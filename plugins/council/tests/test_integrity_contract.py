"""AGE-77 host wiring checks complement, but do not prove, model compliance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IntegrityContractTests(unittest.TestCase):
    """Pin shared instruction boundaries without pretending to run native hosts."""

    def test_both_hosts_require_integrity_contract(self):
        """Each host enters the same executable gate and failure contract."""
        for host in ("claude", "codex"):
            skill = (ROOT / host / "skills/council-vote/SKILL.md").read_text()
            self.assertIn("references/integrity.md", skill)
            self.assertIn("bin/council-state.py", skill)
            self.assertIn("integrity.status", skill)
        adapter = (ROOT / "codex/references/orchestration.md").read_text()
        self.assertIn("references/integrity.md", adapter)
        self.assertNotIn("record the\nworktree status", adapter)

    def test_shared_contract_covers_every_gate_and_limit(self):
        """Accepted state and fresh baselines have explicit preconditions."""
        contract = (ROOT / "references/integrity.md").read_text()
        for word in ("begin-phase", "dispatch-attempted", "delivery", "advance", "recover", "finish",
                     "BASELINE.json", "INTEGRITY.json", "invalidated_findings", "repository_root",
                     "writers_stopped", "ignored", "submodule", "symlink", "restored between",
                     "Do not restore", "concurrent", "permission sandbox"):
            self.assertIn(word, contract)
        for file in ("references/liveness.md", "references/council-protocol.md"):
            self.assertIn("integrity.md", (ROOT / file).read_text())


if __name__ == "__main__":
    unittest.main()
