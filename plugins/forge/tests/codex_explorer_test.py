"""Exercise production explorer behavior with real processes and controlled model startup."""
import importlib.util
import json
import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_launcher():
    """Load a fresh production module so fault injection cannot affect another test."""
    spec = importlib.util.spec_from_file_location("forge_explorer", ROOT / "bin/forge-codex-explore.py")
    launcher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(launcher)
    return launcher


class Explorer(unittest.TestCase):
    """Disposable experiments must not mutate the caller or publish failed findings."""

    def setUp(self):
        """Use a real repository and one controllable model transport."""
        self.tmp = tempfile.TemporaryDirectory(prefix="forge experiment ", dir="/private/tmp")
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        for args in (["init", "-q"], ["config", "user.email", "fixture@example.test"],
                     ["config", "user.name", "Fixture"]):
            subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)
        (self.repo / "source.txt").write_text("committed")
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=self.repo, check=True)
        (self.repo / "source.txt").write_text("user changes")
        (self.repo / ".forge").mkdir()
        (self.repo / ".forge/config.json").write_text('{"governed_explorer":true}')
        fakebin = self.repo / "fakebin"
        fakebin.mkdir()
        cli = fakebin / "codex"
        cli.write_text("""#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
args=sys.argv[1:]
Path(os.environ['ARGS_FILE']).write_text(json.dumps(args))
if os.environ.get('EXPLORER_FAIL'): sys.exit(7)
if os.environ.get('EXPLORER_HANG'):
    child=os.fork()
    if child == 0:
        Path(os.environ['PID_FILE']).write_text(str(os.getpid()))
        time.sleep(60)
    time.sleep(60)
Path('source.txt').write_text('experiment')
Path(args[args.index('--output-last-message')+1]).write_text('Evidence from experiment')
""")
        cli.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{fakebin}:{os.environ['PATH']}",
                        ARGS_FILE=str(self.repo / "args.json"), PID_FILE=str(self.repo / "child.pid"))

    def run_explorer(self, *extra):
        """Invoke the public host-aware seam and retain JSON plus process diagnostics."""
        r = subprocess.run(["bash", str(ROOT / "bin/forge-research-explore.sh"),
                            "--host", "codex", "--topic", "Code Shape", "--task",
                            "Inspect source; literal $(no-execution)", *extra],
                           cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=12)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def assert_caller_preserved(self):
        """Only the original worktree and exact pre-existing dirty content may remain."""
        self.assertEqual((self.repo / "source.txt").read_text(), "user changes")
        worktrees = subprocess.check_output(["git", "worktree", "list", "--porcelain"], cwd=self.repo, text=True)
        self.assertEqual(worktrees.count("worktree "), 1)

    def test_success_and_sandbox_contract(self):
        """Findings come from the CLI last message, with bounded workspace permissions."""
        data = self.run_explorer()
        self.assertTrue(data["ran"], data)
        self.assertIn("Evidence", (self.repo / data["out"]).read_text())
        args = json.loads((self.repo / "args.json").read_text())
        self.assertIn("workspace-write", args)
        self.assertIn('approval_policy="never"', args)
        self.assertIn("sandbox_workspace_write.writable_roots=[]", args)
        self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", args)
        self.assertNotIn("--dangerously-bypass-hook-trust", args)
        self.assert_caller_preserved()

    def test_failure_does_not_publish(self):
        """A failed model process cannot masquerade as successful research."""
        self.env["EXPLORER_FAIL"] = "1"
        data = self.run_explorer()
        self.assertFalse(data["ran"])
        self.assertEqual(data["launcher"]["rc"], 7)
        self.assertFalse((self.repo / ".forge/research/codebase-code-shape.md").exists())
        self.assert_caller_preserved()

    def assert_timeout_reaps_ready_child(self, startup_delay, launcher=None):
        """Control external startup readiness; keep real production wait and cleanup."""
        pid_file = self.repo / f"child-{startup_delay}.pid"
        (self.repo / "fakebin/codex").write_text(
            f'#!/bin/sh\nsleep {startup_delay}\nsleep 60 &\nprintf "%s\\n" "$!" > "$PID_FILE"\nwait\n')
        launcher = launcher or load_launcher()
        real_popen = subprocess.Popen
        owned = []

        def ready_popen(command, *args, **kwargs):
            process = real_popen(command, *args, **kwargs)
            if "codex" not in command:
                return process
            owned.append(process)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if pid_file.exists() and pid_file.read_text().strip():
                    child = int(pid_file.read_text())
                    self.assertEqual(os.getpgid(child), process.pid, "Fixture child is not in the owned group")
                    return process
                self.assertIsNone(process.poll(), "External fixture exited before child readiness")
                time.sleep(0.01)
            self.fail(f"External fixture never became ready: pid={process.pid}, marker={pid_file}")

        original_cwd = Path.cwd()
        try:
            os.chdir(self.repo)
            with patch.dict(os.environ, dict(self.env, PID_FILE=str(pid_file))), \
                    patch.object(subprocess, "Popen", ready_popen):
                data = launcher.explore("Inspect source", self.repo / ".forge/research/timeout.md", 0.5)
            self.assertEqual(len(owned), 1, "Production did not dispatch the real model process")
            self.assertFalse(data["ok"], data)
            self.assertIn("timeout", data["error"])
            pid = int(pid_file.read_text())
            result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], text=True, capture_output=True)
            self.assertEqual(result.stderr, "", "Process inspection failed: " + result.stderr)
            self.assertTrue(result.returncode != 0 or result.stdout.strip().startswith("Z"),
                            f"Descendant survived production cleanup: pid={pid}, status={result.stdout}")
            self.assert_caller_preserved()
        finally:
            os.chdir(original_cwd)
            # A deliberately broken cleanup implementation must not leak fixture processes.
            for process in owned:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    if process.poll() is None:
                        process.kill()
                process.wait(timeout=5)

    def test_timeout_reaps_descendants(self):
        """The unchanged deadline reaps confirmed children despite slow external startup."""
        for delay in (0, 1):
            with self.subTest(startup_delay=delay):
                self.assert_timeout_reaps_ready_child(delay)

    def test_timeout_oracle_rejects_leader_only_cleanup(self):
        """The ready-child oracle fails if cleanup kills the leader but leaves its child."""
        launcher = load_launcher()

        def leader_only(process):
            process.kill()
            process.wait(timeout=5)

        with patch.object(launcher, "stop_group", leader_only):
            with self.assertRaisesRegex(AssertionError, "Descendant survived production cleanup"):
                self.assert_timeout_reaps_ready_child(0, launcher)

    def test_timeout_before_child_readiness(self):
        """The public seam may time out before the external CLI creates any PID marker."""
        (self.repo / "fakebin/codex").write_text(
            '#!/bin/sh\nsleep 60\nprintf "unexpected" > "$PID_FILE"\n')
        data = self.run_explorer("--timeout", "0.5")
        self.assertFalse(data["ran"], data)
        self.assertIn("timeout", data["launcher"]["error"])
        self.assertFalse((self.repo / "child.pid").exists())
        self.assert_caller_preserved()

    def test_disabled_does_not_launch(self):
        """A positive disabled control proves the optional gate remains inert."""
        (self.repo / ".forge/config.json").write_text("{}")
        self.assertEqual(self.run_explorer(), dict(enabled=False, ran=False))
        self.assertFalse((self.repo / "args.json").exists())
        self.assert_caller_preserved()

    def test_native_options_require_values(self):
        """Native flags share the fail-fast argument arity contract."""
        for option in ("--host", "--timeout"):
            with self.subTest(option=option):
                r = subprocess.run(["bash", str(ROOT / "bin/forge-research-explore.sh"), option],
                                   cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=2)
                self.assertEqual(r.returncode, 2, r.stderr)
                self.assertIn(option + " requires a value", r.stderr)

    def test_failure_preserves_but_does_not_certify_previous_findings(self):
        """A failed rerun reports failure while preserving earlier evidence verbatim."""
        data = self.run_explorer()
        out = self.repo / data["out"]
        before = out.read_bytes()
        self.env["EXPLORER_FAIL"] = "1"
        data = self.run_explorer()
        self.assertFalse(data["ran"])
        self.assertEqual(out.read_bytes(), before)
        self.assert_caller_preserved()
