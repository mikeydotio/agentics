"""Negative controls proving Codex instructions participate in the real doc guards."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Scans(unittest.TestCase):
    """Directory discovery must cover host implementations as well as dispatchers."""

    def test_codex_invalid_story_and_agent_are_rejected(self):
        """Each real scanner must reach invalid statements in an added Codex skill."""
        with tempfile.TemporaryDirectory(prefix="forge scan ", dir="/private/tmp") as tmp:
            root = Path(tmp)
            skill = root / "codex/skills/new-step/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text('## Agent Roster\n- imaginary-specialist\n\n\x60\x60\x60bash\nstory nonexistent-verb AGE-1\n\x60\x60\x60\n')
            for script, key in (("forge-contract-check.sh", "contract_ok"),
                                ("forge-agent-alignment-check.sh", "alignment_ok")):
                args = ["bash", str(ROOT / "bin" / script), str(root)]
                if key == "alignment_ok":
                    args.append(str(ROOT.parent / "agents"))
                result = subprocess.run(args, text=True, capture_output=True, check=True)
                data = json.loads(result.stdout)
                self.assertTrue(data["ok"], result.stdout)
                self.assertFalse(data[key], result.stdout)
                self.assertTrue(any("codex" in p for p in data["files_scanned"]))


if __name__ == "__main__":
    unittest.main()
