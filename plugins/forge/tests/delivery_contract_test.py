"""Audit every shipped Forge specialist entrypoint for the owner delivery contract."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeliveryContracts(unittest.TestCase):
    """A new host entrypoint cannot silently bypass the finite delivery policy."""

    def test_every_host_step_loads_delivery(self):
        """Standalone and orchestrated invocations have the same prerequisite."""
        for host in ("claude", "codex"):
            skills = list((ROOT / host / "skills").glob("*/SKILL.md"))
            self.assertEqual(len(skills), 12)
            for path in skills:
                with self.subTest(path=path):
                    self.assertTrue("references/delivery.md" in path.read_text(), str(path))
                    self.assertTrue("delivery_recovery" in path.read_text(), str(path))

    def test_no_unbounded_foreground_contract(self):
        """All actual dispatch documents must reach the liveness reference."""
        count = 0
        for directory in ("references", "codex/references", "claude/skills", "codex/skills"):
            for path in (ROOT / directory).rglob("*.md"):
                body = path.read_text()
                with self.subTest(path=path):
                    self.assertNotRegex(body, r"All agent spawns are \*\*foreground|All agents run in foreground|foreground-only agents|orchestrator blocks until all agents return")
                    if path.name != "delivery.md" and re.search(r"Agent\(|spawn_agent|\bSpawn .*agents?", body):
                        count += 1
                        self.assertRegex(body, r"delivery\.md|runtime\.md|team-roles\.md")
        self.assertGreater(count, 10)


if __name__ == "__main__":
    unittest.main()
