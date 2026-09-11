"""SH-681: exercise the installed pre-tool gate and Git's real push boundary."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "hooks/pre-push-tests.sh"


class DelegationTests(unittest.TestCase):
    """Disposable Git repos make duplicate suites and lost enforcement observable."""

    def setUp(self):
        """Keep every repo, configuration, verdict, and process inside this fixture."""
        self.temp = tempfile.TemporaryDirectory(prefix="sh681-delegation-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith("GIT_") and k not in ("MAKEFLAGS", "MFLAGS", "MAKELEVEL")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid",
                        PREPUSH_BOUND_MARGIN="7", PREPUSH_VERDICT_LOG=str(self.base / "verdict"))
        settings = self.base / "settings.json"
        settings.write_text(json.dumps({"hooks": {"PreToolUse": [{"hooks": [
            {"command": "bash pre-push-tests.sh", "timeout": 10}]}]}}))
        self.env["CLAUDE_SETTINGS_OVERRIDE"] = str(settings)
        self.repo = self.make_repo("repo with spaces")

    def run_process(self, args, cwd=None, **kwargs):
        """Bound fixture subprocesses and retain complete failure diagnostics."""
        return subprocess.run(args, cwd=cwd or self.repo, env=self.env, text=True,
                              capture_output=True, timeout=15, **kwargs)

    def git(self, *args, cwd=None):
        """Use production Git with fixture-only configuration."""
        result = self.run_process(["git", *args], cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def make_repo(self, name):
        """A deliberately red tiny recipe proves whether the global suite ran."""
        repo = self.base / name
        repo.mkdir()
        self.run_process(["git", "init", "-q", "-b", "fixture"], cwd=repo, check=True)
        (repo / "Makefile").write_text("$(shell touch discovery-started)\ntest:\n\t@touch suite-started\n\t@false\n")
        return repo

    def install_gate(self, repo=None, tracked=True, executable=True, configured=True):
        """Install a real rejecting push hook, which the global hook must not execute."""
        repo = repo or self.repo
        hook = repo / "owned hooks/pre-push"
        hook.parent.mkdir()
        hook.write_text("#!/bin/sh\nprintf 'repository-gate-ran\\n' >&2\nexit 1\n")
        hook.chmod(0o755 if executable else 0o644)
        if tracked:
            self.git("add", "--", "owned hooks/pre-push", cwd=repo)
        if configured:
            self.git("config", "core.hooksPath", "owned hooks", cwd=repo)
        return hook

    def pretool(self, command, cwd=None, hook=HOOK):
        """Drive the real Bash hook with the host's JSON input envelope."""
        return self.run_process(["bash", str(hook)], cwd=cwd,
                                input=json.dumps({"tool_input": {"command": command}}))

    def assert_delegated(self, command, cwd=None, hook=HOOK):
        """Delegation must return without starting either the suite or Git hook."""
        result = self.pretool(command, cwd=cwd, hook=hook)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("delegating", result.stderr)
        self.assertNotIn("repository-gate-ran", result.stderr)
        self.assertFalse(list(self.base.rglob("suite-started")))
        self.assertFalse(list(self.base.rglob("discovery-started")))
        self.assertIn(" delegated ", (self.base / "verdict").read_text())

    def test_plain_push_delegates_and_git_still_refuses_the_remote_update(self):
        """An actual push after delegation must still obey the rejecting repository gate."""
        self.install_gate()
        self.git("commit", "-qm", "fixture")
        remote = self.base / "remote.git"
        self.git("init", "--bare", "-q", str(remote))
        self.git("remote", "add", "origin", str(remote))
        self.assert_delegated("git push origin fixture")
        pushed = self.run_process(["git", "push", "origin", "fixture"])
        self.assertNotEqual(pushed.returncode, 0)
        self.assertIn("repository-gate-ran", pushed.stderr)
        self.assertEqual(self.git("--git-dir", str(remote), "for-each-ref"), "")

    def test_quoted_story_comment_does_not_start_a_duplicate_suite(self):
        self.install_gate()
        self.assert_delegated("story comment SH-665 'Diagnostic: git push returned no result.'")

    def test_a_successful_repository_gate_allows_the_real_push(self):
        hook = self.install_gate()
        hook.write_text("#!/bin/sh\nprintf 'repository-gate-ran\\n' >&2\nexit 0\n")
        self.git("add", "--", str(hook))
        self.git("commit", "-qm", "fixture")
        remote = self.base / "remote.git"
        self.git("init", "--bare", "-q", str(remote))
        self.git("remote", "add", "origin", str(remote))
        self.assert_delegated("git push origin fixture")
        pushed = self.run_process(["git", "push", "origin", "fixture"])
        self.assertEqual(pushed.returncode, 0, pushed.stderr)
        self.assertIn("repository-gate-ran", pushed.stderr)
        self.assertEqual(self.git("--git-dir", str(remote), "rev-parse", "refs/heads/fixture"),
                         self.git("rev-parse", "HEAD"))

    def test_https_override_is_supported(self):
        self.install_gate()
        self.assert_delegated('git -c url."https://github.com/".insteadOf="git@github.com:" push origin fixture')

    def test_leading_cd_resolves_the_target(self):
        self.install_gate()
        elsewhere = self.make_repo("elsewhere")
        self.assert_delegated(f"cd {shlex.quote(str(self.repo))} && git push origin fixture", cwd=elsewhere)

    def test_dash_c_resolves_the_target_from_a_non_repository(self):
        self.install_gate()
        self.assert_delegated(f"git -C {shlex.quote(str(self.repo))} push origin fixture", cwd=self.base)

    def test_absolute_hooks_path_and_subdirectory(self):
        hook = self.install_gate()
        self.git("config", "core.hooksPath", str(hook.parent))
        subdir = self.repo / "subdir"
        subdir.mkdir()
        self.assert_delegated("git push origin fixture", cwd=subdir)

    def test_linked_worktree_uses_its_own_hook(self):
        self.install_gate()
        self.git("commit", "-qm", "fixture")
        lane = self.base / "linked lane"
        self.git("worktree", "add", "-qb", "lane", str(lane))
        self.assert_delegated("git push origin lane", cwd=lane)

    def test_inactive_or_unowned_hooks_retain_the_global_gate(self):
        for variant in ("untracked", "nonexecutable", "unconfigured", "missing", "external"):
            with self.subTest(variant=variant):
                repo = self.make_repo(variant)
                hook = self.install_gate(repo, tracked=variant != "untracked",
                                         executable=variant != "nonexecutable",
                                         configured=variant != "unconfigured")
                if variant == "missing":
                    hook.unlink()
                if variant == "external":
                    self.git("config", "core.hooksPath", str(self.repo), cwd=repo)
                    (self.repo / "pre-push").write_text("#!/bin/sh\nexit 0\n")
                    (self.repo / "pre-push").chmod(0o755)
                result = self.pretool("git push origin fixture", cwd=repo)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertTrue((repo / "suite-started").exists())
                self.assertNotIn("delegating", result.stderr)

    def test_command_overrides_and_ambiguous_shell_never_borrow_the_cwd_gate(self):
        self.install_gate()
        other = self.make_repo("foreign")
        commands = [
            "git -c core.hooksPath=/dev/null push origin fixture",
            f"git -C {shlex.quote(str(other))} push origin fixture",
            "git -c core.bare=true push origin fixture",
            "echo ok && git push origin fixture",
            "git push origin fixture; git -C elsewhere push origin fixture",
            "GIT_CONFIG_COUNT=1 git push origin fixture",
            "bash -c 'git push origin fixture'",
            "echo $(git push origin fixture)",
        ]
        for command in commands:
            with self.subTest(command=command):
                result = self.pretool(command)
                self.assertNotIn("delegating", result.stderr)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_missing_companion_keeps_the_global_gate(self):
        self.install_gate()
        orphan = self.base / "pre-push-tests.sh"
        orphan.write_bytes(HOOK.read_bytes())
        result = self.pretool("git push origin fixture", hook=orphan)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("delegating", result.stderr)


if __name__ == "__main__":
    unittest.main()
