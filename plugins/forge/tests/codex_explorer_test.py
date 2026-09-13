"""Exercise the production explorer lifecycle, stubbing only the external model CLI."""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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

    def test_timeout_reaps_descendants(self):
        """The deadline owns ordinary child processes before removing their worktree."""
        (self.repo / "fakebin/codex").write_text(
            '#!/bin/sh\nsleep 60 &\nprintf "%s\\n" "$!" > "$PID_FILE"\nwait\n')
        data = self.run_explorer("--timeout", "0.5")
        self.assertFalse(data["ran"])
        self.assertIn("timeout", data["launcher"]["error"])
        pid = int((self.repo / "child.pid").read_text())
        result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], text=True, capture_output=True)
        self.assertEqual(result.stderr, "", "Process inspection failed: " + result.stderr)
        self.assertTrue(result.returncode != 0 or result.stdout.strip().startswith("Z"), result.stdout)
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
