"""Audited no-transport reconciliation through real persistence and packaged CLIs."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BIN = Path(os.environ.get("DELIVERY_TEST_BIN", Path(__file__).resolve().parents[1] / "bin"))
sys.path.insert(0, str(BIN))
from delivery_store import execute, inspect_runs


class NotSentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/tmp", prefix="delivery-not-sent-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "runs" / "batch"
        self.clock = [1000000.0, 1000.0]
        self.result = None

    def call(self, command, **data):
        if self.result:
            data.setdefault("revision", self.result["state"]["revision"])
        self.result = execute(self.root, command, data, clock=lambda: tuple(self.clock))
        return self.result

    def init(self, count=1, writer=True, owner="rca", host="codex"):
        self.call("init", owner=owner, host=host, session="original-session", step="no-send",
                  capacity=count, tasks=[dict(task_id=str(i), task=f"Preserve work {i}",
                  role="software-engineer" if writer else "investigator", writer=writer)
                  for i in range(count)])

    def event(self, kind, index=0, **fields):
        task = self.result["state"]["tasks"][index]
        return self.call("record", kind=kind, task_id=task["task_id"],
                         attempt_id=task["attempt_id"], **fields)

    def interrupt(self):
        self.call("finish", outcome="interrupted", reason="Interrupted before native call")

    def prepare(self):
        self.init()
        self.event("dispatch-attempted")
        self.interrupt()

    def attestation(self, index=0):
        s = self.result["state"]
        t = s["tasks"][index]
        return dict(kind="dispatch-not-sent", batch_id=s["batch_id"], task_id=t["task_id"],
                    attempt_id=t["attempt_id"], task_digest=t["task_digest"], session=s["session"],
                    no_transport=True, reason="Owner attests reviewed transcript has no native call",
                    evidence="review://preserved-transcript", evidence_sha256="a" * 64,
                    reviewer="independent-reviewer")

    def reconcile(self, **fields):
        values = dict(outcome="reconciled", reason="Partial evidence preserved and reviewed",
                      integrity_ok=True, artifacts_reconciled=True)
        values.update(fields)
        return self.call("finish", **values)

    def reject_unchanged(self, command, **fields):
        before = (self.root / "STATE.json").read_bytes()
        with self.assertRaises(ValueError):
            self.call(command, **fields)
        self.assertEqual((self.root / "STATE.json").read_bytes(), before)

    def test_verified_no_send_preserves_failure_and_deadlines(self):
        for outcome in ("failed", "interrupted"):
            for owner in ("agents", "forge", "rca"):
                for host in ("claude", "codex"):
                    with self.subTest(outcome=outcome, owner=owner, host=host):
                        self.root = self.root.parent / f"{outcome}-{owner}-{host}"
                        self.result = None
                        self.init(owner=owner, host=host)
                        self.event("dispatch-attempted")
                        self.call("finish", outcome=outcome, reason="Interrupted before native call")
                        original = copy.deepcopy(self.result["state"])
                        attestation = self.attestation()
                        self.clock = [v + 4000 for v in self.clock]
                        self.call("record", **attestation)
                        recorded = self.result["state"]
                        self.assertEqual(recorded["history"][:-1], original["history"])
                        expected_event = dict(attestation)
                        expected_event["event"] = expected_event.pop("kind")
                        expected_event["at"] = self.clock[0]
                        self.assertEqual(recorded["history"][-1], expected_event)
                        self.assertEqual(recorded["status"], outcome)
                        self.assertTrue(inspect_runs(self.root.parent)["blocked"])
                        self.assertEqual(self.result["actions"], [])
                        self.call("status")
                        self.reconcile()
                        final = self.result["state"]
                        self.assertEqual(final["status"], "reconciled")
                        self.assertEqual(final["tasks"], original["tasks"])
                        for key in ("deadline", "created_at", "created_mono", "last_mono", "last_wall",
                                    "cleanup_deadline", "cleanup_mono", "remaining", "reason"):
                            self.assertEqual(final[key], original[key], key)
                        self.assertEqual(self.result["actions"], [])
                        self.assertFalse(inspect_runs(self.root.parent)["blocked"])
                        self.reject_unchanged("finish", outcome="succeeded", integrity_ok=True)

    def test_missing_or_wrong_attestation_is_rejected_without_mutation(self):
        self.prepare()
        valid = self.attestation()
        invalid = [(key, None) for key in valid if key != "kind"]
        invalid += [(key, "wrong") for key in ("batch_id", "task_id", "attempt_id", "task_digest", "session")]
        invalid += [("no_transport", 1), ("no_transport", False), ("reason", " "),
                    ("evidence", " "), ("reviewer", " "), ("evidence_sha256", "g" * 64),
                    ("evidence_sha256", "a" * 63), ("evidence_sha256", "a" * 65),
                    ("agent_id", "native-0"), ("sender", "native-0"),
                    ("payload", {"summary": "result"}), ("body", "result")]
        for field, value in invalid:
            with self.subTest(field=field, value=value):
                candidate = dict(valid)
                if value is None:
                    candidate.pop(field)
                else:
                    candidate[field] = value
                self.reject_unchanged("record", **candidate)
        self.reject_unchanged("record", **valid, revision=0)
        self.reject_unchanged("finish", outcome="reconciled", reason="unknown send",
                              integrity_ok=True, artifacts_reconciled=True)

    def test_same_duplicate_is_idempotent_conflict_is_rejected(self):
        self.prepare()
        data = self.attestation()
        self.call("record", **data)
        original = copy.deepcopy(self.result["state"])
        self.clock = [v + 60 for v in self.clock]
        self.call("record", **data)
        expected = dict(original, revision=original["revision"] + 1)
        self.assertEqual(self.result["state"], expected)
        self.assertEqual(self.result["notices"], [])
        for key in ("reason", "evidence", "reviewer", "evidence_sha256"):
            changed = dict(data, **{key: "b" * 64 if key == "evidence_sha256" else "changed"})
            self.reject_unchanged("record", **changed)

    def test_live_missing_attempt_and_known_dispatch_are_rejected(self):
        self.init()
        self.reject_unchanged("record", **self.attestation())
        self.event("dispatch-attempted")
        self.reject_unchanged("record", **self.attestation())
        self.event("dispatched", agent_id="known-worker")
        self.interrupt()
        self.reject_unchanged("record", **self.attestation())
        self.event("stopped", agent_id="known-worker", stopped=True, integrity_ok=True)
        self.reject_unchanged("record", **self.attestation())
        self.root = self.root.parent / "no-attempt"
        self.result = None
        self.init()
        self.interrupt()
        self.reject_unchanged("record", **self.attestation())

    def test_successful_and_reconciled_records_cannot_accept_attestation(self):
        self.prepare()
        data = self.attestation()
        self.call("record", **data)
        self.reconcile()
        self.reject_unchanged("record", **data)
        self.root = self.root.parent / "success"
        self.result = None
        self.init()
        self.event("dispatch-attempted")
        self.event("dispatched", agent_id="known-worker")
        body = {k: v for k, v in self.attestation().items()
                if k in ("batch_id", "task_id", "attempt_id", "task_digest")}
        body.update(kind="result", payload={"summary": "Actual result"})
        self.event("delivery", sender="known-worker", body=json.dumps(body))
        self.event("stopped", agent_id="known-worker", stopped=True, integrity_ok=True)
        self.call("finish", outcome="succeeded", integrity_ok=True)
        self.reject_unchanged("record", **self.attestation())

    def test_other_uncertain_attempt_survivors_and_review_gates_remain(self):
        self.init(count=3, writer=False)
        for index in range(3):
            self.event("dispatch-attempted", index)
        self.event("dispatched", 2, agent_id="real-survivor")
        self.interrupt()
        self.call("record", **self.attestation())
        self.reject_unchanged("finish", outcome="reconciled", reason="survivor",
                              integrity_ok=True, artifacts_reconciled=True)
        self.event("stopped", 2, agent_id="real-survivor", stopped=True, integrity_ok=True)
        self.reject_unchanged("finish", outcome="reconciled", reason="second send unknown",
                              integrity_ok=True, artifacts_reconciled=True)
        self.call("record", **self.attestation(1))
        for integrity, artifacts in ((False, True), (True, False), (None, True), (True, None)):
            self.reject_unchanged("finish", outcome="reconciled", reason="unverified",
                                  integrity_ok=integrity, artifacts_reconciled=artifacts)
        self.reconcile()
        self.assertEqual(self.result["state"]["status"], "reconciled")

    def test_current_reader_attempt_only_and_no_new_retry(self):
        self.init(writer=False)
        self.event("dispatch-attempted")
        self.event("dispatched", agent_id="prior-reader")
        retired = self.attestation()
        self.event("failure", reason="Transport failed")
        self.event("stopped", agent_id="prior-reader", stopped=True, integrity_ok=True)
        self.event("dispatch-attempted")
        self.interrupt()
        task = copy.deepcopy(self.result["state"]["tasks"][0])
        self.assertEqual(task["attempt"], 2)
        self.reject_unchanged("record", **retired)
        self.call("record", **self.attestation())
        self.reconcile()
        self.assertEqual(self.result["state"]["tasks"][0], task)
        self.assertEqual(self.result["actions"], [])

    def test_tampered_stored_attestation_fails_closed_on_reload(self):
        self.prepare()
        self.call("record", **self.attestation())
        self.reconcile()
        original = copy.deepcopy(self.result["state"])
        variants = []
        for field in ("batch_id", "task_id", "attempt_id", "task_digest", "session", "no_transport",
                      "reason", "evidence", "evidence_sha256", "reviewer", "at"):
            tampered = copy.deepcopy(original)
            tampered["history"][-2].pop(field)
            variants.append(("missing-" + field, tampered))
        for field in ("batch_id", "task_id", "attempt_id", "task_digest", "session", "evidence_sha256"):
            tampered = copy.deepcopy(original)
            tampered["history"][-2][field] = "wrong"
            variants.append(("wrong-" + field, tampered))
        for field, value in (("agent_id", "native-surprise"), ("payload", {}), ("status", "accepted"),
                             ("stopped", True), ("integrity_ok", True)):
            tampered = copy.deepcopy(original)
            tampered["tasks"][0][field] = value
            variants.append(("task-" + field, tampered))
        for event in ("dispatch-attempted", "interrupted"):
            tampered = copy.deepcopy(original)
            tampered["history"] = [e for e in tampered["history"] if e["event"] != event]
            variants.append(("missing-history-" + event, tampered))
        tampered = copy.deepcopy(original)
        tampered["history"].append(dict(tampered["history"][1], event="dispatched", reason="known-worker"))
        variants.append(("conflicting-dispatch-history", tampered))
        tampered = copy.deepcopy(original)
        tampered["history"].append(copy.deepcopy(tampered["history"][-2]))
        variants.append(("duplicate-evidence", tampered))
        tampered = copy.deepcopy(original)
        tampered["history"] = [e for e in tampered["history"] if e["event"] != "dispatch-not-sent"]
        variants.append(("removed-evidence", tampered))
        tampered = copy.deepcopy(original)
        tampered["history"][-2]["event"] = "unrecognized-evidence"
        variants.append(("renamed-evidence", tampered))
        for name, tampered in variants:
            with self.subTest(name=name):
                (self.root / "STATE.json").write_text(json.dumps(tampered))
                with self.assertRaises(ValueError):
                    self.call("status")
                self.assertTrue(inspect_runs(self.root.parent)["blocked"])
        (self.root / "STATE.json").write_text(json.dumps(original))
        self.call("status")
        self.assertFalse(inspect_runs(self.root.parent)["blocked"])

    def test_each_packaged_cli_accepts_only_reviewed_no_send(self):
        repository = Path(__file__).resolve().parents[3]
        for owner in ("agents", "rca", "forge"):
            with self.subTest(owner=owner):
                directory = Path(self.temp.name) / owner / "batch"
                cli = repository / "plugins" / owner / "bin/agent-delivery.py"
                state = None

                def command(name, values, ok=True):
                    nonlocal state
                    if state is not None:
                        values["revision"] = state["revision"]
                    proc = subprocess.run([sys.executable, "-B", str(cli), name, str(directory)],
                                          input=json.dumps(values), capture_output=True,
                                          text=True, timeout=30)
                    self.assertEqual(proc.returncode, 0 if ok else 1, proc.stdout + proc.stderr)
                    result = json.loads(proc.stdout)
                    self.assertIs(result["ok"], ok)
                    if ok:
                        state = result["state"]
                    return result

                command("init", dict(owner=owner, host="codex", session="cli-session", step="repair",
                        capacity=1, tasks=[dict(task_id="writer", task="No transport", role="engineer", writer=True)]))
                task = state["tasks"][0]
                ids = dict(task_id=task["task_id"], attempt_id=task["attempt_id"])
                command("record", dict(ids, kind="dispatch-attempted"))
                command("finish", dict(outcome="interrupted", reason="No native invocation"))
                command("finish", dict(outcome="reconciled", reason="unknown send",
                                       integrity_ok=True, artifacts_reconciled=True), ok=False)
                command("record", dict(ids, kind="dispatch-not-sent", batch_id=state["batch_id"],
                        task_digest=task["task_digest"], session="cli-session", no_transport=True,
                        reason="Reviewed trace", evidence="review://trace", evidence_sha256="a" * 64,
                        reviewer="independent-reviewer"))
                command("finish", dict(outcome="reconciled", reason="Evidence preserved",
                                       integrity_ok=True, artifacts_reconciled=True))
                command("status", {})
                self.assertEqual(state["status"], "reconciled")
                self.assertEqual(state["tasks"], [dict(task, status="interrupted")])


if __name__ == "__main__":
    unittest.main()
