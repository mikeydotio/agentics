"""Production delivery transitions; only external time and worker messages are controlled."""
import copy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

BIN = Path(os.environ.get("DELIVERY_TEST_BIN", Path(__file__).resolve().parents[1] / "bin"))
sys.path.insert(0, str(BIN))
from delivery_store import execute, inspect_runs


class DeliveryTests(unittest.TestCase):
    """Test the same persisted command boundary required by all owners."""

    def setUp(self):
        """Allocate private files and a deterministic pair of clocks."""
        self.temp = tempfile.TemporaryDirectory(dir="/tmp", prefix="delivery-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "runs" / "batch"
        self.clock = [1000000.0, 1000.0]
        self.result = None

    def call(self, command, **data):
        """Call production persistence with the last observed revision."""
        if self.result:
            data.setdefault("revision", self.result["state"]["revision"])
        self.result = execute(self.root, command, data, clock=lambda: tuple(self.clock))
        return self.result

    def init(self, owner="agents", host="codex", writers=(False,), roles=None, capacity=3):
        """Define all work before any native dispatch."""
        return self.call("init", owner=owner, host=host, session="session-1", step="research",
                         capacity=capacity, tasks=[dict(task_id=str(i), task=f"Measure {i}",
                         role=(roles or ["investigator"] * len(writers))[i], writer=w)
                         for i, w in enumerate(writers)])

    def task(self, index=0):
        """Read one current attempt."""
        return self.result["state"]["tasks"][index]

    def event(self, kind, index=0, **fields):
        """Record an observed transport event for an exact attempt."""
        return self.call("record", task_id=self.task(index)["task_id"],
                         attempt_id=self.task(index)["attempt_id"], kind=kind, **fields)

    def dispatch(self, index=0):
        """Assert durable intent exists before returning an external identity."""
        self.event("dispatch-attempted", index)
        persisted = json.loads((self.root / "STATE.json").read_text())
        self.assertEqual(persisted["tasks"][index]["status"], "dispatch-attempted")
        return self.event("dispatched", index, agent_id=f"native-{index}-{self.task(index)['attempt']}")

    def envelope(self, index=0):
        """Create an external result without using production envelope code."""
        t = self.task(index)
        return dict(batch_id=self.result["state"]["batch_id"], task_id=t["task_id"],
                    task_digest=t["task_digest"], attempt_id=t["attempt_id"], kind="result",
                    payload={"summary": "Measured", "commands": ["true"]})

    def deliver(self, index=0, body=None, sender=None):
        """Deliver raw worker bytes and the observed transport sender."""
        return self.event("delivery", index, body=body or json.dumps(self.envelope(index)),
                          sender=sender or self.task(index)["agent_id"])

    def tick(self, seconds):
        """Advance clocks, without sleeping or modifying stored state."""
        self.clock = [v + seconds for v in self.clock]
        return self.call("advance")

    def stop(self, index=0):
        """Confirm both shutdown and the separate integrity gate."""
        return self.event("stopped", index, agent_id=self.task(index)["agent_id"],
                          stopped=True, integrity_ok=True)

    def test_successful_baseline_each_owner_and_host(self):
        """Neither an inert helper nor an always-blocking gate passes this baseline."""
        for owner in ("agents", "forge", "rca"):
            for host in ("claude", "codex"):
                with self.subTest(owner=owner, host=host):
                    self.root = self.root.parent / f"{owner}-{host}"
                    self.result = None
                    self.init(owner, host)
                    self.dispatch()
                    self.deliver()
                    self.stop()
                    self.call("finish", outcome="succeeded", integrity_ok=True)
                    self.assertEqual(self.result["state"]["status"], "succeeded")
                    self.assertFalse(inspect_runs(self.root.parent)["blocked"])
                    self.assertEqual(self.task()["payload"]["summary"], "Measured")

    def test_silent_worker_retries_once_then_fails(self):
        """Silence consumes finite probe and retry budgets, then blocks advancement."""
        self.init()
        self.dispatch()
        self.tick(900)
        self.assertEqual(self.task()["status"], "probing")
        self.tick(30)
        self.assertEqual(self.task()["status"], "stopping")
        self.stop()
        self.dispatch()
        self.tick(300)
        self.assertEqual(self.result["state"]["status"], "failed")
        self.assertEqual(self.task()["attempt"], 2)
        self.assertTrue(inspect_runs(self.root.parent)["blocked"])

    def test_writer_partial_output_survives_without_retry(self):
        """A writer failure cannot replay side effects."""
        self.init(writers=(True,))
        self.dispatch()
        partial = self.root.parent / "partial.txt"
        partial.write_text("valuable partial changes")
        self.tick(1800)
        self.tick(30)
        self.assertEqual(self.result["state"]["status"], "failed")
        self.assertEqual(self.task()["attempt"], 1)
        self.assertEqual(partial.read_text(), "valuable partial changes")

    def test_progress_has_one_extension_and_ceiling(self):
        """Repeated current progress cannot buy unlimited time."""
        self.init()
        self.dispatch()
        self.tick(900)
        self.event("probe-attempted")
        self.event("progress", agent_id=self.task()["agent_id"], working=True, evidence="test battery running")
        deadline = self.task()["deadline"]
        self.tick(250)
        self.event("progress", agent_id=self.task()["agent_id"], working=True, evidence="still running")
        self.assertEqual(self.task()["deadline"], deadline)
        self.tick(50)
        self.stop()
        self.dispatch()
        self.tick(300)
        self.assertEqual(self.result["state"]["status"], "failed")

    def test_identity_rejection_duplicates_and_late_results(self):
        """A correct result is necessary; rejected messages never complete a task."""
        self.init()
        self.dispatch()
        for field in ("batch_id", "task_id", "task_digest", "attempt_id"):
            body = self.envelope()
            body[field] = "stale"
            self.deliver(body=json.dumps(body))
            self.assertEqual(self.task()["status"], "pending")
        self.deliver(sender="wrong-native-id")
        self.assertEqual(self.task()["status"], "pending")
        original = json.dumps(self.envelope())
        self.deliver(body="```json\n" + original + "\n```")
        accepted = copy.deepcopy(self.task()["payload"])
        self.deliver(body=original)
        self.assertEqual(self.task()["payload"], accepted)
        self.stop()
        self.call("finish", outcome="succeeded", integrity_ok=True)
        self.deliver(body=original)
        self.assertEqual(self.result["state"]["status"], "succeeded")
        self.assertGreaterEqual(len([e for e in self.result["state"]["history"]
                                     if e["event"] == "rejected"]), 7)

    def test_exact_deadline_delivery_is_late(self):
        """Deadline transitions run before incoming transport facts."""
        self.init(writers=(True,))
        self.dispatch()
        self.clock = [v + 2100 for v in self.clock]
        self.deliver()
        self.assertNotEqual(self.task()["status"], "accepted")

    def test_error_classes_never_retry(self):
        """Permission, unavailable capability, and integrity failure fail immediately."""
        for category in ("permission", "capability", "integrity"):
            with self.subTest(category=category):
                self.root = self.root.parent / category
                self.result = None
                self.init()
                self.dispatch()
                self.event("failure", reason="Unavailable", category=category)
                self.assertEqual(self.result["state"]["status"], "failed")
                self.assertEqual(self.task()["attempt"], 1)

    def test_malformed_result_routes_to_bounded_retry(self):
        """Malformed delivery from the current sender follows the silence failure path."""
        self.init()
        self.dispatch()
        self.deliver(body="not JSON")
        self.assertEqual(self.task()["status"], "stopping")
        self.tick(30)
        self.assertEqual(self.result["state"]["status"], "failed")

    def test_roster_waves_serialize_writers(self):
        """Finite waves respect slots and never overlap a writer with another task."""
        self.init(writers=(False, False, True, False), capacity=2)
        self.assertEqual([t["status"] for t in self.result["state"]["tasks"]],
                         ["prepared", "prepared", "queued", "queued"])
        ceiling = self.result["state"]["deadline"]
        for i in (0, 1):
            self.dispatch(i)
            self.deliver(i)
            self.stop(i)
        self.call("advance")
        self.assertEqual(self.task(2)["status"], "prepared")
        self.assertEqual(self.task(3)["status"], "queued")
        self.tick(ceiling - self.clock[0])
        self.assertEqual(self.result["state"]["status"], "failed")

    def test_recovery_preserves_deadline_or_interrupts_uncertain_send(self):
        """Only the same observed session can continue confirmed work."""
        self.init()
        self.dispatch()
        deadline = self.task()["deadline"]
        self.tick(10)
        self.call("recover", session="session-1", reachable=[self.task()["agent_id"]])
        self.assertEqual(self.task()["deadline"], deadline)
        self.call("recover", session="new-session", reachable=[])
        self.assertEqual(self.result["state"]["status"], "interrupted")
        self.root = self.root.parent / "uncertain"
        self.result = None
        self.init()
        self.event("dispatch-attempted")
        self.call("recover", session="session-1", reachable=[])
        self.assertEqual(self.result["state"]["status"], "interrupted")

    def test_backward_and_discontinuous_clocks(self):
        """Clock disagreement never refreshes response time."""
        self.init()
        self.dispatch()
        self.clock[0] += 6
        self.call("advance")
        self.assertEqual(self.result["state"]["status"], "interrupted")

    def test_revision_lock_corruption_and_write_failure(self):
        """Persistence failures remain failures, without transport permission."""
        self.init()
        before = (self.root / "STATE.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "revision"):
            self.call("advance", revision=-1)
        with (self.root / ".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, "busy"):
                self.call("advance")
        with patch("delivery_store.os.replace", side_effect=OSError("disk failure")):
            with self.assertRaisesRegex(OSError, "disk failure"):
                self.call("advance")
        self.assertEqual((self.root / "STATE.json").read_bytes(), before)
        (self.root / "STATE.json").write_text('{"status":"succeeded"}')
        self.assertTrue(inspect_runs(self.root.parent)["blocked"])

    def test_cleanup_and_explicit_reconciliation(self):
        """Survivors prevent reconciliation but cannot delay the terminal failure."""
        self.init(writers=(True,))
        self.dispatch()
        native = self.task()["agent_id"]
        self.event("failure", category="transport", reason="worker failed")
        deadline = self.result["state"]["cleanup_deadline"]
        with self.assertRaises(ValueError):
            self.call("finish", outcome="reconciled", reason="reviewed",
                      integrity_ok=True, artifacts_reconciled=True)
        self.tick(31)
        self.assertEqual(self.result["state"]["cleanup_deadline"], deadline)
        self.assertFalse(self.result["actions"])
        self.assertIn(native, self.result["state"]["remaining"])
        self.stop()
        self.call("finish", outcome="reconciled", reason="partial artifacts preserved and removed from gates",
                  integrity_ok=True, artifacts_reconciled=True)
        self.assertFalse(inspect_runs(self.root.parent)["blocked"])

    def test_rejected_accepted_result_returns_to_running_for_retry(self):
        """A semantic rejection revokes readiness and stale payload before correction."""
        self.init()
        self.dispatch()
        self.deliver()
        self.assertEqual(self.result["state"]["status"], "ready")
        ceiling = self.result["state"]["deadline"]
        self.event("failure", category="transport", reason="owner rejects off-topic result")
        self.assertEqual(self.result["state"]["status"], "running")
        self.assertNotIn("finish", [a["kind"] for a in self.result["actions"]])
        self.stop()
        self.assertIsNone(self.task()["payload"])
        self.dispatch()
        self.deliver()
        self.stop()
        self.call("finish", outcome="succeeded", integrity_ok=True)
        self.assertEqual(self.result["state"]["deadline"], ceiling)

    def test_explicit_failure_preserves_uncertain_dispatch(self):
        """A terminal label cannot erase durable evidence of an uncertain send."""
        self.init()
        self.event("dispatch-attempted")
        self.call("finish", outcome="failed", reason="native call returned no identity")
        with self.assertRaisesRegex(ValueError, "uncertain"):
            self.call("finish", outcome="reconciled", reason="reviewed",
                      integrity_ok=True, artifacts_reconciled=True)
        self.root = self.root.parent / "never-sent"
        self.result = None
        self.init()
        self.call("finish", outcome="interrupted", reason="cancelled before dispatch")
        self.call("finish", outcome="reconciled", reason="nothing dispatched; artifacts reviewed",
                  integrity_ok=True, artifacts_reconciled=True)
        self.assertEqual(self.result["state"]["status"], "reconciled")

    def test_cleanup_after_reboot_has_its_own_finite_clock(self):
        """A discontinuous original clock cannot renew terminal stop actions."""
        self.init(writers=(True,))
        self.dispatch()
        self.clock = [self.clock[0] - 10000, 1.0]
        self.call("advance")
        self.assertEqual(self.result["state"]["status"], "interrupted")
        self.tick(31)
        self.assertFalse(self.result["actions"])

    def test_missing_failure_reason_is_a_worker_failure(self):
        """Valid JSON with an invalid failure body follows bounded transport failure."""
        self.init()
        self.dispatch()
        envelope = self.envelope()
        envelope["kind"] = "failure"
        self.deliver(body=json.dumps(envelope))
        self.assertEqual(self.task()["status"], "stopping")

    def test_stale_progress_cannot_earn_extension(self):
        """Only the observed native identity from this attempt can earn time."""
        self.init()
        self.dispatch()
        self.tick(900)
        self.event("probe-attempted")
        deadline = self.task()["deadline"]
        self.event("progress", agent_id="stale-native", working=True, evidence="working")
        self.assertEqual(self.task()["deadline"], deadline)
        self.assertEqual(self.task()["status"], "probing")

    def test_real_cli_clock_survives_separate_processes(self):
        """The production clock epoch must survive separate macOS Python processes."""
        data = dict(owner="agents", host="codex", session="cli-parent", step="smoke", capacity=1,
                    tasks=[dict(task_id="one", task="Read only", role="skeptic", writer=False)])
        def run(command, value):
            result = subprocess.run([sys.executable, "-B", str(BIN / "agent-delivery.py"),
                                     command, str(self.root)], input=json.dumps(value),
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return json.loads(result.stdout)["state"]
        first = run("init", data)
        time.sleep(6)
        second = run("advance", dict(revision=first["revision"]))
        self.assertEqual(second["status"], "running")
        self.assertGreaterEqual(second["last_mono"] - first["created_mono"], 5)
        self.assertEqual(second["deadline"], first["deadline"])

    def test_command_line_and_missing_or_legacy_state(self):
        """Installed CLI runs independently and reports malformed input context."""
        result = subprocess.run([sys.executable, str(BIN / "agent-delivery.py"), "init", str(self.root)],
                                input='{}', text=True, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)["ok"])
        self.assertFalse(inspect_runs(self.root.parent)["blocked"])
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "old-report.md").write_text("unknown legacy dispatch")
        self.assertTrue(inspect_runs(self.root.parent)["blocked"])


if __name__ == "__main__":
    unittest.main()
