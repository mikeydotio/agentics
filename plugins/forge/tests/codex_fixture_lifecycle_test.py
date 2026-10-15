"""Exercise the actual Bats fixture with an external, real-flock StoryHook stand-in.

These tests prove ownership, isolation and deletion order, not the identity of
any historical release-gate writer. No real tracker is contacted.
"""
import fcntl
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CASE = "verifying and blocked both accept a story move after setup"
REMOVED = (
    "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
    "GH_CONFIG_DIR", "STORYHOOK_ACTIVITY_LOG_DIR", "STORYHOOK_ACTIVITY_CONTEXT",
    "STORYHOOK_PROJECT", "STORYHOOK_ACTOR", "STORYHOOK_FULL_AUTO", "STORYHOOK_AUTO",
    "STORYHOOK_DISPATCH", "STORYHOOK_CODEX_BOOTSTRAP", "STORYHOOK_ALLOW_TEMP_PROJECT",
    "STORYHOOK_ALLOW_PROJECT_BURST", "STORYHOOK_ALLOW_UNINSTALLED_MIGRATION",
    "STORYHOOK_ALLOW_UNINSTALLED_DAEMON", "STORYHOOK_ALLOW_UNINSTALLED_PLUGIN_INSTALL",
    "STORYHOOK_TEST_SUBPROCESS_PATIENCE_MS", "STORYHOOK_DAEMON_NOFILE", "STORYHOOK_INVOKER",
)
IDENTITY = (
    "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME",
    "STORYHOOK_DATA_DIR", "STORYHOOK_STORE_PATH", "STORYHOOK_DAEMON_ADDR",
    "STORYHOOK_PARENT_PID", "STORYHOOK_PARENT_START_TIME", "STORYHOOK_VERIFIER_MIRROR",
    "STORYHOOK_VERIFIER_AGENT", "STORYHOOK_TAILNET",
)


def writer(project, evidence, ready_fd, stop_fd):
    """Hold a real inode until explicitly released, recording its unlink order."""
    lease = Path(project) / ".git/storyhook/workspace-locks/SC-1.lock"
    lease.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lease), os.O_CREAT | os.O_RDWR | os.O_EXCL, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    os.write(fd, b"owned asynchronous fixture writer\n")
    os.write(ready_fd, b"locked\n")
    os.close(ready_fd)
    reason = os.read(stop_fd, 64).decode("ascii")
    os.close(stop_fd)
    before = os.fstat(fd)
    os.close(fd)
    try:
        after = lease.stat()
        still_linked = (after.st_dev, after.st_ino) == (before.st_dev, before.st_ino)
    except FileNotFoundError:
        still_linked = False
    Path(evidence).write_text(json.dumps({
        "reason": reason, "links_before_release": before.st_nlink,
        "same_inode_after_release": still_linked, "project": project, "pid": os.getpid(),
    }, indent=2) + "\n")


def story_client():
    """Record only explicit harmless test fields, replacing the external transport."""
    request = {"argv": sys.argv[2:], "cwd": os.getcwd(),
               "environment": {key: os.environ.get(key) for key in IDENTITY + REMOVED}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(30)
        client.connect(os.environ["FORGE_FIXTURE_SERVICE"])
        client.sendall((json.dumps(request) + "\n").encode())
        with client.makefile("rb") as incoming:
            response = json.loads(incoming.readline())
    if response.get("error"):
        print(response["error"], file=sys.stderr)
    return response["code"]


class FixtureLifecycle(unittest.TestCase):
    """A private fixture must drain its own worker or preserve its entire tree."""

    def test_workspace_owner_is_quiescent_before_fixture_deletion(self):
        """Successful stop releases a linked inode; two fixtures never share identity."""
        first = self._exercise("success")
        second = self._exercise("success")
        self.assertNotEqual(first["STORYHOOK_STORE_PATH"], second["STORYHOOK_STORE_PATH"])
        self.assertNotEqual(first["XDG_STATE_HOME"], second["XDG_STATE_HOME"])

    def test_nonzero_stop_preserves_workspace_and_store(self):
        """A failed public stop cannot authorize deletion of the held lock."""
        self._exercise("stop-error")

    def test_stop_timeout_preserves_workspace_and_store(self):
        """The actual ten-second client deadline leaves the daemon's resources intact."""
        self._exercise("stop-timeout")

    def test_missing_identity_preserves_workspace_without_addressing_a_daemon(self):
        """Loss of the captured identity cannot select an inherited daemon or permit rm."""
        self._exercise("missing-identity")

    def test_partial_setup_drains_admitted_owner(self):
        """Even failed project creation uses the same private shutdown identity."""
        self._exercise("setup-error")

    def test_partial_setup_and_failed_stop_preserve_admitted_owner(self):
        """A failed setup followed by a failed drain keeps its evidence and lock."""
        self._exercise("setup-and-stop-error")

    def _exercise(self, scenario):
        bats, git = shutil.which("bats"), shutil.which("git")
        self.assertIsNotNone(bats, "Bats is required; missing tools are not a reproduction")
        self.assertIsNotNone(git, "Git is required")
        root = Path(tempfile.mkdtemp(prefix="forge-fixture-life-", dir="/private/tmp"))
        fixtures, fakebin, foreign = root / "bats-temp", root / "bin", root / "foreign"
        for directory in (fixtures, fakebin, foreign, root / "caller-home", foreign / "templates"):
            directory.mkdir()
        (foreign / "templates/foreign-template").write_text("must not enter fixture Git\n")
        sentinel = foreign / "store.db"
        sentinel.write_text("independently owned shared store\n")
        foreign_fd = os.open(str(sentinel), os.O_RDWR)
        fcntl.flock(foreign_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        foreign_inode = os.fstat(foreign_fd)
        entry = fakebin / "story"
        entry.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + " -B " +
                         shlex.quote(str(Path(__file__).resolve())) + ' --story "$@"\n')
        entry.chmod(0o755)
        # Preserve the old bare-mktemp reproduction on macOS. Explicit templates
        # still go to real mktemp unchanged; the repaired fixture owns its root.
        allocator = fakebin / "mktemp"
        allocator.write_text(
            '#!/bin/sh\nif [ "$#" -eq 1 ] && [ "$1" = "-d" ]; then\n'
            '  exec /usr/bin/mktemp -d ' + shlex.quote(str(fixtures / "fixture.XXXXXX")) +
            '\nfi\nexec /usr/bin/mktemp "$@"\n')
        allocator.chmod(0o755)
        for name, executable in (("git", git), ("python3", sys.executable)):
            wrapper = fakebin / name
            wrapper.write_text('#!/bin/sh\nprintf \'%s\\n\' "$HOME" >> ' +
                               shlex.quote(str(root / (name + "-home.log"))) +
                               '\nexec ' + shlex.quote(executable) + ' "$@"\n')
            wrapper.chmod(0o755)
        # Never forward actual credentials into the substitute's allowlisted log.
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("STORYHOOK_", "GIT_")) and key not in REMOVED}
        env.update({key: "harmless-inherited-sentinel" for key in REMOVED})
        env.update({key: str(foreign / key.lower()) for key in IDENTITY})
        env.update(PATH=str(fakebin) + os.pathsep + os.environ["PATH"],
                   HOME=str(root / "caller-home"), STORYHOOK_STORE_PATH=str(sentinel),
                   STORYHOOK_PARENT_PID="99999999", STORYHOOK_PARENT_START_TIME="foreign-start",
                   STORYHOOK_DAEMON_ADDR="127.0.0.1:1", TMPDIR=str(fixtures),
                   GIT_DIR=str(foreign / "redirect.git"), GIT_WORK_TREE=str(foreign),
                   GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.bare", GIT_CONFIG_VALUE_0="true",
                   GIT_TEMPLATE_DIR=str(foreign / "templates"),
                   FORGE_FIXTURE_SERVICE=str(root / "service.sock"),
                   FORGE_SETUP_SKILL=str(ROOT / "codex/skills/decompose/SKILL.md"))
        errors, transcript, foreign_requests = [], [], []
        stopping = threading.Event()
        state = {"worker": None, "stop_fd": None, "project": None, "identity": None,
                 "fixture_root": None, "stop_seen": False, "timeout_elapsed": None}
        receipt = root / "writer-release.json"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(env["FORGE_FIXTURE_SERVICE"])
        server.listen(4)
        server.settimeout(0.2)
        worker_log = (root / "writer.log").open("wb")

        def release(reason):
            child = state["worker"]
            if child is None:
                raise AssertionError("No workspace owner was admitted")
            if state["stop_fd"] is not None:
                os.write(state["stop_fd"], reason.encode("ascii"))
                os.close(state["stop_fd"])
                state["stop_fd"] = None
            self.assertEqual(child.wait(timeout=5), 0, "Owned writer failed")

        def admit(project):
            self.assertIsNone(state["worker"], "Unexpected second workspace owner")
            ready_r, ready_w = os.pipe()
            stop_r, stop_w = os.pipe()
            state["stop_fd"] = stop_w
            try:
                try:
                    state["worker"] = subprocess.Popen(
                        [sys.executable, "-B", str(Path(__file__).resolve()), "--writer",
                         str(project), str(receipt), str(ready_w), str(stop_r)],
                        stdin=subprocess.DEVNULL, stdout=worker_log, stderr=worker_log,
                        close_fds=True, pass_fds=(ready_w, stop_r), start_new_session=True)
                finally:
                    os.close(ready_w)
                    os.close(stop_r)
                readable, _, _ = select.select([ready_r], [], [], 5)
                self.assertTrue(readable and os.read(ready_r, 64) == b"locked\n",
                                "Writer did not acquire its real workspace lock")
            finally:
                os.close(ready_r)

        def dispatch(request, client):
            transcript.append(request)
            values, argv = request["environment"], request["argv"]
            if values["STORYHOOK_STORE_PATH"] == str(sentinel):
                foreign_requests.append(argv)
                return {"code": 1, "error": "Attempted to address inherited shared state"}
            self.assertTrue(all(values[key] is None for key in REMOVED), values)
            identity = {key: values[key] for key in IDENTITY}
            if argv == ["project", "new", "--prefix", "SC"]:
                project = Path(request["cwd"]).resolve()
                fixture_root = project.parent
                self.assertEqual(fixture_root.parent, Path("/tmp").resolve())
                self.assertTrue(fixture_root.name.startswith("forge-storyhook-fixture."))
                self.assertEqual(fixture_root.stat().st_mode & 0o777, 0o700)
                self.assertTrue((project / ".git").is_dir())
                self.assertFalse((project / ".git/foreign-template").exists())
                home = fixture_root / "home"
                expected = {
                    "HOME": str(home), "XDG_DATA_HOME": str(home / ".local/share"),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_STATE_HOME": str(home / ".local/state"),
                    "STORYHOOK_DATA_DIR": str(home / ".local/share/storyhook"),
                    "STORYHOOK_STORE_PATH": str(home / ".local/share/storyhook/store.db"),
                    "STORYHOOK_DAEMON_ADDR": "127.0.0.1:0", "STORYHOOK_PARENT_START_TIME": "",
                    "STORYHOOK_VERIFIER_MIRROR": "0", "STORYHOOK_VERIFIER_AGENT": "0",
                    "STORYHOOK_TAILNET": "0",
                }
                for key, value in expected.items():
                    self.assertEqual(values[key], value, key)
                self.assertGreater(int(values["STORYHOOK_PARENT_PID"]), 1)
                self.assertNotEqual(values["STORYHOOK_PARENT_PID"], env["STORYHOOK_PARENT_PID"])
                state.update(project=str(project), fixture_root=fixture_root, identity=identity)
                Path(values["STORYHOOK_STORE_PATH"]).write_text("private fixture store\n")
                if scenario.startswith("setup-"):
                    admit(project)
                    return {"code": 7, "error": "injected project creation failure after admission"}
            else:
                self.assertIsNotNone(state["identity"], "Missing project admission")
                self.assertEqual(identity, state["identity"], "Work and stop must select one identity")
                if argv[:2] in (["state", "add"], ["type", "add"]) or argv == ["new", "Task"]:
                    pass
                elif argv == ["move", "SC-1", "verifying"]:
                    self.assertEqual(str(Path(request["cwd"]).resolve()), state["project"])
                    admit(state["project"])
                elif argv == ["move", "SC-1", "blocked", "exhausted retries"]:
                    self.assertIsNotNone(state["worker"])
                    self.assertIsNone(state["worker"].poll(), "Blocked acknowledgement must precede drain")
                    if scenario == "missing-identity":
                        (state["fixture_root"] / "owner").unlink()
                elif argv == ["daemon", "stop"]:
                    state["stop_seen"] = True
                    if scenario in ("stop-error", "setup-and-stop-error"):
                        return {"code": 9, "error": "injected normal stop failure"}
                    if scenario == "stop-timeout":
                        started = time.monotonic()
                        # The real helper deadline must close its client. No response,
                        # synthetic timeout, sleep or worker release supplies the result.
                        client.settimeout(15)
                        self.assertEqual(client.recv(1), b"", "Stop client did not close on timeout")
                        state["timeout_elapsed"] = time.monotonic() - started
                        return None
                    release("fixture-stop")
                else:
                    raise AssertionError("Unexpected StoryHook invocation: %r" % argv)
            return {"code": 0}

        def serve():
            while not stopping.is_set():
                try:
                    client, _ = server.accept()
                except socket.timeout:
                    continue
                with client:
                    client.settimeout(15)
                    try:
                        with client.makefile("rb") as incoming:
                            request = json.loads(incoming.readline())
                        response = dispatch(request, client)
                    except Exception as error:
                        errors.append(repr(error))
                        response = {"code": 1, "error": repr(error)}
                    if response is not None:
                        try:
                            client.sendall((json.dumps(response) + "\n").encode())
                        except OSError as error:
                            errors.append(repr(error))

        service = threading.Thread(target=serve, name="fixture-story-service")
        service.start()
        run, succeeded = None, False
        try:
            with (root / "bats.log").open("wb") as log:
                run = subprocess.Popen(
                    [bats, "--filter", "^" + CASE + "$", str(ROOT / "bin/forge-storyhook-setup-contract.bats")],
                    cwd=root, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                    close_fds=True, start_new_session=True)
                run.wait(timeout=30)
            stopping.set()
            service.join(timeout=16)
            self.assertFalse(service.is_alive(), "Service custody unresolved: %s" % root)
            self.assertFalse(errors, "Fixture/transport failure: %r; evidence: %s" % (errors, root))
            self.assertFalse(foreign_requests, "Fixture addressed the inherited instance")
            self.assertEqual(sentinel.read_text(), "independently owned shared store\n")
            after = sentinel.stat()
            self.assertEqual((after.st_dev, after.st_ino, after.st_nlink),
                             (foreign_inode.st_dev, foreign_inode.st_ino, 1))
            for name in ("git", "python3"):
                homes = (root / (name + "-home.log")).read_text().splitlines()
                self.assertTrue(homes)
                self.assertEqual(set(homes), {env["HOME"]}, "Tool HOME changed: " + name)
            self.assertIsNotNone(state["worker"], "Selected case admitted no workspace owner")
            self.assertEqual(state["stop_seen"], scenario != "missing-identity",
                             "Missing identity must prevent stop; known identity must request it")
            failed_stop = scenario in ("stop-error", "stop-timeout", "setup-and-stop-error", "missing-identity")
            if failed_stop:
                self.assertNotEqual(run.returncode, 0, "Shutdown failure was hidden")
                self.assertFalse(receipt.exists(), "Fixture must not force-release the owner")
                self.assertIsNone(state["worker"].poll())
                self.assertTrue(Path(state["project"]).is_dir())
                self.assertEqual(Path(state["identity"]["STORYHOOK_STORE_PATH"]).read_text(),
                                 "private fixture store\n")
                self.assertGreater((Path(state["project"]) /
                                    ".git/storyhook/workspace-locks/SC-1.lock").stat().st_nlink, 0)
                stop_log = state["fixture_root"] / "stop.log"
                self.assertIn("retained", (root / "bats.log").read_text())
                if scenario == "missing-identity":
                    self.assertFalse(stop_log.exists(), "Unknown identity must not launch a stop client")
                elif scenario == "stop-timeout":
                    self.assertTrue(stop_log.is_file())
                    self.assertIsNotNone(state["timeout_elapsed"])
                    self.assertGreaterEqual(state["timeout_elapsed"], 9)
                    self.assertLess(state["timeout_elapsed"], 15)
                    self.assertIn("timed out", stop_log.read_text())
                else:
                    self.assertTrue(stop_log.is_file())
                    self.assertIn("injected normal stop failure", stop_log.read_text())
                release("test-cleanup")
            else:
                self.assertTrue(receipt.exists(), "Fixture did not finish draining its owner")
                if scenario == "setup-error":
                    self.assertNotEqual(run.returncode, 0, "Setup error was hidden")
                else:
                    self.assertEqual(run.returncode, 0, (root / "bats.log").read_text())
                self.assertFalse(state["fixture_root"].exists(), "Fixture did not reclaim its own root")
            observation = json.loads(receipt.read_text())
            (root / "observed.json").write_text(json.dumps({
                "scenario": scenario, "fixture_exit": run.returncode,
                "writer_release": observation, "commands": transcript,
            }, indent=2) + "\n")
            self.assertEqual(observation["reason"], "test-cleanup" if failed_stop else "fixture-stop")
            self.assertGreater(observation["links_before_release"], 0,
                               "Actual rm unlinked a live owner's inode; evidence: %s" % root)
            self.assertTrue(observation["same_inode_after_release"], "Lock changed before owner release")
            succeeded = True
            return state["identity"]
        finally:
            # Cancellation is confined to children this regression itself created.
            if run is not None and run.poll() is None:
                os.killpg(run.pid, signal.SIGTERM)
                try:
                    run.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(run.pid, signal.SIGKILL)
                    run.wait(timeout=3)
            stopping.set()
            service.join(timeout=16)
            if service.is_alive():
                raise AssertionError("Service custody unresolved; preserve %s" % root)
            child = state["worker"]
            if child is not None and child.poll() is None:
                release("test-cleanup")
            if state["stop_fd"] is not None:
                os.close(state["stop_fd"])
            server.close()
            worker_log.close()
            os.close(foreign_fd)
            (root / "commands.json").write_text(json.dumps(transcript, indent=2) + "\n")
            if succeeded:
                if state["fixture_root"].exists():
                    shutil.rmtree(state["fixture_root"])
                shutil.rmtree(root)
            else:
                print("Fixture lifecycle evidence retained at %s; fixture: %s" %
                      (root, state["fixture_root"]), file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--writer":
        writer(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
    elif len(sys.argv) > 1 and sys.argv[1] == "--story":
        sys.exit(story_client())
    else:
        unittest.main()
