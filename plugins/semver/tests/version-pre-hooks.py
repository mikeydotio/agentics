"""Exercise version transactions and staged hook output through the real CLI."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(sys.argv.pop(1)).resolve()
CASES = {
    "bump": (True, True, ["bump", "execute", "patch"], "patch", "v1.0.1"),
    "set": (True, True, ["set", "execute", "v2.0.0"], "set", "v2.0.0"),
    "set-first": (True, False, ["set", "execute", "v2.0.0"], "set", "v2.0.0"),
    "init": (False, False, ["init", "execute", "--mode", "fresh"], "init", "v0.1.0"),
    "reinit": (True, True, ["init", "execute", "--mode", "reinit", "--version", "v2.0.0"], "init", "v2.0.0"),
    "tracking": (False, False, ["tracking", "start", "--version", "v2.0.0"], "init", "v2.0.0"),
    "first-version": (True, False, ["bump", "first-version", "v2.0.0"], "init", "v2.0.0"),
}
HOOK = '''#!/usr/bin/env bash
set -euo pipefail
[ "${SEMVER_BUMP_IN_PROGRESS}" = 1 ]
actual='(none)'
if [ -f VERSION ]; then actual=$(cat VERSION); fi
[ "$actual" = "$OLD_VERSION" ]
printf '%s|%s|%s\\n' "$BUMP_TYPE" "$OLD_VERSION" "$NEW_VERSION" > hook-context
printf '%s\\n' "$(( $(cat BUILD) + 1 ))" > BUILD
printf '%s\\n' "$NEW_VERSION" > package-version
git add BUILD package-version hook-context
'''


class VersionPreHooks(unittest.TestCase):
    """Verify successful, failed, and unchanged version operations."""

    def fixture(self, tracking=True, version=True, hook=HOOK):
        """Make an owned repository with a release hook and build counter."""
        tmp = tempfile.TemporaryDirectory(prefix="semver-pre-", dir="/tmp")
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.git(root, "init", "-q", "-b", "main")
        self.git(root, "config", "user.name", "Test")
        self.git(root, "config", "user.email", "test@example.com")
        self.git(root, "config", "commit.gpgsign", "false")
        self.git(root, "config", "tag.gpgsign", "false")
        (root / "BUILD").write_text("10\n")
        (root / "notes").write_text("original\n")
        if tracking:
            (root / ".semver").mkdir()
            (root / ".semver/config.yaml").write_text(
                'tracking: true\nauto_bump: true\nversion_prefix: "v"\ngit_tagging: true\n'
                'changelog_format: "grouped"\ntarget_branch: "main"\n')
        if version:
            (root / "VERSION").write_text("v1.0.0\n")
            (root / "CHANGELOG.md").write_text("# Changelog\n\n## [v1.0.0] - 2026-01-01\n")
        path = root / ".semver/hooks/pre-bump/01-build.sh"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(hook)
        path.chmod(0o755)
        self.git(root, "add", "-A")
        self.git(root, "commit", "-qm", "feat: fixture")
        if version:
            self.git(root, "tag", "v1.0.0")
        return root

    def git(self, root, *args):
        """Run Git with captured diagnostics and require success."""
        result = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def cli(self, root, args, code=0, env=None):
        """Run production CLI, retaining its JSON diagnosis on failure."""
        result = subprocess.run([sys.executable, str(CLI), *args], cwd=root,
                                text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def snapshot(self, root):
        """Capture release-owned state independently of hook side effects."""
        paths = ["VERSION", "CHANGELOG.md", ".semver/config.yaml", "CLAUDE.md"]
        return [self.git(root, "rev-parse", "HEAD"), self.git(root, "tag")] + [
            (root / p).read_bytes() if (root / p).exists() else None for p in paths]

    def test_all_version_writers_commit_hook_output(self):
        """Every new version shares a commit and tag with its build identity."""
        for name, (tracking, version, args, kind, target) in CASES.items():
            with self.subTest(name=name):
                root = self.fixture(tracking, version)
                result = self.cli(root, args)
                self.assertEqual(self.git(root, "show", "HEAD:BUILD"), "11")
                self.assertEqual(self.git(root, "show", "HEAD:package-version"), target)
                self.assertEqual(self.git(root, "show", "HEAD:hook-context"),
                                 f"{kind}|{'v1.0.0' if version else '(none)'}|{target}")
                self.assertEqual(self.git(root, "show", f"{target}:BUILD"), "11")
                self.assertEqual(self.git(root, "status", "--porcelain"), "")
                self.assertEqual(result["pre_hooks"]["hooks_run"], 1)

    def test_failed_hooks_do_not_write_release_files(self):
        """A pre-hook failure cannot commit or alter version/config/changelog."""
        for name, (tracking, version, args, _, _) in CASES.items():
            with self.subTest(name=name):
                root = self.fixture(tracking, version, HOOK + 'echo broken >&2\nexit 17\n')
                before = self.snapshot(root)
                result = self.cli(root, args, code=1)
                self.assertEqual(result["error"], "pre_hook_failed")
                self.assertIn("broken", result.get("detail", ""))
                self.assertEqual(self.snapshot(root), before)
                self.assertEqual((root / "BUILD").read_text(), "11\n")

    def test_missing_runner_fails_closed_for_defined_hooks(self):
        """A missing runner must not silently bypass required pre-hooks."""
        for name, (tracking, version, args, _, _) in CASES.items():
            if name == "first-version":
                continue
            with self.subTest(name=name):
                root = self.fixture(tracking, version)
                before = self.snapshot(root)
                result = self.cli(root, args + ["--plugin-root", str(root / "missing")], code=1)
                self.assertEqual(result["error"], "pre_hook_failed")
                self.assertEqual(self.snapshot(root), before)

    def test_unchanged_versions_do_not_allocate(self):
        """Re-cut, enable, adopt, and tracking-only initialization do no build work."""
        cases = [
            (True, True, ["set", "execute", "v1.0.0"]),
            (True, True, ["init", "execute", "--mode", "enable"]),
            (False, True, ["init", "execute", "--mode", "adopt"]),
            (True, True, ["init", "execute", "--mode", "reinit", "--version", "v1.0.0"]),
            (False, False, ["tracking", "start"]),
        ]
        for tracking, version, args in cases:
            with self.subTest(args=args):
                root = self.fixture(tracking, version)
                self.cli(root, args)
                self.assertEqual((root / "BUILD").read_text(), "10\n")
                self.assertFalse((root / "hook-context").exists())

    def test_dirty_tree_handling_precedes_hooks(self):
        """Stash excludes user edits but retains staged hook output in the release."""
        for kind in ("bump", "set"):
            for action in ("stash", "include"):
                for fails in (False, True):
                    with self.subTest(kind=kind, action=action, fails=fails):
                        root = self.fixture(hook=HOOK + ('exit 17\n' if fails else ''))
                        (root / "notes").write_text("user edit\n")
                        before = self.snapshot(root)
                        args = CASES[kind][2] + ["--dirty-action", action]
                        self.cli(root, args, code=1 if fails else 0)
                        self.assertEqual((root / "notes").read_text(), "user edit\n")
                        self.assertEqual(self.git(root, "stash", "list"), "")
                        if fails:
                            self.assertEqual(self.snapshot(root), before)
                        else:
                            self.assertEqual(self.git(root, "show", "HEAD:BUILD"), "11")
                            self.assertEqual(self.git(root, "show", "HEAD:notes"),
                                             "original" if action == "stash" else "user edit")

    def test_clean_stash_action_preserves_existing_stash(self):
        """A no-op stash cannot pop a stash from an earlier user operation."""
        for kind in ("bump", "set"):
            with self.subTest(kind=kind):
                root = self.fixture()
                (root / "notes").write_text("earlier work\n")
                self.git(root, "stash", "push", "-m", "user-owned")
                before = self.git(root, "rev-parse", "refs/stash")
                result = self.cli(root, CASES[kind][2] + ["--dirty-action", "stash"])
                self.assertEqual(self.git(root, "rev-parse", "refs/stash"), before)
                self.assertFalse(result.get("stash_applied", False))
                self.assertEqual(self.git(root, "status", "--porcelain"), "")

    def test_post_hooks_observe_committed_build_and_old_version(self):
        """Pre and post hooks see the same operation context in the correct order."""
        for name, (tracking, version, args, _, _) in CASES.items():
            with self.subTest(name=name):
                root = self.fixture(tracking, version)
                post = root / ".semver/hooks/post-bump/01-check.sh"
                post.parent.mkdir(parents=True)
                post.write_text('''#!/usr/bin/env bash
set -euo pipefail
[ "$(git show HEAD:BUILD)" = 11 ]
[ "$(cat VERSION)" = "$NEW_VERSION" ]
[ "$(cat hook-context)" = "$BUMP_TYPE|$OLD_VERSION|$NEW_VERSION" ]
''')
                post.chmod(0o755)
                self.git(root, "add", "-A")
                self.git(root, "commit", "-qm", "test: post-hook")
                result = self.cli(root, args)
                self.assertEqual(result["post_hooks"]["hooks_run"], 1)
                self.assertEqual(result["post_hooks"]["warnings"], [])

    def test_nested_operations_fail_before_writes(self):
        """Direct execute paths honor the same recursion guard as run paths."""
        for name, (tracking, version, args, _, _) in CASES.items():
            with self.subTest(name=name):
                root = self.fixture(tracking, version)
                before = self.snapshot(root)
                result = self.cli(root, args, code=1,
                                  env={**os.environ, "SEMVER_BUMP_IN_PROGRESS": "1"})
                self.assertEqual(result["error"], "reentrancy")
                self.assertEqual(self.snapshot(root), before)
                self.assertEqual((root / "BUILD").read_text(), "10\n")

    def test_dirty_file_names_are_lossless(self):
        """Git status columns and quoting must never become filename content."""
        root = self.fixture()
        self.git(root, "commit", "--allow-empty", "-qm", "feat: release candidate")
        (root / "BUILD").write_text("11\n")
        strange = [" leading space ", "line\nbreak", "quote\"name", "unicode-é"]
        for name in strange:
            (root / name).write_text("new file\n")
        self.git(root, "mv", "notes", "renamed notes")
        expected = {"BUILD", "renamed notes", *strange}
        for args in (["bump", "gather", "patch"], ["set", "run", "v2.0.0"]):
            with self.subTest(args=args):
                result = self.cli(root, args)
                self.assertEqual(set(result["dirty_files"]), expected)

    def test_set_prompt_hook_hands_back_without_mutation(self):
        """Set run must let the agent review pre-bump prompt instructions first."""
        root = self.fixture()
        prompt = root / ".semver/hooks/pre-bump/PROMPT_HOOK.md"
        prompt.write_text("Review the release.\n")
        self.git(root, "add", "-A")
        self.git(root, "commit", "-qm", "docs: pre-hook prompt")
        before = self.snapshot(root)
        result = self.cli(root, ["set", "run", "v2.0.0"])
        self.assertFalse(result["executed"])
        self.assertTrue(result["has_pre_bump_prompt_hook"])
        self.assertEqual(self.snapshot(root), before)
        self.assertEqual((root / "BUILD").read_text(), "10\n")
        result = self.cli(root, ["set", "run", "v2.0.0", "--non-interactive"], code=1)
        self.assertEqual(result["error"], "non_interactive_blocked")
        self.assertEqual(self.snapshot(root), before)

    def test_init_prompt_hook_hands_back_without_mutation(self):
        """Fresh init also pauses for the pre-hook prompt before creating artifacts."""
        root = self.fixture(False, False)
        prompt = root / ".semver/hooks/pre-bump/PROMPT_HOOK.md"
        prompt.write_text("Review the release.\n")
        self.git(root, "add", "-A")
        self.git(root, "commit", "-qm", "docs: pre-hook prompt")
        before = self.snapshot(root)
        result = self.cli(root, ["init", "run"])
        self.assertFalse(result["executed"])
        self.assertTrue(result["has_pre_bump_prompt_hook"])
        self.assertEqual(self.snapshot(root), before)
        self.assertEqual((root / "BUILD").read_text(), "10\n")


if __name__ == "__main__":
    unittest.main()
