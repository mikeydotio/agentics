"""Exercise real archive and Git recovery against disposable dirty worktrees."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/preserve-worktree.py"
sys.path.insert(0, str(CLI.parent))
SPEC = importlib.util.spec_from_file_location("preserve_worktree", CLI)
PRESERVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRESERVE)


class PreservationTests(unittest.TestCase):
    """Own every fixture and exercise the production CLI end to end."""

    def setUp(self):
        """Build a fixture with committed and staged-only objects."""
        self.temp = tempfile.TemporaryDirectory(prefix="age66-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
                        GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid",
                        PYTHONDONTWRITEBYTECODE="1")
        self.git("init", "-b", "fixture")
        for name in ("modified", "deleted", "staged"):
            (self.repo / name).write_text("base\n")
        (self.repo / ".gitignore").write_text("ignored\n")
        self.git("add", ".")
        self.git("commit", "-m", "fixture baseline")
        (self.repo / "modified").write_text("dirty\n")
        (self.repo / "deleted").unlink()
        (self.repo / "staged").write_bytes(b"staged\x00binary")
        self.git("add", "staged")
        (self.repo / "staged").write_bytes(b"unstaged\x00binary")
        (self.repo / "ignored").write_text("private evidence\n")
        (self.repo / "space ü\nname").write_bytes(bytes(range(256)))
        (self.repo / "executable").write_text("#!/bin/sh\nexit 0\n")
        (self.repo / "executable").chmod(0o751)
        (self.repo / "empty").mkdir()
        os.link(self.repo / "modified", self.repo / "hardlink")
        self.external = self.root / "outside"
        self.external.write_text("never follow\n")
        (self.repo / "symlink").symlink_to(self.external)
        (self.repo / "dangling").symlink_to("absent")
        self.archive = self.root / "archive"
        self.restored = self.root / "restored"

    def git(self, *args, cwd=None):
        """Run real fixture Git without user hooks or configuration."""
        return subprocess.check_output(["git", "-c", "core.hooksPath=/dev/null", *args],
                                       cwd=cwd or self.repo, env=self.env, stderr=subprocess.PIPE)

    def cli(self, command, source=None, destination=None, success=True):
        """Require the CLI verdict and retain diagnostics on failure."""
        result = subprocess.run([sys.executable, "-W", "error", str(CLI), command,
                                 str(source or self.repo), str(destination or self.archive)],
                                env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_independent_round_trip(self):
        """Recover all content and index state after the source disappears."""
        before = self.git("status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored")
        index = (self.repo / ".git/index").read_bytes()
        self.cli("capture")
        self.assertEqual(index, (self.repo / ".git/index").read_bytes())
        self.repo.rename(self.root / "source-unavailable")
        result = subprocess.run([sys.executable, "-W", "error",
                                 str(self.archive / "restore/preserve-worktree.py"), "verify",
                                 str(self.archive), str(self.restored)],
                                env=self.env, capture_output=True, text=True, cwd=self.root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = self.git("status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored", cwd=self.restored)
        self.assertEqual(before, after)
        self.assertEqual(self.git("show", ":staged", cwd=self.restored), b"staged\x00binary")
        self.assertEqual((self.restored / "staged").read_bytes(), b"unstaged\x00binary")
        self.assertEqual((self.restored / "space ü\nname").read_bytes(), bytes(range(256)))
        self.assertEqual((self.restored / "executable").stat().st_mode & 0o777, 0o751)
        self.assertEqual((self.restored / "modified").stat().st_ino,
                         (self.restored / "hardlink").stat().st_ino)
        self.assertTrue((self.restored / "empty").is_dir())
        self.assertEqual(os.readlink(self.restored / "symlink"), str(self.external))
        self.assertEqual(self.external.read_text(), "never follow\n")
        self.assertFalse((self.restored / "deleted").exists())
        self.assertTrue(json.loads((self.archive / "verification.json").read_text())["verified"])

    def test_existing_destinations_are_untouched(self):
        """Capture and restore cannot overwrite existing evidence."""
        self.archive.mkdir()
        sentinel = self.archive / "sentinel"
        sentinel.write_text("keep")
        self.cli("capture", success=False)
        self.assertEqual(sentinel.read_text(), "keep")
        sentinel.unlink()
        self.archive.rmdir()
        self.cli("capture")
        self.restored.mkdir()
        self.cli("verify", self.archive, self.restored, success=False)
        self.assertEqual(list(self.restored.iterdir()), [])

    def test_corruption_fails_before_restore(self):
        """Checksums protect every recorded archive component."""
        self.cli("capture")
        payload = self.archive / "payload.tar"
        with payload.open("ab") as stream:
            stream.write(b"corrupt")
        self.cli("verify", self.archive, self.restored, success=False)
        self.assertFalse((self.archive / "verification.json").exists())
        self.assertFalse(self.restored.exists())

    def test_missing_staged_object_fails(self):
        """A missing staged-only blob cannot produce a complete archive."""
        oid = self.git("rev-parse", ":staged").decode().strip()
        (self.repo / ".git/objects" / oid[:2] / oid[2:]).unlink()
        self.cli("capture", success=False)
        self.assertFalse((self.archive / "SHA256SUMS.json").exists())

    def test_output_inside_source_is_rejected(self):
        """Capture never writes into the read-only source tree."""
        self.cli("capture", destination=self.repo / "archive", success=False)
        self.assertFalse((self.repo / "archive").exists())

    def test_source_mutation_rejects_capture(self):
        """A real edit during archive creation invalidates the capture."""
        original = PRESERVE.run

        def write_during_archive(argv, **kwargs):
            """Inject an external writer at a deterministic archive boundary."""
            result = original(argv, **kwargs)
            if argv[0] == "/usr/bin/tar":
                (self.repo / "modified").write_text("concurrent writer\n")
            return result

        with patch.object(PRESERVE, "run", side_effect=write_during_archive):
            with self.assertRaisesRegex(RuntimeError, "source changed during capture"):
                PRESERVE.capture(self.repo, self.archive)
        self.assertFalse((self.archive / "SHA256SUMS.json").exists())

    def test_open_source_is_rejected(self):
        """An actual open writable descriptor prevents a coherent-capture claim."""
        with (self.repo / "modified").open("a"):
            result = self.cli("capture", success=False)
        self.assertIn("source is open", result.stderr)
        self.assertFalse(self.archive.exists())

    def test_restore_mismatch_is_not_verified(self):
        """Independent comparison rejects internally inconsistent evidence."""
        self.cli("capture")
        path = self.archive / "inventory.json"
        data = json.loads(path.read_text())
        data["modified"]["sha256"] = "0" * 64
        path.write_text(json.dumps(data))
        checksums = self.archive / "SHA256SUMS.json"
        data = json.loads(checksums.read_text())
        data[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        checksums.write_text(json.dumps(data))
        result = self.cli("verify", self.archive, self.restored, success=False)
        self.assertIn("filesystem restoration mismatch", result.stderr)
        self.assertFalse((self.archive / "verification.json").exists())

    def test_mac_metadata_round_trip(self):
        """Restore real xattrs, ACLs, flags, and nanosecond modification times."""
        file = self.repo / "executable"
        subprocess.run(["/usr/bin/xattr", "-w", "io.mikey.age66", "evidence", str(file)], check=True)
        subprocess.run(["/bin/chmod", "+a", "everyone allow read", str(file)], check=True)
        os.chflags(file, 1)
        expected_acl = subprocess.check_output(["/bin/ls", "-lden", str(file)]).splitlines()[1:]
        os.utime(file, ns=(1600000000123456789, 1600000000123456789))
        self.cli("capture")
        self.cli("verify", self.archive, self.restored)
        self.assertEqual(subprocess.check_output(["/usr/bin/xattr", "-p", "io.mikey.age66",
                                                str(self.restored / "executable")]), b"evidence\n")
        self.assertEqual(file.stat().st_mtime_ns, (self.restored / "executable").stat().st_mtime_ns)
        self.assertEqual((self.restored / "executable").stat().st_flags, 1)
        acl = subprocess.check_output(["/bin/ls", "-lden", str(self.restored / "executable")]).splitlines()[1:]
        self.assertTrue(expected_acl)
        self.assertEqual(expected_acl, acl)

    def test_restore_preserves_nondefault_group(self):
        """Source ownership must survive a destination with another default group."""
        group = next(g for g in os.getgroups() if g != self.repo.stat().st_gid)
        os.chown(self.repo / "modified", -1, group)
        self.cli("capture")
        self.cli("verify", self.archive, self.restored)
        self.assertEqual((self.restored / "modified").stat().st_gid, group)

    def test_linked_worktree_is_independent(self):
        """Never restore a linked worktree's pointer into shared Git storage."""
        linked = self.root / "linked"
        self.git("worktree", "add", "-b", "linked", str(linked))
        (linked / "untracked").write_text("unique\n")
        common_before = (self.repo / ".git/config").read_bytes()
        self.cli("capture", linked)
        self.cli("verify", self.archive, self.restored)
        self.assertTrue((self.restored / ".git").is_dir())
        self.assertEqual((self.restored / "untracked").read_text(), "unique\n")
        self.assertEqual(common_before, (self.repo / ".git/config").read_bytes())
        self.assertEqual(self.git("rev-parse", "--git-common-dir", cwd=self.restored).strip(), b".git")

    def test_repeat_recovery_preserves_first_receipt(self):
        """An archive remains recoverable after its first successful verification."""
        self.cli("capture")
        self.cli("verify", self.archive, self.restored)
        receipt = (self.archive / "verification.json").read_bytes()
        self.cli("verify", self.archive, self.root / "second-recovery")
        self.assertEqual(receipt, (self.archive / "verification.json").read_bytes())

    def test_split_index_round_trip(self):
        """Archive shared index dependencies instead of relying on source Git files."""
        self.git("update-index", "--split-index")
        self.cli("capture")
        self.repo.rename(self.root / "source-unavailable")
        self.cli("verify", self.archive, self.restored)
        self.assertEqual(self.git("show", ":staged", cwd=self.restored), b"staged\x00binary")


if __name__ == "__main__":
    unittest.main()
