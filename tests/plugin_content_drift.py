"""Exercise release identity through the production CLI and real Git fixtures."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts/check-plugin-content.sh"
GIT = shutil.which("git")
BASH = shutil.which("bash")
TOOL = "plugins/alpha/bin/tool"


class ContentIdentityTests(unittest.TestCase):
    """Pin candidate disclosure and strict release refusal independently."""

    def setUp(self):
        """Create a tagged marketplace with no ambient Git configuration."""
        self.assertIsNotNone(GIT, "git is required")
        self.assertIsNotNone(BASH, "bash is required")
        self.temp = tempfile.TemporaryDirectory(prefix="age84-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "repo with spaces"
        self.repo.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
                        TMPDIR=str(self.home))
        self.git("init", "-q", "--template=")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.write("VERSION", "v1.0.0\n")
        self.write(TOOL, "original\n")
        for path in (".claude-plugin/marketplace.json",
                     "plugins/alpha/.claude-plugin/plugin.json",
                     "plugins/alpha/.codex-plugin/plugin.json"):
            self.write(path, '{"name":"alpha","version":"1.0.0"}\n')
        self.commit()
        self.git("tag", "v1.0.0")

    def git(self, *args):
        """Require fixture preparation to succeed before testing a verdict."""
        return subprocess.run([GIT, "-C", str(self.repo), *args], env=self.env,
                              capture_output=True, text=True, check=True).stdout.strip()

    def write(self, path, content):
        """Write one fixture input without changing the production checkout."""
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def commit(self):
        """Record fixture inputs using normal Git history."""
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")

    def check(self, mode=None, *, repo=None, env=None, extra=(), checker=CHECKER):
        """Invoke the public checker; never reproduce its policy in the harness."""
        args = [BASH, str(checker), "--repo", str(repo or self.repo)]
        if mode is not None:
            args.extend(["--mode", mode])
        return subprocess.run([*args, *extra], env=env or self.env,
                              capture_output=True, text=True)

    def verdict(self, mode, code, state, **kwargs):
        """Require the exact exit class and a substantive diagnostic."""
        result = self.check(mode, **kwargs)
        message = result.stdout + result.stderr
        self.assertEqual(code, result.returncode, message)
        self.assertIn(state, message)
        if mode == "candidate" and code == 0:
            self.assertIn("release readiness is not certified", message)
        return message

    def drift(self, path=TOOL, **kwargs):
        """Require both acceptance with disclosure and strict refusal."""
        for mode, code in (("candidate", 0), ("release", 1)):
            output = self.verdict(mode, code, "unreleased-changes", **kwargs)
            self.assertIn(path, output)

    def test_clean_and_annotated_tags(self):
        """Both Git tag kinds identify the same content."""
        for annotated in (False, True):
            if annotated:
                self.git("tag", "-d", "v1.0.0")
                self.git("tag", "-a", "v1.0.0", "-m", "release")
            for mode in ("candidate", "release", None):
                self.verdict(mode, 0, "release-matched")

    def test_default_mode_is_strict(self):
        """An old or new direct caller cannot accidentally certify a candidate."""
        self.write(TOOL, "changed")
        self.verdict(None, 1, "unreleased-changes")

    def test_runtime_change_kinds(self):
        """Content, tree structure, modes and links all affect identity."""
        changes = ("modify", "add", "delete", "rename", "mode", "symlink")
        for change in changes:
            with self.subTest(change=change):
                self.git("reset", "--hard", "v1.0.0")
                if change == "modify":
                    self.write(TOOL, "changed")
                elif change == "add":
                    self.write("plugins/beta/bin/new", "new plugin")
                elif change == "delete":
                    (self.repo / TOOL).unlink()
                elif change == "rename":
                    self.git("mv", TOOL, "plugins/alpha/bin/renamed")
                elif change == "mode":
                    (self.repo / TOOL).chmod(0o755)
                else:
                    (self.repo / TOOL).unlink()
                    (self.repo / TOOL).symlink_to("elsewhere")
                self.commit()
                self.drift("plugins/beta/bin/new" if change == "add" else TOOL)

    def test_checkout_forms_and_inherited_drift(self):
        """Linked and detached candidates retain the full release comparison."""
        self.write(TOOL, "inherited change")
        self.commit()
        self.write("docs/note.md", "candidate only changes documentation")
        self.commit()
        linked = self.home / "linked"
        self.git("worktree", "add", "--detach", str(linked), "HEAD")
        self.drift(repo=linked)
        self.git("checkout", "--detach")
        self.drift()

    def test_working_copy_layers(self):
        """Index changes cannot be cancelled out by a worktree reversal."""
        self.write(TOOL, "unstaged")
        self.drift()
        self.git("add", TOOL)
        self.drift()
        self.write(TOOL, "original\n")
        self.drift()

    def test_untracked_including_ignored_runtime(self):
        """Ignored shipped files remain possible local install inputs."""
        for ignored in (False, True):
            if ignored:
                self.write(".gitignore", "plugins/beta/\n")
            self.write("plugins/beta/bin/new", "untracked")
            self.drift("plugins/beta/bin/new")

    def test_exclusions_across_layers(self):
        """Only existing test and top-level plugin README exclusions survive."""
        for path in ("plugins/alpha/tests/deep/test.sh", "plugins/alpha/bin/x.bats",
                     "plugins/alpha/README.md", "docs/unrelated.md"):
            self.write(path, "excluded")
        for stage in ("untracked", "staged", "committed"):
            if stage == "staged":
                self.git("add", "-A")
            elif stage == "committed":
                self.commit()
            self.verdict("release", 0, "release-matched")
        self.write("plugins/alpha/references/README.md", "runtime")
        self.drift("plugins/alpha/references/README.md")

    def test_manifests_and_marketplace(self):
        """Both host manifests and marketplace metadata affect identity."""
        for path in (".claude-plugin/marketplace.json",
                     "plugins/alpha/.claude-plugin/plugin.json",
                     "plugins/alpha/.codex-plugin/plugin.json"):
            with self.subTest(path=path):
                self.write(path, '{"changed":true}')
                self.drift(path)
                self.git("restore", path)

    def test_missing_tag_and_untagged_version(self):
        """Absence is explicit candidate evidence and a strict release failure."""
        self.git("tag", "-d", "v1.0.0")
        for version in ("v1.0.0", "1.0.1"):
            self.write("VERSION", version + "\n")
            self.verdict("candidate", 0, "baseline-unavailable")
            self.verdict("release", 1, "baseline-unavailable")

    def test_invalid_versions(self):
        """Malformed SemVer never becomes a Git ref or an absent baseline."""
        for value in ("", "v", "1.2", "01.2.3", "1.2.3-01", "1.2.3+",
                      "1.2.3\nextra", "1. 2.3", "../main", "1.2.3/a",
                      "v1.0.0\x00", "v1.0.0\n"):
            with self.subTest(value=value):
                self.write("VERSION", value + "\n")
                for mode in ("candidate", "release"):
                    self.verdict(mode, 1, "VERSION")
        (self.repo / "VERSION").unlink()
        self.verdict("candidate", 1, "VERSION")

    def test_valid_prerelease_and_build_versions(self):
        """Valid SemVer identifiers are not mistaken for malformed versions."""
        for version in ("1.0.1-alpha.0+build.01", "v1.0.1-0A"):
            self.write("VERSION", version + "\n")
            self.commit()
            self.git("tag", "v" + version.removeprefix("v"))
            self.verdict("release", 0, "release-matched")

    def test_noncommit_and_corrupt_tag(self):
        """Existing unusable tag objects must never be reported as absent."""
        self.git("tag", "-d", "v1.0.0")
        self.git("tag", "v1.0.0", self.git("rev-parse", "HEAD:VERSION"))
        for mode in ("candidate", "release"):
            self.verdict(mode, 1, "release tag")
        self.write(".git/refs/tags/v1.0.0", "f" * 40 + "\n")
        self.verdict("candidate", 1, "release tag")

    def test_invalid_repository_and_head(self):
        """Repository and HEAD failures are verification errors."""
        self.verdict("candidate", 1, "repository", repo=self.home)
        self.git("checkout", "--orphan", "unborn")
        self.verdict("candidate", 1, "HEAD")

    def test_unusual_paths_are_unambiguous(self):
        """Each reported path can be decoded to its original filename."""
        paths = ["plugins/alpha/bin/" + name for name in
                 ("with space", "with\ttab", "with\nnewline", "-leading")]
        for path in paths:
            self.write(path, "new")
        output = self.verdict("release", 1, "unreleased-changes")
        reported = [line.removeprefix("  ") for line in output.splitlines()
                    if line.startswith("  ")]
        decoded = subprocess.run([BASH, "-c", "printf '%s\\0' " + " ".join(reported)],
                                 capture_output=True, check=True).stdout.split(b"\0")[:-1]
        self.assertEqual(set(map(os.fsencode, paths)), set(decoded))

    def test_arguments(self):
        """Invalid invocations retain a distinct usage exit code."""
        for args in (("--unknown",), ("--mode",), ("--mode", "oops"), ("--repo",)):
            result = self.check(extra=args)
            self.assertEqual(2, result.returncode, result.stderr)
            self.assertIn("usage:", result.stderr)

    def test_missing_git_and_git_failures(self):
        """A failed Git producer cannot be mistaken for an empty path list."""
        shims = self.home / "shims"
        shims.mkdir()
        env = dict(self.env, PATH=str(shims))
        self.verdict("candidate", 1, "git is required", env=env)
        for command in ("for-each-ref", "diff", "ls-files"):
            with self.subTest(command=command):
                shim = shims / "git"
                shim.write_text('#!/bin/bash\nfor arg in "$@"; do\n'
                                f'  if [ "$arg" = "{command}" ]; then\n'
                                '    echo "fixture Git failure" >&2; exit 73\n  fi\ndone\n'
                                f'exec "{GIT}" "$@"\n')
                shim.chmod(0o755)
                env["PATH"] = str(shims) + ":" + self.env["PATH"]
                self.verdict("candidate", 1, "fixture Git failure", env=env)

    def test_make_targets(self):
        """Production recipes preserve checker verdicts and prerequisite errors."""
        shutil.copy(ROOT / "Makefile", self.repo / "Makefile")
        (self.repo / "scripts").mkdir()
        shutil.copy(CHECKER, self.repo / "scripts/check-plugin-content.sh")
        # The regression suite and manifest suite are external prerequisites to
        # this wiring test. Substitute their exits; always use the real checker.
        self.write("tests/with-isolated-store.sh", '"$@"\n')
        self.write("tests/plugin-content-drift.sh", 'echo fixture-regressions; exit "${FIXTURE_SUITE_EXIT:-0}"\n')
        self.write("tests/plugin-versions.sh", 'echo fixture-manifests; exit "${FIXTURE_SUITE_EXIT:-0}"\n')
        for changed in (False, True):
            if changed:
                self.write(TOOL, "unreleased")
            for target in ("test-plugin-content-drift", "validate-release"):
                result = subprocess.run(["make", "-C", str(self.repo), target],
                                        env=self.env, capture_output=True, text=True)
                expected = 2 if changed and target == "validate-release" else 0
                self.assertEqual(expected, result.returncode, result.stdout + result.stderr)
                mode = "candidate" if target == "test-plugin-content-drift" else "release"
                self.assertIn("mode=" + mode, result.stdout)
                env = dict(self.env, FIXTURE_SUITE_EXIT="7")
                result = subprocess.run(["make", "-C", str(self.repo), target],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(2, result.returncode, result.stdout + result.stderr)
                self.assertNotIn("mode=", result.stdout)

    def test_default_repository_is_script_repository(self):
        """Unrelated cwd and ambient hook variables cannot select the inputs."""
        (self.repo / "scripts").mkdir()
        copied = self.repo / "scripts/check-plugin-content.sh"
        shutil.copy(CHECKER, copied)
        env = dict(self.env, GIT_DIR=str(self.home / "invalid"),
                   GIT_WORK_TREE=str(self.home), GIT_INDEX_FILE=str(self.home / "bad-index"))
        result = subprocess.run([BASH, str(copied)], cwd=self.home, env=env,
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("release-matched", result.stdout)

    def test_private_alternate_objects_preserve_source_identity(self):
        """Verifier-only objects remain readable without redirecting the checkout."""
        source_objects = self.repo / ".git/objects"
        lease = self.home / 'lease objects:private'
        lease.mkdir()
        unused = self.home / "unused objects"
        unused.mkdir()
        linked = self.home / "candidate checkout"
        self.git("worktree", "add", "--detach", str(linked), "HEAD")
        self.repo = linked
        ordinary_env = self.env
        alternates = str(unused) + ":" + json.dumps(str(lease))
        for changed in (False, True):
            # Only the immutable candidate objects go into the private store.
            # The linked checkout still owns its refs, HEAD and index.
            self.env = dict(ordinary_env, GIT_OBJECT_DIRECTORY=str(lease),
                            GIT_ALTERNATE_OBJECT_DIRECTORIES=str(source_objects))
            if changed:
                self.write(TOOL, "candidate change")
                self.git("add", TOOL)
            self.git("commit", "--allow-empty", "-qm", "private candidate")
            head = self.git("rev-parse", "HEAD")
            self.env = ordinary_env
            missing = subprocess.run([GIT, "-C", str(linked), "cat-file", "-e", head],
                                     env=ordinary_env, capture_output=True)
            self.assertNotEqual(0, missing.returncode, "HEAD leaked into shared objects")
            env = dict(ordinary_env, GIT_ALTERNATE_OBJECT_DIRECTORIES=alternates,
                       GIT_DIR=str(self.home / "wrong-git-dir"),
                       GIT_COMMON_DIR=str(self.home / "wrong-common-dir"),
                       GIT_WORK_TREE=str(self.home),
                       GIT_INDEX_FILE=str(self.home / "wrong-index"),
                       GIT_OBJECT_DIRECTORY=str(self.home / "wrong-write-store"))
            for mode in ("candidate", "release"):
                with self.subTest(changed=changed, mode=mode):
                    self.verdict(mode, 1, "cannot resolve HEAD")
                    code = 1 if changed and mode == "release" else 0
                    state = "unreleased-changes" if changed else "release-matched"
                    output = self.verdict(mode, code, state, env=env)
                    self.assertIn(head, output)
                    if changed:
                        self.assertIn(TOOL, output)

    def test_hidden_worktree_changes_fail_with_context(self):
        """Index shortcuts cannot certify content Git was told not to inspect."""
        for flag in ("assume-unchanged", "skip-worktree"):
            with self.subTest(flag=flag):
                self.git("update-index", "--" + flag, TOOL)
                self.write(TOOL, "hidden change")
                for mode in ("candidate", "release"):
                    output = self.verdict(mode, 1, "index flags")
                    self.assertIn(TOOL, output)
                self.git("update-index", "--no-" + flag, TOOL)
                self.git("restore", TOOL)

    def test_caller_locale_preserves_clean_drift_and_hidden_verdicts(self):
        """ASCII index markers retain their meaning under caller collation."""
        for variable in ("LC_ALL", "LC_COLLATE", "LANG"):
            for caller_locale in ("C", "en_US.UTF-8"):
                with self.subTest(variable=variable, locale=caller_locale):
                    env = {k: v for k, v in self.env.items()
                           if k != "LANG" and not k.startswith("LC_")}
                    env[variable] = caller_locale
                    for mode in ("candidate", "release"):
                        self.verdict(mode, 0, "release-matched", env=env)
                    self.write(TOOL, "visible change")
                    self.drift(env=env)
                    self.git("restore", TOOL)
                    for flag in ("assume-unchanged", "skip-worktree"):
                        self.git("update-index", "--" + flag, TOOL)
                        try:
                            self.write(TOOL, "hidden change")
                            for mode in ("candidate", "release"):
                                output = self.verdict(mode, 1, "index flags", env=env)
                                self.assertIn(TOOL, output)
                        finally:
                            self.git("update-index", "--no-" + flag, TOOL)
                            self.git("restore", TOOL)


if __name__ == "__main__":
    unittest.main(verbosity=2)
