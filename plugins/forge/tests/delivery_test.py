"""Exercise Forge's production artifact and mutation guards with actual delivery records."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve()
ROOT = Path(os.environ.get("FORGE_DELIVERY_TEST_ROOT", SOURCE.parents[1]))
sys.path.insert(0, str(ROOT / "bin"))
from delivery_store import execute


class ForgeDeliveryTests(unittest.TestCase):
    """Pending work must override even plausible completion artifacts."""

    def setUp(self):
        """Use real Git and production helpers without the user's project store."""
        self.temp = tempfile.TemporaryDirectory(dir="/tmp", prefix="forge-delivery-")
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        self.forge = self.project / ".forge"
        self.forge.mkdir()
        (self.forge / "COMPLETION.md").write_text("# Completion\n\nPlausible partial artifact\n")
        self.git("init", "-q")
        self.git("add", ".forge/COMPLETION.md")
        self.git("commit", "-qm", "fixture")
        self.batch = self.forge / "deliveries" / "one"
        self.now = [time.time(), time.monotonic()]
        self.result = execute(self.batch, "init", dict(owner="forge", host="codex", session="parent",
                              step="review", capacity=1, tasks=[dict(task_id="review", task="Review fixture",
                              role="reviewer", writer=False)]), lambda: tuple(self.now))

    def git(self, *args):
        """Keep fixture Git identity and hooks independent of user configuration."""
        return subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                               "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
                              cwd=self.project, check=True, text=True, capture_output=True, timeout=10).stdout.strip()

    def call(self, command, **fields):
        """Call the real persisted boundary with controlled external time."""
        self.result = execute(self.batch, command, dict(revision=self.result["state"]["revision"], **fields),
                              lambda: tuple(self.now))

    def script(self, name, *args):
        """Run a production script in the disposable project and decode its output."""
        env = dict(os.environ)
        env.pop("TMUX", None)
        env.pop("TMUX_PANE", None)
        result = subprocess.run(["bash", str(ROOT / "bin" / name), *args], cwd=self.project,
                                env=env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def complete(self):
        """A real accepted delivery permits the original artifact ladder."""
        t = self.result["state"]["tasks"][0]
        identity = dict(task_id=t["task_id"], attempt_id=t["attempt_id"])
        self.call("record", **identity, kind="dispatch-attempted")
        self.call("record", **identity, kind="dispatched", agent_id="native-42")
        envelope = dict(identity, batch_id=self.result["state"]["batch_id"],
                        task_digest=t["task_digest"], kind="result", payload={"verdict": "pass"})
        self.call("record", **identity, kind="delivery", sender="native-42", body=json.dumps(envelope))
        self.call("record", **identity, kind="stopped", agent_id="native-42", stopped=True, integrity_ok=True)
        self.call("finish", outcome="succeeded", integrity_ok=True)

    def test_successful_baseline_advances_and_pending_blocks(self):
        """A completion file cannot hide a pending worker, but real completion still works."""
        before = self.script("forge-state.sh")
        self.assertEqual(before["state"], "delivery_recovery")
        self.assertEqual(before["dispatch"], "delivery_recovery")
        self.assertFalse(before["auto_advance"])
        self.complete()
        self.assertEqual(self.script("forge-state.sh")["state"], "complete")

    def test_pending_step_exit_cannot_commit_or_queue(self):
        """The mutation boundary itself must reject incomplete deliveries."""
        head = self.git("rev-parse", "HEAD")
        (self.forge / "COMPLETION.md").write_text("# Changed partial completion\n")
        result = self.script("forge-step-exit.sh", "--step", "review", "--summary", "partial", "--terminal")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "delivery_recovery_required")
        self.assertFalse(result["committed"])
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertFalse((self.project / ".freshen/forge.signal").exists())

    def test_crash_recovery_preserves_writer_changes(self):
        """The guard precedes StoryHook resets and Git cleanup."""
        path = self.forge / "COMPLETION.md"
        path.write_text("# Partial writer evidence\n")
        result = self.script("forge-crash-recover.sh")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "delivery_recovery_required")
        self.assertEqual(result["reset_stories"], [])
        self.assertEqual(path.read_text(), "# Partial writer evidence\n")

    def test_corrupt_or_failed_record_blocks(self):
        """A corrupt or terminal-failed record cannot disappear behind successful files."""
        self.call("finish", outcome="failed", reason="permission denied")
        self.assertEqual(self.script("forge-state.sh")["state"], "delivery_recovery")
        (self.batch / "STATE.json").write_text("broken")
        self.assertEqual(self.script("forge-state.sh")["state"], "delivery_recovery")


    def test_pipeline_guard_negative_controls(self):
        """Removing each real gate must fail its ordinary production-flow oracle."""
        condition = "if ! printf '%s' \"$delivery\" | jq -e '.ok == true and .blocked == false' >/dev/null; then"
        cases = [('forge-state.sh', 'test_successful_baseline_advances_and_pending_blocks'), ('forge-step-exit.sh', 'test_pending_step_exit_cannot_commit_or_queue'), ('forge-crash-recover.sh', 'test_crash_recovery_preserves_writer_changes')]
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="forge-guard-mutations-") as directory:
            target = Path(directory)
            shutil.copytree(ROOT / "bin", target / "bin")
            for filename, case in cases:
                with self.subTest(script=filename):
                    path = target / "bin" / filename
                    source = path.read_text()
                    self.assertEqual(source.count(condition), 1)
                    args = [sys.executable, "-B", "-W", "error", str(SOURCE), "ForgeDeliveryTests." + case]
                    env = dict(os.environ, FORGE_DELIVERY_TEST_ROOT=str(target))
                    baseline = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
                    self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
                    path.write_text(source.replace(condition, "if false; then"))
                    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("FAIL:", result.stderr, result.stdout + result.stderr)
                    path.write_text(source)


if __name__ == "__main__":
    unittest.main()
