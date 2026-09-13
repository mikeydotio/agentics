"""Exercise the production resolver with only the external registry stubbed."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AgentResolution(unittest.TestCase):
    """Installed identity must win over stale or disabled cache entries."""

    def setUp(self):
        """Create an isolated install layout, including spaces in every root."""
        self.temp = tempfile.TemporaryDirectory(prefix="rca resolver ", dir="/private/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plugin = self.root / "market/rca/3.9.1"
        self.plugin.joinpath("bin").mkdir(parents=True)
        shutil.copy(ROOT / "bin/resolve-agents-root.sh", self.plugin / "bin")
        self.fakebin = self.root / "fake-bin"
        self.fakebin.mkdir()
        codex = self.fakebin / "codex"
        codex.write_text('#!/bin/sh\ncat "$REGISTRY_FILE"\nexit "${REGISTRY_EXIT:-0}"\n')
        codex.chmod(0o755)
        self.registry = self.root / "registry.json"
        self.registry.write_text('{"installed":[]}')
        self.env = dict(os.environ, CODEX_HOME=str(self.root / "codex home"),
                        REGISTRY_FILE=str(self.registry), PATH=f"{self.fakebin}:{os.environ['PATH']}")
        self.env.pop("AGENTS_PLUGIN_ROOT", None)

    def agents(self, path, version="3.9.1"):
        """Copy real role files and their production resolver into the fixture."""
        source = ROOT.parent / "agents"
        for directory in ("agents", "bin", "references", ".codex-plugin"):
            shutil.copytree(source / directory, path / directory)
        manifest = path / ".codex-plugin/plugin.json"
        data = json.loads(manifest.read_text())
        data["version"] = version
        manifest.write_text(json.dumps(data))
        return path.resolve()

    def registered(self, path=None, version="3.9.1", enabled=True, market="team"):
        """Write one installed plugin record in the actual Codex CLI schema."""
        record = dict(name="agents", pluginId=f"agents@{market}", marketplaceName=market,
                      version=version, installed=True, enabled=enabled,
                      source={"source": "git", "url": "https://example.invalid/agents"})
        if path is not None:
            record["source"] = dict(source="local", path=str(path))
        self.registry.write_text(json.dumps({"installed": [record]}))

    def run_resolver(self, expected=0):
        """Assert diagnostic exits as well as the resolved absolute path."""
        result = subprocess.run(["bash", str(self.plugin / "bin/resolve-agents-root.sh")],
                                env=self.env, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        if expected:
            self.assertEqual(result.stdout, "")
            self.assertIn("rca:", result.stderr)
        return result.stdout.strip()

    def test_explicit_override_and_bad_override(self):
        """An explicit override is authoritative and cannot silently fall through."""
        role_root = self.agents(self.root / "explicit agents")
        self.env["AGENTS_PLUGIN_ROOT"] = str(role_root)
        self.assertEqual(self.run_resolver(), str(role_root))
        self.env["AGENTS_PLUGIN_ROOT"] += "/missing"
        self.run_resolver(2)

    def test_checkout_sibling(self):
        """Source checkouts resolve without a registry installation."""
        role_root = self.agents(self.plugin.parent / "agents")
        self.assertEqual(self.run_resolver(), str(role_root))

    def test_enabled_local_install(self):
        """Local registry paths work outside the target project's cwd."""
        role_root = self.agents(self.root / "local agents")
        self.registered(role_root)
        self.assertEqual(self.run_resolver(), str(role_root))

    def test_exact_cache_version_and_market(self):
        """Higher stale versions and foreign marketplaces are never selected."""
        cache = Path(self.env["CODEX_HOME"]) / "plugins/cache"
        self.agents(cache / "team/agents/9.9.9", "9.9.9")
        self.agents(cache / "other/agents/3.9.1")
        expected = self.agents(cache / "team/agents/3.9.1")
        self.registered()
        self.assertEqual(self.run_resolver(), str(expected))

    def test_disabled_or_missing_dependency(self):
        """Only genuinely unavailable dependencies permit override-only fallback."""
        self.run_resolver(1)
        role_root = self.agents(self.root / "disabled")
        self.registered(role_root, enabled=False)
        self.run_resolver(1)

    def test_invalid_registry_and_unreachable_install(self):
        """Parsing and installation damage cannot masquerade as missing Agents."""
        for value in ("not json", "{}", '{"installed":null}', '{"installed":[{}]}'):
            with self.subTest(value=value):
                self.registry.write_text(value)
                self.run_resolver(2)
        self.registered(self.root / "absent")
        self.run_resolver(2)
        self.env["REGISTRY_EXIT"] = "7"
        self.run_resolver(2)

    def test_ambiguous_installations_and_version_mismatch(self):
        """Ambiguity and identity mismatches require an explicit valid override."""
        role_root = self.agents(self.root / "wrong version", "9.9.9")
        self.registered(role_root)
        self.run_resolver(2)
        record = json.loads(self.registry.read_text())["installed"][0]
        self.registry.write_text(json.dumps({"installed": [record, record]}))
        self.run_resolver(2)

    def test_role_resolution_and_missing_role(self):
        """The shared resolver, not RCA's guesses, chooses canonical role files."""
        role_root = self.agents(self.root / "roles")
        self.env["AGENTS_PLUGIN_ROOT"] = str(role_root)
        resolved = Path(self.run_resolver())
        for role in ("qa-engineer", "investigator", "evidence-collector", "experimenter",
                     "hypothesis-challenger", "software-architect", "software-engineer", "technical-writer"):
            result = subprocess.run(["bash", str(resolved / "bin/resolve-agent.sh"), role],
                                    text=True, capture_output=True, check=True)
            self.assertTrue(Path(result.stdout.strip()).is_file())
        result = subprocess.run(["bash", str(resolved / "bin/resolve-agent.sh"), "missing-role"],
                                text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("unknown agent", result.stderr)
