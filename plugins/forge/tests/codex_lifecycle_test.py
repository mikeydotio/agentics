"""Real Forge/Freshen lifecycle integration with a deterministic external terminal."""
import json
import os
from pathlib import Path
import subprocess
import time
import unittest
import codex_hooks_test as fixtures

ROOT = fixtures.ROOT
FRESHEN = ROOT.parent / "freshen"


class Lifecycle(unittest.TestCase):
    """Accepted input events, not pasted text, drive the production reset handshake."""

    def setUp(self):
        """Share artifact setup while replacing only the external tmux transport."""
        self.fixture = fixtures.Hooks()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.project = self.fixture.project
        self.env = self.fixture.env
        self.env.update(TMUX="/tmp/fixture.sock,111,0", TMUX_PANE="%123",
                        TERMINAL_ROOT=str(self.project), FRESHEN_CODEX_DEFERRED_DELAY="0.01",
                        FRESHEN_CODEX_PASTE_SETTLE="0.01", FRESHEN_CODEX_READY_DELAY="0.01",
                        FRESHEN_CODEX_RESET_SETTLE="0.01", FRESHEN_CODEX_TEST_ALLOW_SHORT_SETTLE="1")
        tmux = self.project / "fakebin/tmux"
        tmux.write_text("""#!/usr/bin/env python3
import os,sys
from pathlib import Path
r=Path(os.environ['TERMINAL_ROOT'])
args=sys.argv[1:]
pending=r/'terminal-input'
if args[0]=='capture-pane':
    print('› '+(pending.read_text() if pending.exists() else '')+'\\n\\ngpt-fixture')
elif args[0]=='send-keys':
    if '-l' in args:
        pending.write_text((pending.read_text() if pending.exists() else '')+args[-1])
    elif args[-1]=='Enter':
        with (r/'accepted-input').open('a') as out: out.write(pending.read_text()+'\\n')
        pending.write_text('')
else:
    sys.exit(2)
""")
        tmux.chmod(0o755)

    def freshen(self, hook, **payload):
        """Execute Freshen's packaged production adapter with its own root binding."""
        env = dict(self.env, PLUGIN_ROOT=str(FRESHEN))
        r = subprocess.run(["bash", str(FRESHEN / "hooks/codex" / hook)], env=env,
                           cwd=self.project, input=json.dumps(dict(cwd=str(self.project), **payload)),
                           text=True, capture_output=True, timeout=10)
        self.assertEqual(r.returncode, 0, r.stderr)

    def drive(self, freshen_first):
        """Provide external accepted-message events while production hooks own state."""
        if freshen_first:
            self.freshen("on-stop.sh")
        self.fixture.hook("Stop")
        self.freshen("on-stop.sh")
        self.fixture.hook("Stop")
        accepted = self.project / "accepted-input"
        seen = []
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            messages = accepted.read_text().splitlines() if accepted.exists() else []
            for message in messages[len(seen):]:
                seen.append(message)
                if message == "/new":
                    continue
                if message.startswith("Sending input only to fire session start hooks.") and "Freshen reset " in message:
                    self.freshen("cleanup-session-start.sh", source="startup")
                    self.fixture.hook("SessionStart")
                    self.freshen("on-stop.sh")
                elif message == "$forge:forge resume":
                    # Acceptance alone is insufficient; production consumption waits for Stop.
                    active = self.project / ".freshen/.codex-reset/active"
                    self.assertTrue((active / "continuation.signal").exists())
                    self.freshen("on-stop.sh")
            journals = list((self.project / ".freshen/.codex-reset").glob("completed-*"))
            if journals:
                self.assertEqual((journals[0] / "phase").read_text().strip(), "continuation-stop")
                self.assertEqual(seen.count("/new"), 1)
                self.assertEqual(seen.count("$forge:forge resume"), 1)
                self.assertEqual(len(seen), 3)
                self.assertFalse((self.project / ".freshen/forge.signal").exists())
                self.assertFalse((self.project / ".freshen/.clear-pending").exists())
                return
            time.sleep(0.02)
        logs = list((self.project / ".freshen").rglob("*.log"))
        self.fail("Lifecycle did not retire: " + repr(seen) + "\n" +
                  "\n".join(p.read_text() for p in logs))

    def test_freshen_hook_first(self):
        """Forge must start delivery after Freshen originally observes no signal."""
        self.drive(True)

    def test_forge_hook_first(self):
        """The later registered Freshen hook must not launch a duplicate worker."""
        self.drive(False)

    def test_disabled_and_conflict_do_not_schedule(self):
        """Queue refusal leaves a checkpoint and the original signal unchanged."""
        freshen = self.project / ".freshen"
        freshen.mkdir()
        (freshen / ".disabled").touch()
        self.fixture.hook("Stop")
        self.assertFalse((freshen / ".codex-reset/active").exists())

        (freshen / ".disabled").unlink()
        self.fixture.state.write_text('{"status":"running","sessions_completed":1}')
        (freshen / "other.signal").write_text("other continuation")
        r = self.fixture.hook("Stop")
        self.assertIn("already pending", r.stderr)
        self.assertEqual((freshen / "other.signal").read_text(), "other continuation")
        self.assertFalse((freshen / ".codex-reset/active").exists())

    def test_existing_signal_still_obeys_disabled_policy(self):
        """An earlier queue must not bypass a later disable operation."""
        freshen = self.project / ".freshen"
        freshen.mkdir()
        signal = freshen / "forge.signal"
        signal.write_text("$forge:forge continue\nExisting summary\n")
        (freshen / ".disabled").touch()
        r = self.fixture.hook("Stop")
        self.assertIn("disabled", r.stderr)
        self.assertEqual(signal.read_text(), "$forge:forge continue\nExisting summary\n")
        self.assertFalse((freshen / ".codex-reset/active").exists())

    def test_existing_signal_still_obeys_conflicting_source(self):
        """A legacy Forge signal cannot override another pending workflow."""
        freshen = self.project / ".freshen"
        freshen.mkdir()
        (freshen / "forge.signal").write_text("/forge continue\nExisting summary\n")
        (freshen / "other.signal").write_text("other continuation\n")
        r = self.fixture.hook("Stop")
        self.assertIn("already pending", r.stderr)
        self.assertEqual((freshen / "forge.signal").read_text(), "/forge continue\nExisting summary\n")
        self.assertFalse((freshen / ".codex-reset/active").exists())
