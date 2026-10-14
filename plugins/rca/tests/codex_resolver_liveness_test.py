"""Reproduce an installed resolver blocked by its external registry command."""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class InstalledResolverLiveness(unittest.TestCase):
    """A silent registry must not keep specialist resolution alive indefinitely."""

    def test_nonterminating_registry_is_bounded_by_resolver(self):
        """Require a resolver-owned deadline, separate from the test watchdog."""
        scratch = Path(tempfile.mkdtemp(prefix="rca resolver liveness ", dir="/tmp"))
        plugin = scratch / "market/rca/3.9.5"
        shutil.copytree(ROOT / "bin", plugin / "bin")
        fakebin = scratch / "fake-bin"
        fakebin.mkdir()
        # Use the resolved interpreter, avoiding platform launcher setup work.
        (fakebin / "python3").symlink_to(sys.executable)
        marker = scratch / "registry-entered.json"
        codex = fakebin / "codex"
        codex.write_text(
            f"#!{sys.executable}\n"
            "import json, os, signal, sys\n"
            "from pathlib import Path\n"
            "Path(os.environ['RCA_TEST_REGISTRY_MARKER']).write_text(json.dumps({\n"
            "    'argv': sys.argv[1:], 'pid': os.getpid(), 'pgid': os.getpgrp()}))\n"
            "while True:\n"
            "    signal.pause()\n"
        )
        codex.chmod(0o755)
        env = dict(os.environ, PATH=f"{fakebin}:{os.environ['PATH']}",
                   RCA_TEST_REGISTRY_MARKER=str(marker), TMPDIR=str(scratch))
        env.pop("AGENTS_PLUGIN_ROOT", None)
        # Keep the resolver deadline independent of the emergency test watchdog.
        env["RCA_RESOLVER_TIMEOUT_SECONDS"] = "0.25"
        command = ["/bin/bash", str(plugin / "bin/resolve-agents-root.sh")]
        expired = False
        interrupted = True
        started = time.monotonic()
        def cancelled(_signum, _frame):
            """Route external cancellation through the owned-child cleanup."""
            raise KeyboardInterrupt

        previous_term = signal.signal(signal.SIGTERM, cancelled)
        try:
            with (scratch / "stdout").open("wb") as stdout, (scratch / "stderr").open("wb") as stderr:
                process = subprocess.Popen(command, env=env, stdout=stdout, stderr=stderr,
                                           start_new_session=True)
                try:
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        expired = True
                    interrupted = False
                finally:
                    # Observe custody BEFORE emergency cleanup can hide a leak.
                    registry_alive = False
                    entry = json.loads(marker.read_text()) if marker.exists() else None
                    if entry:
                        try:
                            os.kill(entry["pid"], 0)
                            registry_alive = True
                        except ProcessLookupError:
                            pass
                        try:
                            os.killpg(entry["pgid"], signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    # This session belongs only to this test; never use name-based kills.
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=0.5)
                    evidence = dict(command=command, resolver_pid=process.pid,
                                    elapsed_seconds=time.monotonic() - started,
                                    outer_watchdog_expired=expired, interrupted=interrupted,
                                    registry_alive_before_emergency_cleanup=registry_alive,
                                    returncode=process.returncode,
                                    requested_resolver_deadline_seconds=0.25)
                    (scratch / "result.json").write_text(json.dumps(evidence, indent=2) + "\n")
                    if interrupted:
                        print(f"Resolver cancellation evidence retained at {scratch}", file=sys.stderr)
        finally:
            signal.signal(signal.SIGTERM, previous_term)
        diagnostic = f"Evidence retained at {scratch}; {json.dumps(evidence)}"
        self.assertTrue(marker.is_file(), "Registry fixture was never entered. " + diagnostic)
        entry = json.loads(marker.read_text())
        self.assertEqual(entry["argv"], ["plugin", "list", "--json"], diagnostic)
        self.assertFalse(expired, "Resolver did not terminate itself before the 3-second "
                         "outer watchdog after entering codex plugin list --json. " + diagnostic)
        self.assertEqual(process.returncode, 124, diagnostic)
        self.assertFalse(registry_alive, "Resolver left its registry process alive. " + diagnostic)
        self.assertEqual((scratch / "stdout").read_text(), "", diagnostic)
        self.assertRegex((scratch / "stderr").read_text().lower(),
                         r"timeout|timed out|deadline", diagnostic)
        shutil.rmtree(scratch)


if __name__ == "__main__":
    unittest.main()
