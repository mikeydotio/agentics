"""SH-681: provider installation, drift, and execution from installed files."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from prepush_delegation import DelegationTests as Fixture


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "hooks/install-pre-push-hook.sh"
FILES = ("pre-push-tests.sh", "pre-push-delegation.py")


class InstallTests(unittest.TestCase):
    """Installation must be explicit, recoverable, and independent of live home state."""

    def setUp(self):
        """Give the child a fixture home, including when testing the old installer."""
        self.temp = tempfile.TemporaryDirectory(prefix="sh681-install-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.env = dict(os.environ, HOME=str(self.home))
        self.env.pop("PREPUSH_HOOK_DEST", None)
        for provider in ("claude", "codex"):
            folder = self.home / f".{provider}"
            folder.mkdir()
            registration = folder / ("settings.json" if provider == "claude" else "hooks.json")
            registration.write_text(json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
                {"type": "command", "command": f"bash '{folder}/hooks/pre-push-tests.sh'", "timeout": 900}]}]}}))

    def invoke(self, *args):
        """Call the production installer with captured diagnostics and a bound."""
        return subprocess.run(["bash", str(INSTALLER), *args], cwd=ROOT, env=self.env,
                              capture_output=True, text=True, timeout=15)

    def assert_ok(self, result):
        """Surface both streams when installation fails."""
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_installs_and_checks_both_complete_bundles(self):
        before = {p: p.read_bytes() for p in self.home.glob(".*/*.json")}
        self.assert_ok(self.invoke("install", "--provider", "all"))
        self.assert_ok(self.invoke("check", "--provider", "all"))
        for provider in ("claude", "codex"):
            for name in FILES:
                installed = self.home / f".{provider}/hooks/{name}"
                self.assertEqual(installed.read_bytes(), (ROOT / "hooks" / name).read_bytes())
            self.assertTrue(os.access(self.home / f".{provider}/hooks/pre-push-tests.sh", os.X_OK))
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_codex_only_does_not_install_claude(self):
        self.assert_ok(self.invoke("install", "--provider", "codex"))
        self.assert_ok(self.invoke("check", "--provider", "codex"))
        self.assertFalse((self.home / ".claude/hooks").exists())

    def test_default_remains_claude_and_override_remains_supported(self):
        self.assert_ok(self.invoke("install"))
        self.assertTrue((self.home / ".claude/hooks/pre-push-tests.sh").exists())
        self.assertFalse((self.home / ".codex/hooks").exists())
        destination = self.home / "custom/gate.sh"
        self.env["PREPUSH_HOOK_DEST"] = str(destination)
        self.assert_ok(self.invoke("install"))
        self.assert_ok(self.invoke("check"))
        self.assertTrue((destination.parent / "pre-push-delegation.py").is_file())
        self.assertNotEqual(self.invoke("install", "--provider", "all").returncode, 0)

    def test_missing_mode_and_companion_drift_are_reported_and_repaired(self):
        self.assert_ok(self.invoke("install", "--provider", "all"))
        folder = self.home / ".codex/hooks"
        gate = folder / FILES[0]
        probe = folder / FILES[1]
        gate.chmod(0o644)
        probe.write_text("# drift\n")
        result = self.invoke("check", "--provider", "all")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("claude", result.stdout + result.stderr)
        self.assertIn("codex", result.stdout + result.stderr)
        self.assertIn("pre-push-delegation.py", result.stdout + result.stderr)
        self.assert_ok(self.invoke("install", "--provider", "all"))
        backups = list(folder.glob("*.bak.*"))
        self.assertTrue(any(p.read_text() == "# drift\n" for p in backups))
        self.assertTrue(any(p.read_bytes() == gate.read_bytes() and p.stat().st_mode & 0o111 == 0
                            for p in backups))
        self.assert_ok(self.invoke("check", "--provider", "all"))
        probe.unlink()
        self.assertNotEqual(self.invoke("check", "--provider", "all").returncode, 0)

    def test_repeated_repairs_preserve_every_backup_and_clean_installs_are_idempotent(self):
        self.assert_ok(self.invoke("install", "--provider", "codex"))
        gate = self.home / ".codex/hooks/pre-push-tests.sh"
        for content in ("# one\n", "# two\n"):
            gate.write_text(content)
            self.assert_ok(self.invoke("install", "--provider", "codex"))
        backups = list(gate.parent.glob("pre-push-tests.sh.bak.*"))
        self.assertEqual({p.read_text() for p in backups}, {"# one\n", "# two\n"})
        previous = gate.stat().st_mtime_ns
        self.assert_ok(self.invoke("install", "--provider", "codex"))
        self.assertEqual(previous, gate.stat().st_mtime_ns)
        self.assertEqual(backups, list(gate.parent.glob("pre-push-tests.sh.bak.*")))

    def test_registration_drift_is_reported_without_rewriting_settings(self):
        self.assert_ok(self.invoke("install", "--provider", "codex"))
        settings = self.home / ".codex/hooks.json"
        for content in ("{}", "{bad", settings.read_text().replace("Bash", "OtherTool")):
            settings.write_text(content)
            result = self.invoke("check", "--provider", "codex")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("registration", result.stdout + result.stderr)
            self.assertEqual(settings.read_text(), content)

    def test_symlink_destinations_are_refused_without_changing_the_target(self):
        target = self.home / "foreign"
        target.write_text("preserve me\n")
        folder = self.home / ".codex/hooks"
        folder.mkdir()
        (folder / FILES[0]).symlink_to(target)
        self.assertNotEqual(self.invoke("install", "--provider", "codex").returncode, 0)
        self.assertEqual(target.read_text(), "preserve me\n")

    def test_unknown_arguments_do_not_write_files(self):
        for args in (("install", "--provider", "unknown"), ("install", "extra"),
                     ("install", "--provider"), ("unknown",)):
            self.assertNotEqual(self.invoke(*args).returncode, 0)
        self.assertFalse((self.home / ".claude/hooks").exists())
        self.assertFalse((self.home / ".codex/hooks").exists())

    def test_installed_bundle_actually_delegates(self):
        self.assert_ok(self.invoke("install", "--provider", "codex"))
        fixture = Fixture()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.install_gate()
        fixture.assert_delegated("git push origin fixture",
                                 hook=self.home / ".codex/hooks/pre-push-tests.sh")

    def test_codex_uses_its_own_timeout_even_when_claude_disagrees_or_is_absent(self):
        self.assert_ok(self.invoke("install", "--provider", "all"))
        codex = self.home / ".codex/hooks.json"
        codex.write_text(codex.read_text().replace('900', '123'))
        gate = self.home / ".codex/hooks/pre-push-tests.sh"
        for remove_claude in (False, True):
            if remove_claude:
                (self.home / ".claude/settings.json").unlink()
            result = subprocess.run(["bash", str(gate), "resolve"], cwd=self.home,
                                    env=self.env, text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), f"123 {codex}")

    def test_make_targets_preserve_custom_destinations_and_explicit_providers(self):
        for arguments in (("HOOK_PROVIDER=all",),
                          (f"PREPUSH_HOOK_DEST={self.home}/custom/make-gate.sh",)):
            for target in ("install-hooks", "check-hooks"):
                result = subprocess.run(["make", target, *arguments], cwd=ROOT, env=self.env,
                                        text=True, capture_output=True, timeout=15)
                self.assert_ok(result)


if __name__ == "__main__":
    unittest.main(defaultTest="InstallTests")
