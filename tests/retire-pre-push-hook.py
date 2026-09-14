#!/usr/bin/env python3
"""Exercise host-hook retirement against private homes, never live settings."""

import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "hooks/retire-pre-push-hook.py"


def run_fixture_git(
    repo, *args, env, check=True, timeout=10, ready_path=None, ready_timeout=10,
):
    """Bound fixture Git's process family and retain phase evidence on timeout."""
    command = ["git", "-C", str(repo), *args]
    with tempfile.NamedTemporaryFile(prefix="git-trace-", dir=repo) as trace:
        traced_env = dict(env, GIT_TRACE2_EVENT=trace.name)
        # A new group owns hook/transport descendants without leaving the
        # verifier's session, which must still be able to cancel this test.
        launcher = [sys.executable, "-c",
                    "import os, sys; os.setpgrp(); os.execvp(sys.argv[1], sys.argv[1:])",
                    *command]
        with subprocess.Popen(launcher, env=traced_env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
            def failure_message(reason, stdout, stderr):
                """Render process and Git phase evidence for one fixture failure."""
                trace.seek(0)
                events = trace.read().decode("utf-8", errors="replace").splitlines()
                return (
                    f"{reason}: {command!r}\n"
                    f"stdout: {stdout}\nstderr: {stderr}\n"
                    "Git Trace2 final events:\n" + "\n".join(events[-20:])
                )

            def terminate(reason, error=None):
                """Kill the fixture process group, collect evidence, and fail."""
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass  # The group exited, or the launcher has not set it yet.
                process.kill()
                stdout, stderr = process.communicate(timeout=2)
                failure = AssertionError(failure_message(reason, stdout, stderr))
                if error is None:
                    raise failure
                raise failure from error

            if ready_path is not None:
                ready_path = Path(ready_path)
                ready_deadline = time.monotonic() + ready_timeout
                while not ready_path.exists():
                    if process.poll() is not None:
                        stdout, stderr = process.communicate(timeout=2)
                        raise AssertionError(failure_message(
                            f"fixture Git exited before readiness marker {ready_path}",
                            stdout, stderr,
                        ))
                    remaining = ready_deadline - time.monotonic()
                    if remaining <= 0:
                        terminate(
                            f"fixture Git did not create readiness marker {ready_path} "
                            f"within {ready_timeout}s"
                        )
                    time.sleep(min(0.01, remaining))

            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                terminate(f"fixture Git timed out after {timeout}s", error)
        result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        if check:
            result.check_returncode()
        return result


class RetirementTests(unittest.TestCase):
    """Preservation, refusal, and repeatability of the real retirement command."""

    def setUp(self):
        """Allocate one isolated home per case."""
        self.temp = tempfile.TemporaryDirectory(prefix="retire-hook-", dir="/private/tmp")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home with spaces"
        self.home.mkdir()

    def seed(self, host="claude", command=None):
        """Install a mixed registration and distinguishable hook in the fixture."""
        folder = self.home / f".{host}"
        hook = folder / "hooks/pre-push-tests.sh"
        hook.parent.mkdir(parents=True, exist_ok=True)
        hook.write_text("#!/bin/sh\nprintf 'fixture hook must never execute'\n")
        hook.chmod(0o751)
        path = folder / ("settings.json" if host == "claude" else "hooks.json")
        if command is None:
            command = f'bash "$HOME/.{host}/hooks/pre-push-tests.sh"'
        keep = {"type": "command", "command": "python3 unrelated.py", "timeout": 5}
        data = {
            "permissions": {"allow": ["custom-value"]},
            "hooks": {
                "PreToolUse": [{"matcher": "Bash", "custom": True, "hooks": [
                    keep, {"type": "command", "command": command, "timeout": 900}]}],
                "Stop": [{"hooks": [{"type": "command", "command": "notify"}]}],
            },
        }
        path.write_text(json.dumps(data, indent=4) + "\n")
        path.chmod(0o600)
        return path, hook, data

    def run_retirement(self, *args):
        """Run the production CLI with an explicit fixture home."""
        return subprocess.run(
            ["python3", str(SCRIPT), "--home", str(self.home), *args],
            text=True, capture_output=True, timeout=10, check=False,
        )

    def test_check_is_read_only_and_reports_pending_retirement(self):
        """Check is read only and reports pending retirement."""
        path, hook, _ = self.seed()
        before = path.read_bytes()
        result = self.run_retirement()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("pending", result.stdout)
        self.assertEqual(path.read_bytes(), before)
        self.assertTrue(hook.exists())
        self.assertFalse((self.home / ".local").exists())

    def test_removes_both_hosts_preserves_settings_modes_and_exact_backups(self):
        """Removes both hosts preserves settings modes and exact backups."""
        fixtures = [self.seed(), self.seed("codex", f"bash '{self.home}/.codex/hooks/pre-push-tests.sh'")]
        originals = {p: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
                     for settings, hook, _ in fixtures for p in (settings, hook)}
        result = self.run_retirement("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        backup = Path(report["backup"])
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o700)
        for path, hook, expected in fixtures:
            expected["hooks"]["PreToolUse"][0]["hooks"].pop()
            self.assertEqual(json.loads(path.read_text()), expected)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertFalse(hook.exists())
            for original in (path, hook):
                saved = backup / original.relative_to(self.home)
                self.assertEqual(saved.read_bytes(), originals[original][0])
                self.assertEqual(stat.S_IMODE(saved.stat().st_mode), originals[original][1])
        self.assertEqual(self.run_retirement().returncode, 0)
        again = self.run_retirement("--apply")
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIsNone(json.loads(again.stdout)["backup"])

    def test_empty_install_is_a_noop(self):
        """Empty install is a noop."""
        result = self.run_retirement("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_unrelated_settings_are_not_reformatted(self):
        """Unrelated settings are not reformatted."""
        path, hook, _ = self.seed(command="bash /some/repo/pre-push-tests.sh")
        before = path.read_bytes()
        result = self.run_retirement("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_bytes(), before)
        self.assertFalse(hook.exists())

    def test_malformed_second_host_prevents_any_first_host_mutation(self):
        """Malformed second host prevents any first host mutation."""
        path, hook, _ = self.seed()
        other, _, _ = self.seed("codex")
        other.write_text("{broken")
        before = path.read_bytes()
        result = self.run_retirement("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(other), result.stderr)
        self.assertEqual(path.read_bytes(), before)
        self.assertTrue(hook.exists())
        self.assertFalse((self.home / ".local").exists())

    def test_unknown_shapes_and_duplicate_keys_are_refused_before_writes(self):
        """Unknown shapes and duplicate keys are refused before writes."""
        for raw in ['[]', '{"hooks": []}', '{"hooks":{"PreToolUse":{}}}',
                    '{"hooks":{"PreToolUse":[{"hooks":"bad"}]}}',
                    '{"hooks":{},"hooks":{}}']:
            with self.subTest(raw=raw):
                path, hook, _ = self.seed()
                path.write_text(raw)
                result = self.run_retirement("--apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(path.read_text(), raw)
                self.assertTrue(hook.exists())

    def test_unknown_invocation_of_managed_hook_is_refused(self):
        """Unknown invocation of managed hook is refused."""
        path, hook, _ = self.seed(command='env X=1 bash "$HOME/.claude/hooks/pre-push-tests.sh"')
        before = path.read_bytes()
        result = self.run_retirement("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unrecognized", result.stderr)
        self.assertEqual(path.read_bytes(), before)
        self.assertTrue(hook.exists())

    def test_symlink_and_fifo_are_refused_without_following_or_blocking(self):
        """Symlink and fifo are refused without following or blocking."""
        path, hook, _ = self.seed()
        original = hook.read_bytes()
        hook.unlink()
        target = self.home / "keep.sh"
        target.write_bytes(original)
        hook.symlink_to(target)
        self.assertNotEqual(self.run_retirement("--apply").returncode, 0)
        self.assertEqual(target.read_bytes(), original)
        hook.unlink()
        os.mkfifo(hook)
        self.assertNotEqual(self.run_retirement("--apply").returncode, 0)
        self.assertTrue(path.exists())

    def test_single_hook_entry_is_removed_without_removing_other_events(self):
        """Single hook entry is removed without removing other events."""
        path, _, data = self.seed()
        data["hooks"]["PreToolUse"][0]["hooks"].pop(0)
        path.write_text(json.dumps(data))
        result = self.run_retirement("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        data["hooks"]["PreToolUse"] = []
        self.assertEqual(json.loads(path.read_text()), data)

    def test_registration_is_removed_when_script_is_already_absent(self):
        """Registration is removed when script is already absent."""
        path, hook, _ = self.seed()
        hook.unlink()
        result = self.run_retirement("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pre-push-tests.sh", path.read_text())

    def test_repository_hook_still_controls_real_publication(self):
        """Repository hook still controls real publication."""
        self.seed()
        repo = self.home / "project"
        remote = self.home / "remote.git"
        repo.mkdir()
        git_env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        git_env.update(GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                       GIT_AUTHOR_EMAIL="fixture@example.test", GIT_COMMITTER_EMAIL="fixture@example.test")

        def git(*args, check=True):
            """Execute real Git only within the fixture repository."""
            return run_fixture_git(repo, *args, env=git_env, check=check)

        git("init", "-q")
        git("init", "-q", "--bare", str(remote))
        git("-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-qm", "fixture")
        hooks = repo / "project-hooks"
        hooks.mkdir()
        hook = hooks / "pre-push"
        hook.write_text("#!/bin/sh\necho repo-owned-refusal >&2\nexit 1\n")
        hook.chmod(0o755)
        git("config", "core.hooksPath", str(hooks))
        original = hook.read_bytes()
        self.assertEqual(self.run_retirement("--apply").returncode, 0)
        self.assertEqual(hook.read_bytes(), original)
        refused = git("push", str(remote), "HEAD:refs/heads/feature", check=False)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("repo-owned-refusal", refused.stderr)
        self.assertEqual(git("ls-remote", str(remote), "refs/heads/feature").stdout, "")
        hook.write_text("#!/bin/sh\nexit 0\n")
        git("push", str(remote), "HEAD:refs/heads/feature")
        self.assertIn("refs/heads/feature", git("ls-remote", str(remote)).stdout)

    def test_git_readiness_timeout_fails_with_phase_evidence(self):
        """A missing readiness marker fails on its own bounded deadline."""
        repo = self.home / "unready-project"
        repo.mkdir()
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        run_fixture_git(repo, "init", "-q", "--template=", env=env)
        hook = repo / ".git/hooks/pre-push"
        hook.parent.mkdir(exist_ok=True)
        hook.write_text("#!/bin/sh\nsleep 60\n")
        hook.chmod(0o755)
        marker = repo / "never-created"

        with self.assertRaises(AssertionError) as failure:
            run_fixture_git(
                repo, "hook", "run", "pre-push", env=env, timeout=10,
                ready_path=marker, ready_timeout=0.1,
            )

        self.assertIn(f"did not create readiness marker {marker}", str(failure.exception))
        self.assertIn("Git Trace2 final events", str(failure.exception))

    def test_git_timeout_reaps_hook_descendants_and_reports_phase(self):
        """A stuck real Git hook fails loudly without leaking its process family."""
        repo = self.home / "stuck-project"
        repo.mkdir()
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        run_fixture_git(repo, "init", "-q", "--template=", env=env)
        hook = repo / ".git/hooks/pre-push"
        hook.parent.mkdir(exist_ok=True)
        child = repo / "hang.py"
        child.write_text(
            "import json, os, subprocess, sys, time\n"
            "from pathlib import Path\n"
            "time.sleep(0.2)\n"
            "p = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
            "Path('pids.json').write_text(json.dumps([os.getpid(), p.pid, os.getsid(0)]))\n"
            "Path('ready').touch()\n"
            "print('fixture-hook-entered', flush=True)\n"
            "p.wait()\n"
        )
        hook.write_text(f'#!/bin/sh\nexec python3 "{child}"\n')
        hook.chmod(0o755)

        def cleanup_children():
            """Reap only this fault fixture's known processes if the regression fails."""
            if (repo / "pids.json").exists():
                for pid in json.loads((repo / "pids.json").read_text())[:2]:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

        self.addCleanup(cleanup_children)
        failure = None
        try:
            run_fixture_git(
                repo, "hook", "run", "pre-push", env=env, timeout=0.1,
                ready_path=repo / "ready", ready_timeout=10,
            )
        except (subprocess.TimeoutExpired, AssertionError) as error:
            failure = error
        self.assertIsNotNone(failure, "the deliberately stuck hook must fail")
        self.assertTrue((repo / "pids.json").exists(), "hook never reached the fault injection")
        parent, descendant, session = json.loads((repo / "pids.json").read_text())
        self.assertEqual(session, os.getsid(0), "fixture escaped verifier session ownership")
        alive = [parent, descendant]
        deadline = time.monotonic() + 2
        while alive and time.monotonic() < deadline:
            for pid in alive[:]:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    alive.remove(pid)
            if alive:
                time.sleep(0.02)
        self.assertEqual(alive, [], "timed-out Git left hook descendants alive")
        self.assertIsInstance(failure, AssertionError)
        self.assertIn("fixture Git timed out", str(failure))
        self.assertIn("fixture-hook-entered", str(failure))
        self.assertIn('"child_start"', str(failure))
        self.assertIn("pre-push", str(failure))

    def test_retired_source_and_install_targets_cannot_reinstall_the_hook(self):
        """Retired source and install targets cannot reinstall the hook."""
        for name in ("hooks/pre-push-tests.sh", "hooks/install-pre-push-hook.sh",
                     "tests/prepush-gate.sh", "tests/gate-deadline.sh", "tests/gate-deadline-guard.sh"):
            self.assertFalse((ROOT / name).exists(), name)
        makefile = (ROOT / "Makefile").read_text()
        self.assertNotIn("install-hooks:", makefile)
        self.assertNotIn("check-hooks:", makefile)
        self.assertNotIn("gate_deadline_check", (ROOT / "tests/with-isolated-store.sh").read_text())


if __name__ == "__main__":
    unittest.main()
