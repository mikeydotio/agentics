"""AGE-77: prove integrity regressions reject removed safeguards in copied code."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IntegrityMutationTests(unittest.TestCase):
    """Require successful named controls before interpreting mutation failures."""

    def test_integrity_mutations(self):
        """Content, coverage, failure, and integration assertions kill real mutants."""
        cases = (
            ("council_store.py", 'if check["status"] != "clean":', 'if False:',
             "test_required_boundaries"),
            ("council_inventory.py", 'sha256=digest.hexdigest()', 'sha256="status-only"',
             "test_dirty_edit_preserved_despite_identical_status"),
            ("council_inventory.py", 'if path in ignored_files:',
             'if path in ignored_files or path == "ignored":',
             "test_clean_untracked_ignored_and_unusual_paths"),
            ("council_integrity.py", 'result["details"] = [f"Cannot verify repository inputs: {exc}"]',
             'result.update(status="clean", details=[])',
             "test_missing_corrupt_and_unreadable_baseline"),
            ("council_git.py", 'cached and guard.startswith("files:") and', 'cached and',
             "test_external_git_configuration_cannot_hide_read_failure"),
            ("council_store.py", 'state.update(clock_wall=now, clock_mono=mono)', 'pass',
             "test_integrity_abort_has_exact_cleanup_window"),
        )
        with tempfile.TemporaryDirectory(prefix="age77-mutants-", dir="/tmp") as temp:
            copied = Path(temp) / "council"
            shutil.copytree(ROOT, copied)
            env = dict(os.environ, COUNCIL_TEST_ROOT=str(copied), PYTHONDONTWRITEBYTECODE="1")
            tests = [f"IntegrityTests.{case[3]}" for case in cases]
            argv = [sys.executable, "-B", "-W", "error", str(copied / "tests/test_integrity.py")]
            baseline = subprocess.run(argv + tests, env=env, capture_output=True,
                                      text=True, timeout=180, check=False)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            self.assertIn("Ran 6 tests", baseline.stderr)
            print("PASS: all six mutation controls ran successfully", flush=True)
            for file, original, changed, test in cases:
                with self.subTest(test=test):
                    path = copied / "bin" / file
                    source = path.read_text()
                    self.assertEqual(source.count(original), 1, "mutation must apply exactly once")
                    path.write_text(source.replace(original, changed))
                    try:
                        proc = subprocess.run(argv + [f"IntegrityTests.{test}"], env=env,
                                              capture_output=True, text=True, timeout=180, check=False)
                        self.assertNotEqual(proc.returncode, 0, "mutant survived")
                        self.assertIn("FAIL: " + test, proc.stderr)
                        self.assertIn("AssertionError", proc.stderr)
                        self.assertNotIn("ERROR:", proc.stderr)
                        print(f"PASS: {test} rejected {file} mutant", flush=True)
                    finally:
                        path.write_text(source)


if __name__ == "__main__":
    unittest.main()
