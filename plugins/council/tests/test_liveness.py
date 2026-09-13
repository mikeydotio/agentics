"""Exercise production Council commands; only time and agent delivery are synthetic."""
import copy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

BIN = Path(os.environ.get("COUNCIL_TEST_ROOT", Path(__file__).resolve().parents[1])) / "bin"
sys.path.insert(0, str(BIN))
from council_store import execute


class CouncilTests(unittest.TestCase):
    """Drive the same persisted transition boundary used by both hosts."""

    def setUp(self):
        """Create an isolated sitting and controllable clock."""
        self.temp = tempfile.TemporaryDirectory(prefix="council-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = [1000000.0, 1000.0]
        self.result = execute(self.root, "init", {
            "question": "Which migration?", "chair": "session-1", "host": "codex",
            "archetypes": ["architect", "database", "challenger"],
        }, lambda: tuple(self.now))

    def call(self, command, **data):
        """Send a command with the last observed revision."""
        data.setdefault("revision", self.result["state"]["revision"])
        self.result = execute(self.root, command, data, lambda: tuple(self.now))
        return self.result

    def tick(self, seconds):
        """Advance both clocks without sleeping."""
        self.now = [x + seconds for x in self.now]
        return self.call("advance")

    def seat(self, n):
        """Return a seat's current attempt."""
        return self.result["state"]["seats"][str(n)]

    def event(self, n, kind, **data):
        """Record an event for the current attempt."""
        return self.call("record", seat=n, attempt_id=self.seat(n)["attempt_id"],
                         kind=kind, **data)

    def dispatch(self, n):
        """Prove intent precedes a confirmed native agent identity."""
        if self.seat(n)["status"] == "stopping":
            self.event(n, "stopped", agent_id=f"agent-{n}", stopped=True)
        self.event(n, "dispatch-attempted")
        self.assertEqual(self.seat(n)["status"], "dispatch-attempted")
        self.event(n, "dispatched", agent_id=f"agent-{n}")

    def begin(self, phase="research"):
        """Dispatch the full panel before collecting responses."""
        self.call("begin-phase", phase=phase)
        for n in (1, 2, 3):
            self.dispatch(n)

    def payload(self, n):
        """Provide a valid native phase payload."""
        phase = self.result["state"]["phase"]
        if phase == "research":
            return {"summary": f"Option {n}", "rationale": "Measured", "risks": "Cost",
                    "confidence": "high"}
        if phase == "vote":
            return {"choice": "A", "reason": "Best fit"}
        if phase == "deliberation":
            return {"seat": n, "action": "stand", "revised_proposal":
                    self.result["state"]["proposals"][self.seat(n)["proposal_label"]],
                    "delta": "no change"}
        labels = list(self.result["state"]["proposals"])
        return dict(zip(("first", "second", "third"), labels), reason="Best fit")

    def envelope(self, n, **changes):
        """Build the wire envelope, independently of production validation."""
        s = self.result["state"]
        result = {"council_id": s["council_id"], "question_digest": s["question_digest"],
                  "phase": s["phase"], "seat": n, "attempt_id": self.seat(n)["attempt_id"],
                  "kind": "result", "payload": self.payload(n)}
        result.update(changes)
        return result

    def deliver(self, n, envelope=None, fenced=False, sender=None):
        """Deliver an external agent message through production parsing."""
        body = json.dumps(envelope or self.envelope(n))
        if fenced:
            body = "```json\n" + body + "\n```"
        return self.event(n, "delivery", sender=sender or f"agent-{n}", body=body)

    def retry(self, n):
        """Acknowledge stopping the old run before dispatching its retry."""
        self.event(n, "stopped", agent_id=f"agent-{n}", stopped=True)
        self.dispatch(n)

    def resolve_research(self):
        """Complete the baseline proposal phase."""
        self.begin()
        for n in (1, 2, 3):
            self.deliver(n)

    def test_baseline_all_three_dispatch_and_complete(self):
        """An inert or always-aborting implementation cannot pass the baseline."""
        self.resolve_research()
        self.assertEqual(self.result["state"]["status"], "phase-complete")
        self.assertEqual(set(self.result["state"]["proposals"]), {"A", "B", "C"})
        self.assertEqual(sum(h["event"] == "dispatched" for h in
                             self.result["state"]["history"]), 3)
        self.assertFalse((self.root / "ABORT.md").exists())
        self.begin("vote")
        for n in (1, 2, 3):
            self.deliver(n, fenced=n == 2)
        self.call("finish", outcome="decision", markdown="# Council Decision\n\nOption 1")
        self.assertEqual(self.result["state"]["status"], "decided")
        self.assertIn("Option 1", (self.root / "DECISION.md").read_text())

    def test_two_silent_seats_retry_abstain_abort(self):
        """Silent agents hit the same retry and abstention path as bad JSON."""
        self.begin()
        self.deliver(1)
        self.tick(900)
        self.assertEqual(self.seat(2)["status"], "probing")
        self.tick(30)
        for n in (2, 3):
            self.assertEqual(self.seat(n)["retry_count"], 1)
            self.retry(n)
        self.tick(300)
        self.assertEqual(self.result["state"]["status"], "aborted")
        self.assertEqual(self.seat(2)["status"], "abstained")
        self.assertIn("Seat 2", (self.root / "ABORT.md").read_text())
        self.assertFalse((self.root / "DECISION.md").exists())

    def test_one_silent_seat_two_proposal_slate(self):
        """Remaining voters rank exactly the surviving proposals."""
        self.begin()
        self.deliver(1)
        self.deliver(3)
        self.tick(900)
        self.tick(30)
        self.retry(2)
        self.tick(300)
        self.assertEqual(self.result["state"]["status"], "phase-complete")
        self.assertEqual(set(self.result["state"]["proposals"]), {"A", "B"})
        self.assertIn("research", (self.root / "PANEL.md").read_text())
        self.begin("vote")
        for n in (1, 2, 3):
            self.deliver(n, self.envelope(n, payload={"choice": "A" if n < 3 else "B",
                                                     "reason": "Domain"}))
        self.call("begin-phase", phase="deliberation")
        self.assertEqual(set(self.result["state"]["participants"]), {1, 3})
        for n in (1, 3):
            self.dispatch(n)
            self.deliver(n)
        self.begin("runoff")
        for n in (1, 2, 3):
            self.deliver(n)
        self.assertEqual(self.result["state"]["status"], "phase-complete")

    def test_working_extension_is_bounded_and_retry_can_succeed(self):
        """Eleven-minute research survives; repeated progress buys no more time."""
        self.begin()
        self.tick(660)
        self.deliver(1)
        self.deliver(2)
        self.tick(240)
        self.event(3, "liveness", agent_id="agent-3", working=True, evidence="battery running")
        self.assertEqual(self.seat(3)["deadline"], 1001200)
        self.tick(299)
        self.event(3, "liveness", agent_id="agent-3", working=True, evidence="still running")
        self.assertEqual(self.seat(3)["deadline"], 1001200)
        self.tick(1)
        self.retry(3)
        self.tick(299)
        self.deliver(3)
        self.assertEqual(self.result["state"]["status"], "phase-complete")

    def test_hard_ceiling_wins_over_queued_delivery(self):
        """A response delivered at the deadline cannot revive its attempt."""
        self.begin()
        self.deliver(1)
        self.deliver(2)
        self.tick(900)
        self.event(3, "liveness", agent_id="agent-3", working=True, evidence="measurement")
        self.tick(300)
        self.retry(3)
        self.tick(300)
        self.deliver(3)
        self.assertEqual(self.seat(3)["status"], "abstained")

    def test_malformed_then_silent_uses_one_retry(self):
        """Mixed failure kinds share a retry counter."""
        self.begin()
        self.event(1, "delivery", sender="agent-1", body="not JSON")
        self.assertEqual(self.seat(1)["retry_count"], 1)
        self.retry(1)
        self.tick(300)
        self.assertEqual(self.seat(1)["status"], "abstained")

    def test_identity_and_duplicate_messages_never_change_tally(self):
        """Well-formed phantom responses are ignored, not tallied."""
        self.begin()
        for changes in ({"council_id": "old"}, {"question_digest": "other"},
                        {"phase": "vote"}, {"seat": 2}, {"attempt_id": "stale"}):
            self.deliver(1, self.envelope(1, **changes))
            self.assertEqual(self.seat(1)["status"], "pending")
        self.deliver(1, sender="stale-agent")
        self.assertEqual(self.seat(1)["status"], "pending")
        self.deliver(1)
        accepted = copy.deepcopy(self.seat(1))
        self.deliver(1)
        self.assertEqual(self.seat(1), accepted)

    def test_partial_dispatch_and_lost_chair_recovery(self):
        """Uncertain dispatch remains evidence and is never silently replayed."""
        self.call("begin-phase", phase="research")
        self.dispatch(1)
        self.event(2, "dispatch-attempted")
        persisted = json.loads((self.root / "STATE.json").read_text())
        self.assertEqual(persisted["seats"]["2"]["status"], "dispatch-attempted")
        self.assertEqual(persisted["seats"]["3"]["status"], "prepared")
        self.call("recover", chair="new-session", reachable=["agent-1"])
        self.assertEqual(self.result["state"]["status"], "aborted")
        self.assertIn("interrupted", (self.root / "ABORT.md").read_text())

    def test_same_chair_recovery_preserves_deadlines(self):
        """A restart cannot refresh a seat budget or lose accepted results."""
        self.begin()
        self.deliver(1)
        deadline = self.seat(2)["deadline"]
        self.now = [x + 100 for x in self.now]
        self.call("recover", chair="session-1", reachable=["agent-1", "agent-2", "agent-3"])
        self.assertEqual(self.seat(2)["deadline"], deadline)
        self.assertEqual(self.seat(1)["status"], "accepted")

    def test_lost_runtime_identity_aborts_recovery(self):
        """Missing native agents cannot be mistaken for a fresh panel."""
        self.begin()
        self.call("recover", chair="session-1", reachable=[])
        self.assertEqual(self.result["state"]["status"], "aborted")

    def test_clock_discontinuity_aborts(self):
        """Clock jumps cannot extend an unattended wait."""
        self.begin()
        self.now[0] -= 3600
        self.call("advance")
        self.assertEqual(self.result["state"]["status"], "aborted")
        self.assertIn("clock", self.result["state"]["reason"])

    def test_terminal_artifact_recovery_is_idempotent(self):
        """A crash after state persistence can regenerate a missing abort."""
        self.begin()
        self.call("finish", outcome="abort", reason="capability lost")
        expected = (self.root / "ABORT.md").read_text()
        (self.root / "ABORT.md").unlink()
        self.call("recover", chair="session-1", reachable=[])
        self.assertEqual((self.root / "ABORT.md").read_text(), expected)

    def test_revision_and_corrupt_state_fail_without_overwrite(self):
        """Invalid state and stale updates leave the last evidence intact."""
        path = self.root / "STATE.json"
        before = path.read_bytes()
        with self.assertRaisesRegex(ValueError, "revision"):
            self.call("begin-phase", phase="research", revision=999)
        self.assertEqual(path.read_bytes(), before)
        path.write_text('{"schema_version":1}')
        with self.assertRaisesRegex(ValueError, "state"):
            self.call("advance")
        self.assertEqual(path.read_text(), '{"schema_version":1}')

    def test_permission_failure_and_scratch_isolation(self):
        """Denied execution follows normal failure policy with private scratch."""
        self.begin()
        paths = {self.seat(n)["scratch"] for n in (1, 2, 3)}
        self.assertEqual(len(paths), 3)
        for path in paths:
            self.assertTrue(Path(path).is_dir())
        self.event(1, "failure", reason="permission denied")
        self.assertEqual(self.seat(1)["retry_count"], 1)
        self.assertNotIn(self.seat(1)["scratch"], paths)
        self.retry(1)
        self.event(1, "failure", reason="tool unavailable")
        self.assertEqual(self.seat(1)["status"], "abstained")

    def test_finish_requires_completed_vote(self):
        """The chair cannot persist a winner before collecting ballots."""
        self.begin()
        with self.assertRaisesRegex(ValueError, "vote|runoff"):
            self.call("finish", outcome="decision", markdown="fabricated")

    def test_probe_failure_does_not_earn_extension(self):
        """Unknown or idle status cannot prolong the initial attempt."""
        self.begin()
        self.tick(900)
        self.event(1, "liveness", agent_id="agent-1", working=False, evidence="idle")
        self.assertEqual(self.seat(1)["retry_count"], 1)
        self.assertFalse(self.seat(1)["extended"])

    def test_cumulative_clock_drift_cannot_refresh_budget(self):
        """Small clock adjustments must be compared to the original clock pair."""
        self.begin()
        for _ in range(4):
            self.now[0] += 10
            self.now[1] += 12
            self.call("advance")
        self.assertEqual(self.result["state"]["status"], "aborted")

    def test_probes_are_recorded_before_sending_and_never_replayed(self):
        """Recovery must not send a second probe for the same attempt."""
        self.begin()
        self.tick(900)
        self.event(1, "probe-attempted")
        self.call("recover", chair="session-1", reachable=["agent-1", "agent-2", "agent-3"])
        action = next(x for x in self.result["actions"] if x["seat"] == 1)
        self.assertEqual(action["kind"], "wait")

    def test_reduced_slate_retains_original_arrival_order(self):
        """Original reduced-slate labeling remains compatible with archived councils."""
        self.begin()
        self.deliver(3)
        self.deliver(1)
        self.event(2, "failure", reason="tool denied")
        self.retry(2)
        self.event(2, "failure", reason="tool denied again")
        self.assertEqual(self.result["state"]["proposals"]["A"]["summary"], "Option 3")

    def test_abstainer_must_stop_before_next_phase(self):
        """A timed-out run cannot overlap its next phase task."""
        self.begin()
        self.deliver(1)
        self.deliver(2)
        self.event(3, "failure", reason="lost response")
        self.retry(3)
        self.event(3, "failure", reason="still no response")
        self.call("begin-phase", phase="vote")
        self.assertEqual(self.seat(3)["status"], "stopping")
        with self.assertRaisesRegex(ValueError, "invalid event"):
            self.event(3, "dispatch-attempted")

    def test_invalid_phase_payload_types_share_retry_policy(self):
        """Malformed objects never pass just because their values are truthy."""
        self.begin()
        original = copy.deepcopy(self.result)
        raw = (self.root / "STATE.json").read_bytes()
        for value in (None, [], True, 2, "", {}, {"summary": []},
                      {"summary": "x", "rationale": True, "risks": "x", "confidence": "high"},
                      {"summary": "x", "rationale": "x", "risks": "x", "confidence": "certain"}):
            with self.subTest(value=value):
                (self.root / "STATE.json").write_bytes(raw)
                self.result = copy.deepcopy(original)
                self.deliver(1, self.envelope(1, payload=value))
                self.assertEqual(self.seat(1)["retry_count"], 1)

    def test_wrong_vote_and_duplicate_rankings_rejected(self):
        """The vote and runoff validate against the actual proposal set."""
        self.resolve_research()
        self.begin("vote")
        self.deliver(1, self.envelope(1, payload={"choice": [], "reason": "x"}))
        self.assertEqual(self.seat(1)["retry_count"], 1)
        self.retry(1)
        for n in (1, 2, 3):
            self.deliver(n, self.envelope(n, payload={"choice": "ABC"[n - 1], "reason": "x"}))
        self.begin("deliberation")
        for n in (1, 2, 3):
            self.deliver(n)
        self.begin("runoff")
        self.deliver(1, self.envelope(1, payload={"first": "A", "second": "A", "third": "C", "reason": "x"}))
        self.assertEqual(self.seat(1)["retry_count"], 1)

    def test_later_phases_have_five_minute_ceiling(self):
        """Each later dispatch is bounded, not only the initial research."""
        self.resolve_research()
        self.begin("vote")
        for phase in ("vote", "deliberation", "runoff"):
            if phase != "vote":
                self.begin(phase)
            start = self.now[0]
            self.assertEqual(self.result["state"]["hard_deadline"], start + 300)
            if phase == "vote":
                for n in (1, 2):
                    self.deliver(n, self.envelope(n, payload={"choice": "AB"[n - 1], "reason": "x"}))
            else:
                for n in (1, 2):
                    self.deliver(n)
            self.tick(120)
            self.event(3, "liveness", agent_id="agent-3", working=True, evidence="current task running")
            self.tick(60)
            self.retry(3)
            self.tick(120)
            self.assertEqual(self.seat(3)["status"], "abstained")
            self.assertEqual(self.result["state"]["status"], "phase-complete")

    def test_wait_slices_and_expired_recovery(self):
        """Status is read-only; advancing resolves expired waits before acting."""
        self.begin()
        self.tick(899)
        self.assertTrue(all(x["wait_seconds"] == 1 for x in self.result["actions"]))
        self.now = [x + 1000 for x in self.now]
        before = (self.root / "STATE.json").read_bytes()
        self.call("status")
        self.assertEqual((self.root / "STATE.json").read_bytes(), before)
        self.assertTrue(all(x["wait_seconds"] == 0 for x in self.result["actions"]))
        self.call("recover", chair="session-1", reachable=["agent-1", "agent-2", "agent-3"])
        self.assertEqual(self.result["state"]["status"], "aborted")

    def test_cleanup_has_no_unbounded_acknowledgement(self):
        """Remaining agents remain visible after the 30-second cleanup budget."""
        self.begin()
        self.call("finish", outcome="abort", reason="capability unavailable")
        deadline = self.result["state"]["cleanup_deadline"]
        self.tick(30)
        self.assertEqual(self.result["actions"], [])
        self.call("record", kind="cleanup", remaining=["agent-1"])
        self.assertEqual(self.result["state"]["cleanup_deadline"], deadline)
        self.assertIn("agent-1", (self.root / "LIVENESS.md").read_text())

    def test_json_envelope_shapes_and_failure_delivery(self):
        """Fences are consistent and malformed JSON cannot sneak in duplicate keys."""
        self.begin()
        self.event(1, "delivery", sender="agent-1", body='{"seat":1,"seat":2}')
        self.assertEqual(self.seat(1)["retry_count"], 1)
        self.retry(1)
        self.deliver(1, self.envelope(1, kind="failure", reason="permission denied"))
        self.assertEqual(self.seat(1)["status"], "abstained")
        self.event(2, "delivery", sender="agent-2", body='```json\n{}\n```\nextra prose')
        self.assertEqual(self.seat(2)["retry_count"], 1)

    def test_lock_conflict_fails_promptly(self):
        """Competing writers receive a failure instead of another unbounded wait."""
        with (self.root / ".state.lock").open("r+") as locked:
            fcntl.flock(locked, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, "busy"):
                self.call("begin-phase", phase="research")

    def test_persistence_crash_after_terminal_state_is_recoverable(self):
        """Simulate a Markdown I/O failure after a successful terminal commit."""
        self.begin()
        with patch("council_store.render", side_effect=OSError("disk failure")):
            with self.assertRaisesRegex(OSError, "disk failure"):
                self.call("finish", outcome="abort", reason="interrupted delivery")
        state = json.loads((self.root / "STATE.json").read_text())
        self.assertEqual(state["status"], "aborted")
        self.assertFalse((self.root / "ABORT.md").exists())
        self.call("status")
        self.call("recover", chair="session-1", reachable=[])
        self.assertTrue((self.root / "ABORT.md").exists())

    def test_structurally_corrupt_states_fail_without_artifact_changes(self):
        """Valid JSON with broken invariants is still corrupt state."""
        self.begin()
        path = self.root / "STATE.json"
        base = json.loads(path.read_text())
        cases = []
        for change in ({"participants": []}, {"history": [None]}, {"seats": []},
                       {"question_digest": "wrong"}, {"hard_deadline": 99999999}):
            state = copy.deepcopy(base)
            state.update(change)
            cases.append(state)
        state = copy.deepcopy(base)
        state["seats"]["1"]["deadline"] = 99999999
        cases.append(state)
        for state in cases:
            with self.subTest(state=state):
                raw = json.dumps(state)
                path.write_text(raw)
                with self.assertRaisesRegex(ValueError, "state"):
                    self.call("advance")
                self.assertEqual(path.read_text(), raw)

    def test_cli_hosts_and_errors(self):
        """Invoke the shipped executable, including its JSON error serializer."""
        for host in ("claude", "codex"):
            root = self.root / host
            run = subprocess.run([sys.executable, "-W", "error", str(BIN / "council-state.py"), "init", str(root)],
                                 input=json.dumps({"question": "Which?", "chair": "cli", "host": host,
                                                   "archetypes": ["one", "two", "three"]}),
                                 capture_output=True, text=True, timeout=10, check=False)
            self.assertEqual(run.returncode, 0, run.stderr + run.stdout)
            self.assertTrue(json.loads(run.stdout)["ok"])
        run = subprocess.run([sys.executable, str(BIN / "council-state.py"), "advance", str(root)],
                             input='{"revision":999}', capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(run.returncode, 1)
        self.assertIn("revision", json.loads(run.stdout)["error"])

    def test_invalid_commands_fail_before_mutation(self):
        """Bad phase/event input cannot bypass the contextual error boundary."""
        before = (self.root / "STATE.json").read_bytes()
        for command, fields in (("begin-phase", {}), ("begin-phase", {"phase": []}),
                                ("record", {"seat": 1, "kind": "failure", "reason": "x"})):
            with self.subTest(command=command, fields=fields):
                with self.assertRaises(ValueError):
                    self.call(command, **fields)
                self.assertEqual((self.root / "STATE.json").read_bytes(), before)

    def test_failed_attempt_keeps_identity_in_history(self):
        """Retry cannot erase the exact failed native attempt from crash evidence."""
        self.begin()
        old = copy.deepcopy(self.seat(1))
        self.event(1, "failure", reason="tool failed")
        failed = next(h for h in self.result["state"]["history"] if h["event"] == "attempt-failed")
        self.assertEqual(failed["attempt_id"], old["attempt_id"])
        self.assertEqual(failed["agent_id"], "agent-1")
        self.assertEqual(failed["scratch"], old["scratch"])


if __name__ == "__main__":
    unittest.main()
