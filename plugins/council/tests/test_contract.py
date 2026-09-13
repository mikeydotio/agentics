"""Prevent either host or a phase template from bypassing production liveness."""
import os
from pathlib import Path
import re
import unittest

ROOT = Path(os.environ.get("COUNCIL_TEST_ROOT", Path(__file__).resolve().parents[1]))


class ContractTests(unittest.TestCase):
    """Check instruction integration, separately from executable policy tests."""

    def test_existing_voting_protocol_baseline(self):
        """Historical and repaired protocols both retain real voting phases."""
        protocol = (ROOT / "references/council-protocol.md").read_text()
        for phase in range(7):
            self.assertIn(f"## Phase {phase}", protocol)
        for artifact in ("proposals-round-1.md", "vote-round-1.md", "deliberation.md",
                         "proposals-round-2.md", "vote-round-2.md", "DECISION.md", "ABORT.md"):
            self.assertIn(artifact, protocol)
        voting = (ROOT / "references/voting-mechanics.md").read_text()
        for rule in ("Single-choice", "Instant-Runoff", "chair tiebreaker", "does not"):
            if rule == "does not":
                self.assertIn("chair never", voting)
            else:
                self.assertIn(rule.lower(), voting.lower())

    def test_all_dispatch_phases_use_shared_helper(self):
        """Each dispatch phase must explicitly enter the same production loop."""
        protocol = (ROOT / "references/council-protocol.md").read_text()
        phases = re.split(r"## Phase \d+[^\n]*\n", protocol)
        for number, phase in ((2, "research"), (3, "vote"), (4, "deliberation"), (5, "runoff")):
            section = phases[number + 1]
            self.assertIn("begin-phase", section)
            self.assertIn(f'phase:"{phase}"', section)
            self.assertIn("liveness.md", section)

    def test_host_delivery_contracts_agree(self):
        """Both hosts require identity, bounded collection, and recoverable state."""
        for host in ("claude", "codex"):
            skill = (ROOT / host / "skills/council-vote/SKILL.md").read_text()
            self.assertIn("references/liveness.md", skill)
            self.assertIn("bin/council-state.py", skill)
            self.assertIn("1500 seconds", skill)
            self.assertIn("300 seconds", skill)
        claude = (ROOT / "claude/skills/council-vote/SKILL.md").read_text()
        for rule in ("SendMessage", "string containing", "fenced JSON envelope", "returned agent ID"):
            self.assertIn(rule, claude)
        codex = (ROOT / "codex/references/orchestration.md").read_text()
        for rule in ("spawn_agent", "followup_task", "wait_agent", "list_agents", "interrupt_agent",
                     "30000 milliseconds", "probe", "recover"):
            self.assertIn(rule, codex)
        for old in ("never backgrounded", "Reject markdown", "Do not wrap in markdown code fences"):
            self.assertNotIn(old, claude + codex + (ROOT / "references/council-protocol.md").read_text())

    def test_shared_contract_names_failures_and_deadlines(self):
        """The durable-state path is mandatory and contains explicit finite defaults."""
        contract = (ROOT / "references/liveness.md").read_text()
        for token in ("STATE.json", "probe-attempted", "dispatch-attempted", "revision", "recover",
                      "1500 s", "300 s", "30 seconds", "ABORT.md", "LIVENESS.md", "scratch",
                      "Do not spawn further agents", "user", "clock", "working:false"):
            if token == "working:false":
                self.assertIn("unknown is false", contract)
            else:
                self.assertIn(token, contract)


if __name__ == "__main__":
    unittest.main()
