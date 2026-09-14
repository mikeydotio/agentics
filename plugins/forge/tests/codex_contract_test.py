"""Instruction and packaging contracts, not a simulation of model compliance."""
import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STEPS = set(json.loads((ROOT / "tests/claude-skill-baseline.json").read_text()))


class Contracts(unittest.TestCase):
    """Keep every original Claude entrypoint and validate the Codex resource graph."""

    def test_claude_bytes_and_metadata(self):
        """Dispatch must retain both implementation bytes and registration metadata."""
        baseline = json.loads((ROOT / "tests/claude-skill-baseline.json").read_text())
        self.assertEqual(len(baseline), 12)
        for step, digest in baseline.items():
            with self.subTest(step=step):
                original = (ROOT / f"claude/skills/{step}/SKILL.md").read_bytes()
                normalized = re.sub(rb"\n<!-- AGE-104 DELIVERY BEGIN -->.*?<!-- AGE-104 DELIVERY END -->\n", b"", original, flags=re.S)
                normalized = re.sub(rb"\n<!-- AGE-55 INTEGRITY BEGIN -->.*?<!-- AGE-55 INTEGRITY END -->\n", b"", normalized, flags=re.S)
                edits = json.loads((ROOT / "tests/claude-liveness-edits.json").read_text())
                for before, after in edits.get(f"claude/skills/{step}/SKILL.md", []):
                    self.assertEqual(normalized.count(after.encode()), 1)
                    normalized = normalized.replace(after.encode(), before.encode())
                self.assertEqual(hashlib.sha256(normalized).hexdigest(), digest)
                public = (ROOT / f"skills/{step}/SKILL.md").read_text()
                self.assertEqual(original.decode().split("---", 2)[1], public.split("---", 2)[1])
                for host in ("claude", "codex"):
                    self.assertIn(f"<plugin-root>/{host}/skills/{step}/SKILL.md", public)
                self.assertIn("authoritative runtime identity", public)
                self.assertIn("Environment compatibility aliases are not authoritative", public)

    def test_codex_resources_and_calls(self):
        """Native steps have quoted real resource paths and no active Claude calls."""
        skills = list((ROOT / "codex/skills").glob("*/SKILL.md"))
        self.assertEqual({p.parent.name for p in skills}, STEPS)
        checked = 0
        for path in (ROOT / "codex").rglob("*.md"):
            body = path.read_text()
            with self.subTest(path=path):
                self.assertNotRegex(body, r"CLAUDE_PLUGIN_ROOT|AskUserQuestion|subagent_type|Agent\(|run_in_background")
                self.assertNotRegex(body, r"(?m)^(model|effort|argument-hint):")
                self.assertNotRegex(body, r"/clear|claude -p")
                self.assertNotIn("Evaluator has NO Write/Edit tools", body)
                self.assertNotIn("verify a clean working tree; preserve pre-existing changes", body)
                for target in re.findall(r'<plugin-root>/([^\s\x60"),;]+)', body):
                    if "<" not in target:
                        self.assertTrue((ROOT / target).exists(), target)
                        checked += 1
                if path in skills:
                    self.assertEqual(path.parent.parent.parent.parent, ROOT)
                    self.assertIn("three directories", body)
                    self.assertIn("codex/references/runtime.md", body)
        self.assertGreater(checked, 40)

    def test_native_invariants(self):
        """The port retains complete pipeline and independent evaluation contracts."""
        runtime = (ROOT / "codex/references/runtime.md").read_text()
        for token in ("spawn_agent", "followup_task", "wait_agent", "interrupt_agent",
                      "resolve-dependency.sh", "resolve-agent.sh", "request_user_input",
                      "canonical role", "Forge override", "Do not spawn further agents",
                      "integrity", "permissions", "incomplete", "concurrency"):
            self.assertIn(token, runtime)
        loop = (ROOT / "codex/references/execution-loop.md").read_text()
        for token in ("pre-gen", "pre-eval", "full-tree", "forge-verdict.sh",
                      "forge-prechecks.sh", "forge-loop-state.sh", "forge-lock.sh"):
            self.assertIn(token, loop)
        self.assertIn("ok: false", runtime)

    def test_manifest(self):
        """Exactly the common entrypoints are registered with the existing identity."""
        m = json.loads((ROOT / ".codex-plugin/plugin.json").read_text())
        self.assertEqual(m["name"], "forge")
        self.assertEqual(m["skills"], "./skills/")
        self.assertEqual(m["version"], json.loads((ROOT / ".claude-plugin/plugin.json").read_text())["version"])


if __name__ == "__main__":
    unittest.main()
