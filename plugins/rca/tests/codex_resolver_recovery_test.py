"""Test resolver ownership using an installed layout and external CLI fixtures."""

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
FIXTURE = '''#!{python}
import json, os, signal, sys, time
from pathlib import Path
root = Path(os.environ['FIXTURE_ROOT'])
with (root / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
(root / 'parent.json').write_text(json.dumps(dict(pid=os.getpid(), pgid=os.getpgrp())))
mode = os.environ.get('FIXTURE_MODE', 'exit')
if mode in ('writer', 'detached'):
    child = os.fork()
    if child == 0:
        if mode == 'detached':
            os.setsid()
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        (root / 'child.json').write_text(json.dumps(dict(pid=os.getpid(), pgid=os.getpgrp())))
        while True:
            signal.pause()
    while not (root / 'child.json').exists():
        time.sleep(0.005)
if mode in ('hang', 'resistant'):
    if mode == 'resistant':
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    while True:
        signal.pause()
sys.stderr.write(os.environ.get('FIXTURE_DIAGNOSTIC', ''))
sys.stdout.write(os.environ.get('FIXTURE_REGISTRY', '{"installed":[]}'))
sys.stdout.flush()
sys.stderr.flush()
os._exit(int(os.environ.get('FIXTURE_EXIT', '0')))
'''


BOUNDARY_DRIVER = r"""import importlib.util, json, os, signal, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("resolver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
mode, signum = sys.argv[2], int(sys.argv[3])
events = dict(signals=0, result_writes=0, diagnostic_failures=0, unmasked_io_checks=0)
original_write = Path.write_text
original_stderr, original_stdout = sys.stderr, sys.stdout

def fire():
    if events['signals'] == 0:
        events['signals'] += 1
        os.kill(os.getpid(), signum)

def check_unmasked_io():
    blocked = signal.pthread_sigmask(signal.SIG_BLOCK, set())
    assert not blocked & {signal.SIGINT, signal.SIGTERM}, 'finalization I/O ran with cancellation masked'
    events['unmasked_io_checks'] += 1

def write_result(path, data, *args, **kwargs):
    if path.name == 'result.json':
        check_unmasked_io()
        events['result_writes'] += 1
        count = events['result_writes']
        if mode == 'persist' and count == 1:
            fire()
        if mode == 'failure_then_cancel' and count == 2:
            fire()
        if mode == 'uncorrectable' and count >= 2:
            raise PermissionError('injected corrective metadata failure')
        result = original_write(path, data, *args, **kwargs)
        if mode == 'uncorrectable' and count == 1:
            fire()
        return result
    return original_write(path, data, *args, **kwargs)
Path.write_text = write_result

class Diagnostics:
    def write(self, data):
        check_unmasked_io()
        if data.startswith('rca: Agents resolution '):
            if mode in ('diagnostic_failure', 'failure_then_cancel') and not events['diagnostic_failures']:
                events['diagnostic_failures'] += 1
                raise OSError('injected diagnostic write failure')
            result = original_stderr.write(data)
            if mode == 'diagnostic':
                fire()
            return result
        return original_stderr.write(data)
    def flush(self):
        check_unmasked_io()
        result = original_stderr.flush()
        if mode == 'diagnostic_flush':
            fire()
        return result
    def __getattr__(self, name):
        return getattr(original_stderr, name)

class OutputBuffer:
    def write(self, data):
        check_unmasked_io()
        result = original_stdout.buffer.write(data)
        if mode == 'output_write':
            original_stdout.buffer.flush()
            fire()
        return result
    def flush(self):
        check_unmasked_io()
        result = original_stdout.buffer.flush()
        if mode == 'output_flush':
            fire()
        return result
    def __getattr__(self, name):
        return getattr(original_stdout.buffer, name)

class Output:
    buffer = OutputBuffer()
    def __getattr__(self, name):
        return getattr(original_stdout, name)
sys.stderr, sys.stdout = Diagnostics(), Output()
if mode in ('pending_commit', 'post_commit'):
    original_commit = module._commit_outcome
    def instrument_commit(*args, **kwargs):
        if mode == 'pending_commit' and not events['signals']:
            previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
            try:
                fire()
                return original_commit(*args, **kwargs)
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, previous)
        result = original_commit(*args, **kwargs)
        if mode == 'post_commit' and result:
            fire()
            events['signal_after_commit'] = True
        return result
    module._commit_outcome = instrument_commit
code = module.main([])
events['returned_code'] = code
with open(os.environ['BOUNDARY_EVENTS'], 'w') as stream:
    json.dump(events, stream)
raise SystemExit(code)
"""


def alive(pid):
    """Observe a recorded fixture PID without searching or signaling by name."""
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


class ResolverRecovery(unittest.TestCase):
    """Exercise actual registry execution, diagnostics, and cancellation ownership."""

    def setUp(self):
        """Create the complete installed entry and an isolated fake CLI."""
        self.temp = tempfile.TemporaryDirectory(prefix="rca recovery ", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plugin = self.root / "market/rca/3.9.5"
        shutil.copytree(ROOT / "bin", self.plugin / "bin")
        self.fakebin = self.root / "fake-bin"
        self.fakebin.mkdir()
        # Use the resolved interpreter, avoiding platform launcher setup work.
        (self.fakebin / "python3").symlink_to(sys.executable)
        codex = self.fakebin / "codex"
        codex.write_text(FIXTURE.replace('{python}', sys.executable))
        codex.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.fakebin}:{os.environ['PATH']}",
                        TMPDIR=str(self.root), FIXTURE_ROOT=str(self.root),
                        RCA_RESOLVER_TIMEOUT_SECONDS="0.25")
        self.env.pop("AGENTS_PLUGIN_ROOT", None)
        self.processes = []
        self.addCleanup(self.emergency_cleanup)

    def emergency_cleanup(self):
        """Clean only recorded fixture processes, after all custody assertions."""
        for name in ("child.json", "parent.json"):
            path = self.root / name
            if path.exists():
                record = json.loads(path.read_text())
                try:
                    os.kill(record["pid"], signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for process in self.processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=1)
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()

    def start(self, command=None):
        """Launch the public entry with caller pipes to expose inherited writers."""
        process = subprocess.Popen(command or ["/bin/bash", str(self.plugin / "bin/resolve-agents-root.sh")],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True, text=True)
        self.processes.append(process)
        return process

    def finish(self, process, expected, published_stdout=None):
        """Require bounded return before test cleanup and inspect retained evidence."""
        started = time.monotonic()
        try:
            stdout, stderr = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            self.emergency_cleanup()
            self.fail("Resolver exceeded independent 3-second caller-pipe watchdog")
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(process.returncode, expected, stderr)
        if expected != 0:
            self.assertEqual(stdout, published_stdout or "")
        if expected:
            lines = [line for line in stderr.splitlines() if line.startswith("rca: Agents resolution ")]
            self.assertTrue(lines, stderr)
            directory = Path(lines[-1].split("; evidence: ", 1)[1])
            self.assertEqual(directory.parent.resolve(), self.root.resolve())
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            data = json.loads((directory / "result.json").read_text())
            self.assertIn(str(directory), stderr)
            self.assertFalse(data["detached_descendant_absence_attested"])
            self.assertEqual(data["exit_code"], expected)
            return stdout, stderr, data, directory
        return stdout, stderr, None, None

    def wait_for_marker(self, name="parent.json"):
        """Wait finitely for fixture entry before delivering a real signal."""
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            path = self.root / name
            if path.exists():
                try:
                    return json.loads(path.read_text())
                except json.JSONDecodeError:
                    pass
            time.sleep(0.005)
        self.fail(f"Fixture never recorded {name}")

    def assert_owned_cleanup(self, data):
        """Assert resolver-owned cleanup before the test's emergency cleanup runs."""
        self.assertTrue(data["reaped"])
        self.assertEqual(data["group_after_cleanup"], "absent")
        self.assertFalse(alive(data["validator_pid"]))
        for name in ("parent.json", "child.json"):
            path = self.root / name
            if path.exists():
                record = json.loads(path.read_text())
                if record["pgid"] == data["validator_pgid"]:
                    self.assertFalse(alive(record["pid"]), record)

    def test_silent_hang_is_bounded_and_not_retried(self):
        """A real silent CLI is terminated once and leaves a private failure record."""
        self.env["FIXTURE_MODE"] = "hang"
        _, stderr, data, _ = self.finish(self.start(), 124)
        self.assertEqual(data["reason"], "deadline")
        self.assertIn("deadline", stderr)
        self.assertTrue(data["term_attempted"])
        self.assert_owned_cleanup(data)
        self.assertEqual(self.root.joinpath("calls.jsonl").read_text().splitlines(),
                         ['["plugin", "list", "--json"]'])

    def test_term_resistant_child_requires_kill(self):
        """TERM resistance cannot turn the grace period into an unbounded wait."""
        self.env["FIXTURE_MODE"] = "resistant"
        _, _, data, _ = self.finish(self.start(), 124)
        self.assertTrue(data["kill_attempted"])
        self.assert_owned_cleanup(data)

    def test_direct_pid_and_group_cancellation(self):
        """Both supported signals reach the supervisor through either address."""
        self.env.update(FIXTURE_MODE="resistant", RCA_RESOLVER_TIMEOUT_SECONDS="2")
        for signum in (signal.SIGINT, signal.SIGTERM):
            for group in (False, True):
                with self.subTest(signum=signum, group=group):
                    self.root.joinpath("parent.json").unlink(missing_ok=True)
                    process = self.start()
                    self.wait_for_marker()
                    (os.killpg if group else os.kill)(process.pid, signum)
                    time.sleep(0.03)
                    os.kill(process.pid, signal.SIGTERM if signum == signal.SIGINT else signal.SIGINT)
                    _, _, data, _ = self.finish(process, 128 + signum)
                    self.assertEqual(data["reason"], "cancelled")
                    self.assertEqual(data["signal"], signum)
                    self.assert_owned_cleanup(data)

    def test_signal_during_spawn_registration(self):
        """Deliver real signals around real Popen, without substituting cleanup."""
        self.env.update(FIXTURE_MODE="resistant", RCA_RESOLVER_TIMEOUT_SECONDS="2")
        driver = self.root / "race-driver.py"
        driver.write_text('''import importlib.util, os, signal, subprocess, sys, time
spec = importlib.util.spec_from_file_location("resolver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = subprocess.Popen
def instrumented(*args, **kwargs):
    if sys.argv[2] == 'before':
        os.kill(os.getpid(), signal.SIGINT)
    child = original(*args, **kwargs)
    if sys.argv[2] == 'after':
        os.kill(os.getpid(), signal.SIGTERM)
    return child
module.subprocess.Popen = instrumented
raise SystemExit(module.main([]))
''')
        for when, expected in (("before", 130), ("after", 143)):
            with self.subTest(when=when):
                self.root.joinpath("parent.json").unlink(missing_ok=True)
                command = [sys.executable, "-B", "-S", str(driver),
                           str(self.plugin / "bin/resolve-agents-root.py"), when]
                _, _, data, _ = self.finish(self.start(command), expected)
                self.assert_owned_cleanup(data)

    def test_completed_parent_with_inherited_writer_fails_closed(self):
        """A remaining owned writer is cleaned and cannot yield ordinary absence."""
        self.env["FIXTURE_MODE"] = "writer"
        _, _, data, _ = self.finish(self.start(), 2)
        self.assertEqual(data["reason"], "remaining-group")
        self.assert_owned_cleanup(data)
        self.assertFalse(alive(json.loads(self.root.joinpath("parent.json").read_text())["pid"]))

    def test_detached_writer_cannot_hold_caller_pipes(self):
        """Bounded return does not pretend to attest detached-descendant absence."""
        self.env["FIXTURE_MODE"] = "detached"
        _, _, data, _ = self.finish(self.start(), 1)
        child = self.wait_for_marker("child.json")
        self.assertNotEqual(child["pgid"], data["validator_pgid"])
        self.assertTrue(alive(child["pid"]))
        self.assert_owned_cleanup(data)
        self.assertFalse(alive(json.loads(self.root.joinpath("parent.json").read_text())["pid"]))
        # addCleanup owns this explicitly recorded escaped child, not the resolver.

    def test_external_failure_codes_are_not_local_timeout_or_cancel(self):
        """A CLI exit cannot impersonate supervisor-observed cancellation/deadline."""
        self.env["FIXTURE_DIAGNOSTIC"] = "permission denied; approval required\n"
        for code in (7, 124, 130, 143):
            with self.subTest(code=code):
                self.env["FIXTURE_EXIT"] = str(code)
                _, stderr, data, evidence = self.finish(self.start(), 2)
                self.assertEqual(data["reason"], "validator-failure")
                self.assertEqual(data["child_status"], 2)
                self.assertIn("permission denied; approval required", stderr)
                self.assertIn("permission denied; approval required", (evidence / "stderr").read_text())
                self.assert_owned_cleanup(data)

    def test_invalid_deadlines_never_launch_a_child(self):
        """The configurable mandatory bound cannot be disabled or made unbounded."""
        for value in ("0", "-1", "nan", "inf", "-inf", "61", "", "abc"):
            with self.subTest(value=value):
                self.env["RCA_RESOLVER_TIMEOUT_SECONDS"] = value
                _, _, data, _ = self.finish(self.start(), 2)
                self.assertIsNone(data["validator_pid"])
                self.assertEqual(data["reason"], "invalid-deadline")
                self.assertFalse(self.root.joinpath("calls.jsonl").exists())

    def test_explicit_new_invocation_preserves_previous_failure(self):
        """A separately initiated attempt may succeed without erasing prior evidence."""
        self.env["FIXTURE_MODE"] = "hang"
        _, _, _, first = self.finish(self.start(), 124)
        original = {path.name: path.read_bytes() for path in first.iterdir()}
        role_root = self.root / "selected agents"
        shutil.copytree(ROOT.parent / "agents", role_root)
        version = json.loads((role_root / ".codex-plugin/plugin.json").read_text())["version"]
        self.env.update(FIXTURE_MODE="exit", FIXTURE_REGISTRY=json.dumps({"installed": [dict(
            name="agents", installed=True, enabled=True, version=version,
            marketplaceName="fixture", pluginId="agents@fixture",
            source=dict(source="local", path=str(role_root)))]}), RCA_RESOLVER_TIMEOUT_SECONDS="2")
        stdout, _, _, _ = self.finish(self.start(), 0)
        self.assertEqual(stdout.strip(), str(role_root.resolve()))
        self.assertEqual({path.name: path.read_bytes() for path in first.iterdir()}, original)
        self.assertEqual(len(self.root.joinpath("calls.jsonl").read_text().splitlines()), 2)

    def boundary_process(self, mode, signum=signal.SIGTERM):
        """Instrument real finalization I/O without replacing child execution."""
        driver = self.root / "boundary-driver.py"
        driver.write_text(BOUNDARY_DRIVER)
        self.env["BOUNDARY_EVENTS"] = str(self.root / "boundary-events.json")
        return self.start([sys.executable, "-B", "-S", str(driver),
                           str(self.plugin / "bin/resolve-agents-root.py"), mode, str(int(signum))])

    def test_cancellation_during_failure_finalization_is_not_absence(self):
        """Metadata writes and diagnostic writes/flushes remain cancellable."""
        for mode in ("persist", "diagnostic", "diagnostic_flush"):
            for signum in (signal.SIGINT, signal.SIGTERM):
                with self.subTest(mode=mode, signum=signum):
                    _, stderr, data, _ = self.finish(self.boundary_process(mode, signum), 128 + signum)
                    self.assertEqual(data["reason"], "cancelled")
                    self.assertEqual(data["signal"], signum)
                    self.assertIn(f"cancelled (exit {128 + signum})", stderr)
                    self.assert_owned_cleanup(data)
                    events = json.loads(self.root.joinpath("boundary-events.json").read_text())
                    self.assertEqual(events["signals"], 1)
                    self.assertEqual(events["result_writes"], 2)
                    self.assertGreater(events["unmasked_io_checks"], 0)

    def test_cancellation_during_success_publication_discards_path(self):
        """Already-emitted success bytes never authorize dispatch after cancellation."""
        self.env["AGENTS_PLUGIN_ROOT"] = str(ROOT.parent / "agents")
        expected_path = str((ROOT.parent / "agents").resolve()) + "\n"
        for mode in ("output_write", "output_flush"):
            for signum in (signal.SIGINT, signal.SIGTERM):
                with self.subTest(mode=mode, signum=signum):
                    _, stderr, data, _ = self.finish(self.boundary_process(mode, signum),
                                                   128 + signum, published_stdout=expected_path)
                    self.assertEqual(data["reason"], "cancelled")
                    self.assertEqual(data["signal"], signum)
                    self.assertTrue(data["stdout_publication_started"])
                    self.assertIn("discard stdout unless exit 0", stderr)
                    self.assert_owned_cleanup(data)

    def test_pending_signal_prevents_outcome_commit(self):
        """A signal already pending at the cutoff cannot become fallback authority."""
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum):
                _, _, data, _ = self.finish(self.boundary_process("pending_commit", signum), 128 + signum)
                self.assertEqual(data["signal"], signum)
                self.assertEqual(data["reason"], "cancelled")
                self.assert_owned_cleanup(data)

    def test_signal_after_commit_preserves_completed_outcome(self):
        """Post-completion signals are deliberately outside the cancellation window."""
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum):
                _, _, data, _ = self.finish(self.boundary_process("post_commit", signum), 1)
                self.assertIsNone(data["signal"])
                self.assertEqual(data["reason"], "unavailable")
                events = json.loads(self.root.joinpath("boundary-events.json").read_text())
                self.assertTrue(events["signal_after_commit"])
                self.assertEqual(events["signals"], 1)
                self.assert_owned_cleanup(data)

    def test_diagnostic_failure_corrects_durable_outcome(self):
        """A diagnostic I/O failure cannot leave durable absence with public exit 2."""
        _, stderr, data, _ = self.finish(self.boundary_process("diagnostic_failure"), 2)
        self.assertEqual(data["reason"], "supervisor-failure")
        self.assertIn("injected diagnostic write failure", stderr)
        self.assert_owned_cleanup(data)
        events = json.loads(self.root.joinpath("boundary-events.json").read_text())
        self.assertEqual(events["result_writes"], 2)
        self.assertEqual(events["diagnostic_failures"], 1)

    def test_io_failure_then_cancellation_is_bounded_and_consistent(self):
        """Two distinct outcome transitions need at most three persistence passes."""
        _, _, data, _ = self.finish(self.boundary_process("failure_then_cancel"), 143)
        self.assertEqual(data["signal"], signal.SIGTERM)
        self.assertEqual(data["reason"], "cancelled")
        self.assert_owned_cleanup(data)
        events = json.loads(self.root.joinpath("boundary-events.json").read_text())
        self.assertEqual(len(self.root.joinpath("calls.jsonl").read_text().splitlines()), 1)
        self.assertEqual(events["result_writes"], 3)
        self.assertEqual(events["diagnostic_failures"], 1)
        self.assertEqual(events["signals"], 1)

    def test_failed_metadata_correction_is_explicit(self):
        """An uncorrectable record is disclosed instead of advertised as current."""
        process = self.boundary_process("uncorrectable")
        stdout, stderr = process.communicate(timeout=3)
        self.assertEqual(process.returncode, 143, stderr)
        self.assertEqual(stdout, "")
        self.assertIn("could not persist current outcome", stderr)
        self.assertIn("result.json may describe an earlier outcome", stderr)
        self.assertIn("exit 143 is authoritative", stderr)
        directory = next(self.root.glob("rca-resolver-*"))
        self.assertEqual(json.loads((directory / "result.json").read_text())["exit_code"], 1)
        events = json.loads(self.root.joinpath("boundary-events.json").read_text())
        self.assertEqual(events["result_writes"], 2)

    def test_finalization_io_error_cannot_become_absence(self):
        """A real exit-1 validator followed by failed evidence I/O is exit 2."""
        driver = self.root / "io-failure-driver.py"
        driver.write_text('''import importlib.util, sys
spec = importlib.util.spec_from_file_location("resolver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = module._snapshot
def fail_phase(path, limit):
    if path.name == "phase":
        raise PermissionError("injected finalization read failure")
    return original(path, limit)
module._snapshot = fail_phase
raise SystemExit(module.main([]))
''')
        _, stderr, data, _ = self.finish(self.start([
            sys.executable, "-B", "-S", str(driver),
            str(self.plugin / "bin/resolve-agents-root.py")]), 2)
        self.assertEqual(data["child_status"], 1)
        self.assertEqual(data["reason"], "supervisor-failure")
        self.assertIn("injected finalization read failure", stderr)
        self.assert_owned_cleanup(data)
        self.assertEqual(len(self.root.joinpath("calls.jsonl").read_text().splitlines()), 1)

    def test_signal_during_success_cleanup_retains_truthful_failure(self):
        """Cancellation after artifact removal still returns an explicit record."""
        self.env["AGENTS_PLUGIN_ROOT"] = str(ROOT.parent / "agents")
        driver = self.root / "cleanup-signal-driver.py"
        driver.write_text('''import importlib.util, os, signal, sys
spec = importlib.util.spec_from_file_location("resolver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = module.shutil.rmtree
def signal_after_cleanup(path):
    original(path)
    os.kill(os.getpid(), signal.SIGTERM)
module.shutil.rmtree = signal_after_cleanup
raise SystemExit(module.main([]))
''')
        _, stderr, data, directory = self.finish(self.start([
            sys.executable, "-B", "-S", str(driver),
            str(self.plugin / "bin/resolve-agents-root.py")]), 143)
        self.assertEqual(data["child_status"], 0)
        self.assertEqual(data["reason"], "cancelled")
        self.assertTrue(data["success_artifact_cleanup_started"])
        self.assertTrue(data["evidence_record_reconstructed"])
        self.assertIn("original raw captures may be missing", stderr)
        self.assertFalse((directory / "stdout").exists())
        self.assertFalse((directory / "stderr").exists())
        self.assert_owned_cleanup(data)

    def test_success_cleanup_io_failure_is_exit_two(self):
        """An artifact cleanup failure cannot emit a root or Python's exit 1."""
        self.env["AGENTS_PLUGIN_ROOT"] = str(ROOT.parent / "agents")
        driver = self.root / "cleanup-failure-driver.py"
        driver.write_text('''import importlib.util, sys
spec = importlib.util.spec_from_file_location("resolver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
def fail_cleanup(path):
    raise PermissionError("injected success cleanup failure")
module.shutil.rmtree = fail_cleanup
raise SystemExit(module.main([]))
''')
        _, stderr, data, directory = self.finish(self.start([
            sys.executable, "-B", "-S", str(driver),
            str(self.plugin / "bin/resolve-agents-root.py")]), 2)
        self.assertEqual(data["child_status"], 0)
        self.assertEqual(data["reason"], "supervisor-failure")
        self.assertIn("injected success cleanup failure", stderr)
        self.assertTrue((directory / "stdout").exists())
        self.assert_owned_cleanup(data)

    def test_unexpected_validator_exit_one_is_not_absence(self):
        """A parser command's unhandled failure cannot grant override-only dispatch."""
        jq = self.fakebin / "jq"
        real_jq = shutil.which("jq")
        self.assertIsNotNone(real_jq)
        jq.write_text(f"#!{sys.executable}\nimport os, sys\n"
                      "if sys.argv[1].startswith('[.installed[]'):\n    sys.exit(1)\n"
                      f"os.execv({real_jq!r}, [{real_jq!r}] + sys.argv[1:])\n")
        jq.chmod(0o755)
        _, _, data, _ = self.finish(self.start(), 2)
        self.assertEqual(data["child_status"], 1)
        self.assertEqual(data["reason"], "unconfirmed-absence")
        self.assert_owned_cleanup(data)

    def test_missing_cli_remains_genuine_absence(self):
        """No CLI still yields exit 1 without a registry invocation."""
        python_only = self.root / "python-only"
        python_only.mkdir()
        (python_only / "python3").symlink_to(sys.executable)
        self.env["PATH"] = f"{python_only}:/usr/bin:/bin:/usr/sbin:/sbin"
        self.finish(self.start(), 1)
        self.assertFalse(self.root.joinpath("calls.jsonl").exists())

    def test_failure_excerpt_is_bounded_and_raw_diagnostics_retained(self):
        """Diagnostic truncation never loses the original evidence file."""
        self.env.update(FIXTURE_EXIT="7", FIXTURE_DIAGNOSTIC="d" * 12000)
        _, stderr, _, directory = self.finish(self.start(), 2)
        self.assertLess(len(stderr), 5000)
        self.assertIn("truncated", stderr)
        self.assertGreater(len((directory / "stderr").read_bytes()), 12000)


if __name__ == "__main__":
    unittest.main()
