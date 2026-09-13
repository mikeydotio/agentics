"""Drive real Forge manifest commands and shared helpers in isolated projects."""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Hooks(unittest.TestCase):
    """Host adapters preserve durable checkpoints and native continuation semantics."""

    def setUp(self):
        """Create real artifact state; stub only the optional external story narrative."""
        self.tmp = tempfile.TemporaryDirectory(prefix="forge hooks ", dir="/private/tmp")
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        (self.project / ".forge").mkdir()
        self.state = self.project / ".forge/state.json"
        self.state.write_text(json.dumps(dict(status="running", sessions_completed=0,
                                              stories_attempted=2, stories_this_session=1)))
        (self.project / ".forge/lock.json").write_text("{}")
        fakebin = self.project / "fakebin"
        fakebin.mkdir()
        (fakebin / "story").write_text("#!/bin/sh\nprintf 'fixture handoff\\n'\n")
        (fakebin / "story").chmod(0o755)
        self.env = dict(os.environ, PATH=f"{fakebin}:{os.environ['PATH']}")
        for name in ("TMUX", "TMUX_PANE", "PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT",
                     "CLAUDE_PROJECT_DIR", "FRESHEN_PLUGIN_ROOT", "HOOK_GUARD_PLUGIN_ROOT"):
            self.env.pop(name, None)

    def hook(self, event, host="codex", cwd=None):
        """Invoke the exact packaged hook command, with native provider variables."""
        command = json.loads((ROOT / "hooks/hooks.json").read_text())["hooks"][event][0]["hooks"][0]["command"]
        env = dict(self.env)
        env["PLUGIN_ROOT" if host == "codex" else "CLAUDE_PLUGIN_ROOT"] = str(ROOT)
        result = subprocess.run(["bash", "-c", command], cwd=self.project, env=env,
                                input=json.dumps(dict(cwd=str(cwd or self.project),
                                                      hook_event_name=event)),
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_host_envelopes_and_payload_directory(self):
        """A stale Claude alias cannot redirect a native Codex event."""
        self.env["CLAUDE_PROJECT_DIR"] = "/not/the/project"
        r = self.hook("SessionStart")
        data = json.loads(r.stdout)
        self.assertEqual(set(data), {"hookSpecificOutput"})
        self.assertEqual(data["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("Forge running", data["hookSpecificOutput"]["additionalContext"])
        del self.env["CLAUDE_PROJECT_DIR"]
        self.assertIn("additionalContext", json.loads(self.hook("SessionStart", "claude").stdout))

    def test_corrupt_and_inactive_state(self):
        """Corruption produces valid diagnostic context; inactive projects emit nothing."""
        self.state.write_text("{broken")
        r = self.hook("SessionStart")
        self.assertIn("corrupt", json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"])
        self.assertIn("malformed", r.stderr)
        for state in (dict(status="done"), {}):
            self.state.write_text(json.dumps(state))
            self.assertEqual(self.hook("SessionStart").stdout, "")
        self.state.unlink()
        self.assertEqual(self.hook("SessionStart").stdout, "")

    def test_legacy_resume_command(self):
        """Known legacy commands translate; arbitrary command text is preserved."""
        for command, expected in (("/forge resume", "$forge:forge resume"),
                                  ("/forge continue", "$forge:forge continue"),
                                  ("custom /forge resume", "custom /forge resume")):
            self.state.write_text(json.dumps(dict(status="paused", resume=dict(command=command, summary="Saved"))))
            text = json.loads(self.hook("SessionStart").stdout)["hookSpecificOutput"]["additionalContext"]
            self.assertIn("Resume: " + expected, text)

    def test_stop_checkpoint_without_tmux_and_idempotence(self):
        """Emergency checkpoint survives lack of reset delivery; duplicate Stop is inert."""
        r = self.hook("Stop")
        state = json.loads(self.state.read_text())
        self.assertEqual(state["status"], "paused")
        self.assertEqual(state["sessions_completed"], 1)
        self.assertEqual(state["resume"]["command"], "$forge:forge resume")
        self.assertFalse((self.project / ".forge/lock.json").exists())
        self.assertIn("Codex", (self.project / ".forge/handoffs/handoff-execute.md").read_text())
        self.assertFalse((self.project / ".freshen/.clear-pending").exists())
        self.assertIn("manual", r.stderr)
        before = self.state.read_bytes()
        self.hook("Stop")
        self.assertEqual(self.state.read_bytes(), before)

    def step(self, *args):
        """Run the production step exit with real Git commits."""
        return subprocess.run(["bash", str(ROOT / "bin/forge-step-exit.sh"), *args],
                              cwd=self.project, env=self.env, text=True, capture_output=True)

    def test_codex_step_exit_and_terminal_cancellation(self):
        """Queue/cancel uses Freshen's native CLI and preserves JSON and resume state."""
        for args in (["init", "-q"], ["config", "user.email", "fixture@example.test"],
                     ["config", "user.name", "Fixture"]):
            subprocess.run(["git", *args], cwd=self.project, check=True, capture_output=True)
        (self.project / ".gitignore").write_text(".forge/state.json\n.forge/lock.json\n.freshen/\nfakebin/\n")
        (self.project / ".forge/IDEA.md").write_text("fixture")
        subprocess.run(["git", "add", "."], cwd=self.project, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=self.project, check=True)
        args = ("--host", "codex", "--step", "research", "--summary", "checkpoint")
        r = self.step(*args, "--next", "/forge continue")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertFalse(data["freshen_queued"])
        self.assertIn("/new", data["fallback_message"])
        self.assertEqual(json.loads(self.state.read_text())["resume"]["command"], "$forge:forge continue")
        self.env.update(TMUX="fixture", TMUX_PANE="%123")
        r = self.step(*args, "--next", "$forge:forge continue")
        self.assertTrue(json.loads(r.stdout)["freshen_queued"], r.stderr)
        self.assertEqual((self.project / ".freshen/forge.signal").read_text().splitlines()[0], "$forge:forge continue")
        r = self.step(*args, "--terminal")
        self.assertTrue(json.loads(r.stdout)["freshen_cancelled"], r.stderr)
        self.assertFalse((self.project / ".freshen/forge.signal").exists())

    def test_invalid_host_is_rejected_before_mutation(self):
        """Invalid host cannot commit or write pipeline state."""
        before = self.state.read_bytes()
        r = self.step("--host", "unknown", "--step", "research", "--summary", "x", "--next", "x")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.state.read_bytes(), before)

    def test_missing_freshen_keeps_emergency_checkpoint(self):
        """A damaged required dependency must leave an actionable manual resume."""
        self.env.update(TMUX="fixture", TMUX_PANE="%123", FRESHEN_PLUGIN_ROOT="/missing-freshen")
        r = self.hook("Stop")
        self.assertIn("Freshen unavailable", r.stderr)
        self.assertEqual(json.loads(self.state.read_text())["status"], "paused")
        self.assertFalse((self.project / ".forge/lock.json").exists())

    def test_native_active_journal_requeue_and_cancellation(self):
        """The Forge boundary preserves Freshen's in-flight ownership and cancel semantics."""
        self.env.update(TMUX="fixture", TMUX_PANE="%123")
        active = self.project / ".freshen/.codex-reset/active"
        active.mkdir(parents=True)
        (active / "signal_basename").write_text("forge.signal\n")
        (active / "nonce").write_text("fixture\n")
        (active / "continuation.signal").write_text("$forge:forge resume\n")
        def freshen(*args):
            return subprocess.run(["bash", "-c", 'source "$1"; shift; forge_freshen "$@"',
                                   "fixture", str(ROOT / "bin/forge-host.sh"), str(ROOT), "codex", *args],
                                  cwd=self.project, env=self.env, capture_output=True, text=True, timeout=5)
        r = freshen("queue", "$forge:forge continue", "--source", "forge")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((active / "continuation.signal").exists())
        queued = self.project / ".freshen/forge.signal"
        self.assertEqual(queued.read_text(), "$forge:forge continue\n")
        r = freshen("queue", "other", "--source", "other")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("in flight", r.stderr)
        r = freshen("cancel", "--source", "forge")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(queued.exists())
        self.assertFalse(active.exists())
        self.assertEqual((active.parent / "cancelled-fixture/phase").read_text(), "cancelled-user\n")


if __name__ == "__main__":
    unittest.main()
