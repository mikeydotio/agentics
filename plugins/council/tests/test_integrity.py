"""AGE-77: exercise repository integrity through the production command boundary."""
import json
import errno
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

BIN = Path(os.environ.get("COUNCIL_TEST_ROOT", Path(__file__).resolve().parents[1])) / "bin"
sys.path.insert(0, str(BIN))
from council_store import execute


class IntegrityTests(unittest.TestCase):
    """Use real repositories; only delivery and time are synthetic."""

    def setUp(self):
        """Create tracked, dirty, untracked, and ignored evidence."""
        self.temp = tempfile.TemporaryDirectory(prefix="age77-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        for name in ("clean", "dirty", "delete"):
            (self.repo / name).write_text("original\n")
        (self.repo / ".gitignore").write_text("ignored\n.council/\n")
        (self.repo / "link").symlink_to("clean")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        (self.repo / "dirty").write_text("user edit\n")
        (self.repo / "untracked").write_text("user draft\n")
        (self.repo / "ignored").write_text("ignored input\n")
        self.root = self.repo / ".council" / "sitting"
        self.now = [1000000.0, 1000.0]
        self.result = None

    def git(self, *args):
        """Invoke real Git without caller checkout overrides."""
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        return subprocess.run(["git", "-C", str(self.repo), *args], env=env,
                              check=True, capture_output=True).stdout

    def init(self, host="codex", **extra):
        """Create a baseline before dispatch."""
        data = dict(question="Which option?", chair="chair", host=host,
                    archetypes=["architect", "qa", "engineer"], repository_root=str(self.repo))
        data.update(extra)
        self.result = execute(self.root, "init", data, lambda: tuple(self.now))
        return self.result

    def call(self, command, **data):
        """Use revision checks exactly as host adapters do."""
        data.setdefault("revision", self.result["state"]["revision"])
        self.result = execute(self.root, command, data, lambda: tuple(self.now))
        return self.result

    def event(self, n, kind, **data):
        """Record one identified native transport event."""
        seat = self.result["state"]["seats"][str(n)]
        return self.call("record", seat=n, attempt_id=seat["attempt_id"], kind=kind, **data)

    def begin(self, phase="research"):
        """Start the complete panel before accepting output."""
        self.call("begin-phase", phase=phase)
        for n in (1, 2, 3):
            self.event(n, "dispatch-attempted")
            self.event(n, "dispatched", agent_id=f"agent-{n}")

    def deliver(self, n):
        """Deliver a valid result for the current phase."""
        s = self.result["state"]
        payload = (dict(summary=f"Option {n}", rationale="Evidence", risks="Cost", confidence="high")
                   if s["phase"] == "research" else dict(choice="A", reason="Evidence"))
        body = json.dumps(dict(council_id=s["council_id"], question_digest=s["question_digest"],
                               phase=s["phase"], seat=n, attempt_id=s["seats"][str(n)]["attempt_id"],
                               kind="result", payload=payload))
        return self.event(n, "delivery", sender=f"agent-{n}", body=body)

    def assert_rejected(self, status="drift", path=None):
        """A failure preserves evidence and exposes only cleanup actions."""
        self.assertFalse(self.result["ok"])
        s = self.result["state"]
        self.assertEqual(s["status"], "aborted")
        self.assertEqual(self.result["integrity"]["status"], status)
        if path:
            self.assertIn(path, self.result["integrity"]["changed_paths"])
        self.assertEqual(s["proposals"], {})
        self.assertTrue(all(x["kind"] == "cleanup" for x in self.result["actions"]))
        self.assertTrue((self.root / "ABORT.md").exists())
        self.assertFalse((self.root / "DECISION.md").exists())

    def test_success_both_hosts_and_allowed_output(self):
        """Real unchanged inputs survive both supported host flows."""
        for host in ("claude", "codex"):
            with self.subTest(host=host):
                self.root = self.repo / ".council" / host
                self.init(host)
                self.assertEqual(self.result["integrity"]["status"], "clean")
                self.begin()
                (self.root / "QUESTION.md").write_text("chair question")
                for seat in self.result["state"]["seats"].values():
                    (Path(seat["scratch"]) / "measurement").write_text("owned output")
                for n in (1, 2, 3):
                    self.deliver(n)
                self.assertEqual(self.result["state"]["status"], "phase-complete")
                self.begin("vote")
                for n in (1, 2, 3):
                    self.deliver(n)
                self.call("finish", outcome="decision", markdown="Use A")
                self.assertTrue(self.result["ok"], self.result)
                self.assertTrue((self.root / "DECISION.md").exists())

    def test_dirty_edit_preserved_despite_identical_status(self):
        """The filed defect cannot hide behind an existing M status."""
        self.init()
        self.begin()
        self.deliver(1)
        baseline = (self.root / "BASELINE.json").read_bytes()
        before = self.git("status", "--porcelain", "-z")
        stamp = (self.repo / "dirty").stat()
        (self.repo / "dirty").write_text("next edit\n")
        os.utime(self.repo / "dirty", ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.assertEqual(before, self.git("status", "--porcelain", "-z"))
        self.deliver(2)
        self.assert_rejected(path="dirty")
        self.assertEqual((self.repo / "dirty").read_text(), "next edit\n")
        self.assertEqual((self.root / "BASELINE.json").read_bytes(), baseline)
        invalid = self.result["state"]["invalidated_findings"]
        self.assertIn("Option 1", json.dumps(invalid))
        self.assertIn("Option 2", json.dumps(invalid))
        self.assertNotIn("member changed", (self.root / "ABORT.md").read_text())

    def test_clean_untracked_ignored_and_unusual_paths(self):
        """All file classes and names are content-sensitive."""
        for number, name in enumerate(("clean", "untracked", "ignored", "space tab\tline\n雪")):
            with self.subTest(name=name):
                target = self.repo / name
                target.write_bytes(b"before")
                self.root = self.repo / ".council" / f"case{number}"
                self.init()
                target.write_bytes(b"after")
                self.call("advance")
                self.assert_rejected(path=name)
                self.assertEqual(target.read_bytes(), b"after")

    def test_index_only_and_head_changes_preserved(self):
        """Index changes need no working-file edit; HEAD is independently checked."""
        self.init()
        (self.repo / "clean").write_text("staged version")
        self.git("add", "clean")
        (self.repo / "clean").write_text("original\n")
        index = self.git("ls-files", "--stage", "-z")
        self.call("advance")
        self.assert_rejected(path="clean")
        self.assertEqual(self.git("ls-files", "--stage", "-z"), index)
        self.root = self.repo / ".council" / "head"
        self.init()
        self.git("commit", "--allow-empty", "-qm", "new HEAD")
        head = self.git("rev-parse", "HEAD")
        self.call("advance")
        self.assert_rejected()
        self.assertTrue(self.result["integrity"]["head_changed"])
        self.assertEqual(self.git("rev-parse", "HEAD"), head)

    def test_add_delete_mode_symlink_and_type(self):
        """Compare existence, executable bits, and link text as well as bytes."""
        self.init()
        (self.repo / "added").write_text("new")
        (self.repo / "delete").unlink()
        (self.repo / "clean").chmod(0o755)
        (self.repo / "link").unlink()
        (self.repo / "link").symlink_to("dirty")
        (self.repo / "untracked").unlink()
        (self.repo / "untracked").mkdir()
        self.call("advance")
        self.assert_rejected()
        self.assertTrue({"added", "delete", "clean", "link", "untracked"}.issubset(
            self.result["integrity"]["changed_paths"]))

    def test_missing_corrupt_and_unreadable_baseline(self):
        """Losing evidence is never permission to accept a result."""
        for case in ("missing", "corrupt", "unreadable"):
            self.root = self.repo / ".council" / case
            self.init()
            baseline = self.root / "BASELINE.json"
            if case == "missing":
                baseline.unlink()
            elif case == "corrupt":
                baseline.write_text("{}")
            if case == "unreadable":
                import council_integrity
                original = council_integrity.read_evidence
                def read(path):
                    if path == baseline:
                        raise PermissionError("injected baseline read denial")
                    return original(path)
                with patch.object(council_integrity, "read_evidence", read):
                    self.call("advance")
            else:
                self.call("advance")
            self.assert_rejected("unverified")

    def test_required_boundaries(self):
        """Neither dispatch, phase progression, recovery nor finish bypasses checks."""
        for checkpoint in ("begin-phase", "dispatch-attempted", "delivery", "recover", "next-phase", "finish"):
            self.root = self.repo / ".council" / checkpoint
            self.init()
            if checkpoint == "dispatch-attempted":
                self.call("begin-phase", phase="research")
            elif checkpoint != "begin-phase":
                self.begin()
                if checkpoint in ("next-phase", "finish"):
                    for n in (1, 2, 3):
                        self.deliver(n)
                if checkpoint == "finish":
                    self.begin("vote")
                    for n in (1, 2, 3):
                        self.deliver(n)
            with (self.repo / "clean").open("a") as stream:
                stream.write(checkpoint)
            if checkpoint in ("begin-phase", "next-phase"):
                self.call("begin-phase", phase="research" if checkpoint == "begin-phase" else "vote")
            elif checkpoint == "dispatch-attempted":
                self.event(1, checkpoint)
            elif checkpoint == "delivery":
                self.deliver(1)
            elif checkpoint == "recover":
                self.call("recover", chair="chair", reachable=["agent-1", "agent-2", "agent-3"])
            else:
                self.call("finish", outcome="decision", markdown="Must not publish")
            self.assert_rejected(path="clean")

    def test_resume_retains_baseline_and_deadline(self):
        """Recovery of unchanged inputs does not grant fresh time."""
        self.init()
        self.begin()
        baseline = (self.root / "BASELINE.json").read_bytes()
        deadline = self.result["state"]["hard_deadline"]
        self.now = [x + 10 for x in self.now]
        self.call("recover", chair="chair", reachable=["agent-1", "agent-2", "agent-3"])
        self.assertTrue(self.result["ok"])
        self.assertEqual(self.result["state"]["hard_deadline"], deadline)
        self.assertEqual((self.root / "BASELINE.json").read_bytes(), baseline)

    def test_other_sitting_and_unowned_scratch_not_exempt(self):
        """Exclusions do not swallow arbitrary ignored output."""
        self.init()
        (self.root / "notes.txt").write_text("unowned")
        other = self.repo / ".council" / "other"
        other.mkdir()
        (other / "QUESTION.md").write_text("other sitting")
        self.call("advance")
        self.assert_rejected()
        self.assertIn(".council/sitting/notes.txt", self.result["integrity"]["changed_paths"])
        self.assertIn(".council/other/QUESTION.md", self.result["integrity"]["changed_paths"])

    def test_real_cli_nonzero_integrity_failure(self):
        """A durable abort is also a failed command, not ok:true."""
        self.init()
        (self.repo / "clean").write_text("changed")
        proc = subprocess.run([sys.executable, "-B", str(BIN / "council-state.py"),
                               "advance", str(self.root)], input=json.dumps({"revision": 0}),
                              text=True, capture_output=True, check=False)
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertFalse(json.loads(proc.stdout)["ok"])

    def test_legacy_baseline_and_reconciliation(self):
        """Legacy evidence fails closed; a fresh reconciled sitting evaluates anew."""
        self.init()
        state_path = self.root / "STATE.json"
        state = json.loads(state_path.read_text())
        del state["baseline"]
        state_path.write_text(json.dumps(state))
        self.call("recover", chair="chair", reachable=[])
        self.assert_rejected("unverified")
        previous = self.root
        saved = state_path.read_bytes()
        self.root = self.repo / ".council" / "reconciled"
        self.init(reconciliation=dict(previous_directory=str(previous), reason="Inputs reviewed",
                                      writers_stopped=True))
        self.assertTrue(self.result["ok"], self.result)
        self.assertEqual(self.result["state"]["proposals"], {})
        self.assertEqual(state_path.read_bytes(), saved)

    def test_nested_repositories_and_external_links_are_declared(self):
        """Unmeasured interiors and symlink targets are never claimed as checked."""
        nested = self.repo / "nested"
        nested.mkdir()
        (nested / ".git").mkdir()
        (nested / "input").write_text("before")
        external = Path(self.temp.name) / "external"
        external.write_text("before")
        (self.repo / "external-link").symlink_to(external)
        self.init()
        (nested / "input").write_text("after")
        external.write_text("after")
        self.call("advance")
        self.assertTrue(self.result["ok"], self.result)
        self.assertIn(dict(path="nested", reason="nested repository interior"),
                      self.result["integrity"]["excluded"])

    def test_owned_paths_cannot_redirect_or_hide_tracked_content(self):
        """Symlink output cannot redirect helper writes or become a broad exclusion."""
        self.init()
        self.begin()
        scratch = Path(self.result["state"]["seats"]["1"]["scratch"])
        scratch.rmdir()
        scratch.symlink_to(self.repo)
        self.call("advance")
        self.assert_rejected("unverified")
        self.assertTrue(scratch.is_symlink())
        self.root = self.repo / ".council" / "tracked"
        self.root.mkdir()
        (self.root / "QUESTION.md").write_text("tracked input")
        self.git("add", "-f", str(self.root / "QUESTION.md"))
        with self.assertRaisesRegex(ValueError, "tracked Council artifacts"):
            self.init()
        self.assertEqual((self.root / "QUESTION.md").read_text(), "tracked input")

    def test_unborn_and_linked_worktrees(self):
        """Repository identity does not depend on a normal .git directory or HEAD."""
        linked = Path(self.temp.name) / "linked"
        self.git("worktree", "add", "--detach", str(linked))
        self.repo = linked
        self.root = linked / ".council" / "linked"
        self.init()
        self.call("advance")
        self.assertTrue(self.result["ok"], self.result)
        unborn = Path(self.temp.name) / "unborn"
        unborn.mkdir()
        self.repo = unborn
        self.git("init", "-q")
        self.root = unborn / ".council" / "unborn"
        self.init()
        self.assertTrue(self.result["ok"], self.result)
        self.call("advance")
        self.assertTrue(self.result["ok"], self.result)

    def test_capture_failure_and_diagnostic_write_failure(self):
        """Incomplete evidence cannot issue permission even when reporting fails."""
        self.init()
        import council_inventory
        original = council_inventory.inventory
        def unstable(*args):
            result = original(*args)
            with (self.repo / "clean").open("a") as stream:
                stream.write("concurrent edit")
            return result
        with patch.object(council_inventory, "inventory", unstable):
            self.call("advance")
        self.assert_rejected("unverified")
        self.root = self.repo / ".council" / "write-failure"
        self.init()
        (self.repo / "clean").write_text("preserve this")
        import council_store
        write = council_store.atomic_write
        def denied(path, content):
            if path.name == "INTEGRITY.json":
                raise OSError("injected diagnostic failure")
            return write(path, content)
        with patch.object(council_store, "atomic_write", denied):
            with self.assertRaisesRegex(OSError, "diagnostic failure"):
                self.call("advance")
        persisted = json.loads((self.root / "STATE.json").read_text())
        self.assertEqual(persisted["status"], "aborted")
        self.assertEqual((self.repo / "clean").read_text(), "preserve this")

    def test_init_failure_preserves_diagnostics_and_requires_new_sitting(self):
        """A failed first capture is durable, not an undispatched green state."""
        with patch("council_integrity.stable_inventory", side_effect=PermissionError("input unreadable")):
            self.init()
        self.assert_rejected("unverified")
        self.assertFalse((self.root / "BASELINE.json").exists())
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.init()

    def test_raw_filename_encoding_and_filesystem_capability(self):
        """Lossless bytes are required even where APFS rejects their creation."""
        from council_inventory import canonical
        name = "raw-\udcff"
        self.assertEqual(os.fsencode(json.loads(canonical(name))), b"raw-\xff")
        try:
            (self.repo / name).write_bytes(b"before")
        except OSError as exc:
            if exc.errno != errno.EILSEQ:
                raise
            self.assertEqual(sys.platform, "darwin")
            return
        self.init()
        (self.repo / name).write_bytes(b"after")
        self.call("advance")
        self.assert_rejected(path=name)

    def test_index_refresh_is_not_drift_and_unmerged_index_is_covered(self):
        """Cache metadata changes require semantic comparison, not automatic drift."""
        self.init()
        self.git("update-index", "--index-version", "4")
        self.call("advance")
        self.assertTrue(self.result["ok"], self.result)
        oid = self.git("rev-parse", "HEAD:clean").strip().decode()
        proc = subprocess.run(["git", "-C", str(self.repo), "update-index", "--index-info"],
                              input=f"0 {'0' * 40}\tclean\n100644 {oid} 1\tclean\n".encode(),
                              capture_output=True, check=True)
        self.assertEqual(proc.returncode, 0)
        self.call("advance")
        self.assert_rejected(path="clean")

    def test_integrity_abort_has_exact_cleanup_window(self):
        """Integrity detection cannot count elapsed time twice after abort."""
        self.init()
        self.begin()
        self.now = [x + 10 for x in self.now]
        (self.repo / "clean").write_text("concurrent edit")
        self.call("advance")
        self.assert_rejected(path="clean")
        self.now = [x + 25 for x in self.now]
        self.call("status")
        self.assertEqual([x["kind"] for x in self.result["actions"]], ["cleanup"])
        self.now = [x + 5 for x in self.now]
        self.call("status")
        self.assertEqual(self.result["actions"], [])

    def test_submodule_gitlink_and_renames(self):
        """The outer index and path names remain checked at excluded interiors."""
        oid = self.git("rev-parse", "HEAD").strip().decode()
        nested = self.repo / "module"
        nested.mkdir()
        (nested / "input").write_text("nested contents")
        self.git("update-index", "--add", "--cacheinfo", f"160000,{oid},module")
        self.init()
        self.assertIn(dict(path="module", reason="nested repository interior"),
                      self.result["integrity"]["excluded"])
        (self.repo / "clean").rename(self.repo / "renamed")
        self.git("update-index", "--force-remove", "module")
        self.call("advance")
        self.assert_rejected()
        self.assertTrue({"module", "clean", "renamed"}.issubset(self.result["integrity"]["changed_paths"]))

    def test_interrupted_initial_state_write_never_replaces_baseline(self):
        """A baseline orphaned by a crash stays immutable and cannot authorize dispatch."""
        import council_store
        write = council_store.atomic_write
        def interrupted(path, content):
            if path.name == "STATE.json":
                raise OSError("interrupted state persistence")
            return write(path, content)
        with patch.object(council_store, "atomic_write", interrupted):
            with self.assertRaisesRegex(OSError, "interrupted state persistence"):
                self.init()
        saved = (self.root / "BASELINE.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.init()
        self.assertEqual((self.root / "BASELINE.json").read_bytes(), saved)

    def test_tracked_diagnostics_are_never_overwritten(self):
        """Reporting a conflict cannot erase the very evidence being protected."""
        self.init()
        target = self.root / "LIVENESS.md"
        target.write_text("user-owned tracked record")
        self.git("add", "-f", str(target))
        saved = (self.root / "STATE.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "tracked Council artifacts"):
            self.call("advance")
        self.assertEqual(target.read_text(), "user-owned tracked record")
        self.assertEqual((self.root / "STATE.json").read_bytes(), saved)

    def test_external_git_configuration_cannot_hide_read_failure(self):
        """Indirect configuration errors must invalidate cached Git evidence."""
        external = Path(self.temp.name) / "included-config"
        external.write_text("[core]\n  bare = false\n")
        self.git("config", "include.path", str(external))
        self.init()
        self.assertTrue(self.result["ok"], self.result)
        external.write_text("this is not git configuration\n")
        with self.assertRaisesRegex(ValueError, "bad config line"):
            self.call("advance")

    def test_special_evidence_files_fail_without_blocking(self):
        """An unreadable baseline or state cannot wedge before type validation."""
        for name in ("BASELINE.json", "STATE.json", "commondir"):
            with self.subTest(name=name):
                self.root = self.repo / ".council" / name
                self.init()
                self.assertTrue(self.result["ok"], self.result)
                evidence = (self.repo / ".git" if name == "commondir" else self.root) / name
                saved = evidence.read_bytes() if evidence.exists() else None
                if saved is not None:
                    evidence.unlink()
                os.mkfifo(evidence)
                try:
                    try:
                        result = subprocess.run([sys.executable, "-B", str(BIN / "council-state.py"),
                                                 "advance", str(self.root)], input='{"revision":0}',
                                                capture_output=True, text=True, timeout=8, check=False)
                    except subprocess.TimeoutExpired:
                        self.fail(f"helper blocked reading special evidence: {name}")
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(json.loads(result.stdout)["ok"])
                    self.assertTrue(evidence.is_fifo())
                finally:
                    evidence.unlink()
                    if saved is not None:
                        evidence.write_bytes(saved)


if __name__ == "__main__":
    unittest.main()
