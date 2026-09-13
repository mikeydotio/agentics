"""Packaging and instruction contracts; these do not simulate model compliance."""

import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STEPS = {"rca", "intake", "reproduce", "locate", "diagnose", "report", "fix", "postmortem"}


class HostContracts(unittest.TestCase):
    """Protect Claude and validate the independently loaded Codex instruction tree."""

    def test_claude_implementations_preserved(self):
        """The dispatch indirection must preserve the original eight implementations."""
        baseline = json.loads((ROOT / "tests/claude-skill-baseline.json").read_text())
        self.assertEqual(set(baseline), STEPS)
        for step, expected in baseline.items():
            with self.subTest(step=step):
                body = (ROOT / f"claude/skills/{step}/SKILL.md").read_bytes()
                normalized = re.sub(rb"\n<!-- AGE-104 DELIVERY BEGIN -->.*?<!-- AGE-104 DELIVERY END -->\n", b"", body, flags=re.S)
                self.assertEqual(body.count(b"<!-- AGE-104 DELIVERY BEGIN -->"), 1)
                self.assertEqual(hashlib.sha256(normalized).hexdigest(), expected)

    def test_dispatch_routes_every_entrypoint(self):
        """Host aliases cannot select or mix implementation trees."""
        for step in STEPS:
            with self.subTest(step=step):
                text = (ROOT / f"skills/{step}/SKILL.md").read_text()
                original = (ROOT / f"claude/skills/{step}/SKILL.md").read_text()
                self.assertEqual(text.split("---", 2)[1], original.split("---", 2)[1],
                                 "Claude invocation metadata changed")
                self.assertIn("HOST_DISPATCH_VERSION: 1", text)
                for host in ("claude", "codex"):
                    self.assertIn(f"<plugin-root>/{host}/skills/{step}/SKILL.md", text)
                self.assertIn("authoritative runtime identity", text)
                self.assertIn("Environment compatibility aliases are not authoritative", text)
                self.assertIn("Ambiguous plugin host", text)

    def test_codex_tree_and_resources(self):
        """All literal resource links resolve, including host-specific references."""
        skills = list((ROOT / "codex/skills").glob("*/SKILL.md"))
        self.assertEqual({p.parent.name for p in skills}, STEPS)
        docs = skills + list((ROOT / "codex/references").glob("*.md"))
        checked = 0
        for path in docs:
            text = path.read_text()
            with self.subTest(path=path):
                self.assertNotRegex(text, r"CLAUDE_PLUGIN_ROOT|AskUserQuestion|subagent_type|/clear|`/rca(?: |`)")
                self.assertNotRegex(text, r"(?m)^(argument-hint|model|effort):")
                for target in re.findall(r"<plugin-root>/([^\s`\"),;]+)", text):
                    if "<" not in target:
                        self.assertTrue((ROOT / target).exists(), target)
                        checked += 1
                for command in re.findall(r"bash ([^\n`]+)", text):
                    if "<plugin-root>" in command:
                        self.assertTrue(command.startswith('"<plugin-root>/'), command)
                if path in skills:
                    self.assertIn("four directories", text)
                    self.assertIn("codex/references/runtime.md", text)
        self.assertGreater(checked, 30)

    def test_native_agent_and_authorization_contract(self):
        """Native dispatch keeps independent review and explicit authorization gates."""
        runtime = (ROOT / "codex/references/runtime.md").read_text()
        for token in ("spawn_agent", "followup_task", "wait_agent", "interrupt_agent",
                      "resolve-agents-root.sh", "resolve-agent.sh", "override-only",
                      "pre-dispatch", "prompt", "request_user_input", "HANDOFF.md",
                      "canonical role", "RCA override", "Do not spawn further agents"):
            self.assertIn(token, runtime)
        self.assertIn("silence", runtime)
        for step, tokens in {
            "reproduce": ["REPRO.md", "OVERRIDE.md"],
            "diagnose": ["≥2", "CHALLENGE.md", "INCONCLUSIVE.md"],
            "report": ["APPROVAL.md", "handoff"],
            "fix": ["decision: fix", "RED", "GREEN", "refactor:"],
            "postmortem": ["AGENTS.md", "POSTMORTEM.md"],
        }.items():
            text = (ROOT / f"codex/skills/{step}/SKILL.md").read_text()
            for token in tokens:
                self.assertIn(token, text)

    def test_codex_manifest(self):
        """The native manifest exposes the same eight public skill names."""
        manifest = json.loads((ROOT / ".codex-plugin/plugin.json").read_text())
        self.assertEqual(manifest["name"], "rca")
        self.assertEqual(manifest["version"], json.loads((ROOT / ".claude-plugin/plugin.json").read_text())["version"])
        self.assertEqual(manifest["skills"], "./skills/")
        self.assertFalse((ROOT / "hooks").exists())
