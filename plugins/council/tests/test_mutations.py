"""Targeted mutations with successful baseline and explicit assertion-failure oracles."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MutationTests(unittest.TestCase):
    """Change only disposable copies; missing programs are never caught mutants."""

    def test_baseline_then_five_removed_safeguards(self):
        """Each mutant must apply and fail its specific behavior assertion."""
        cases = [
            ("council_model.py", 'or now < seat["deadline"]:', 'or True:',
             "test_two_silent_seats_retry_abstain_abort"),
            ("council_model.py", 'seat["retry_count"] == 0 and now < s["hard_deadline"]',
             'seat["retry_count"] <= 1 and now < s["hard_deadline"]',
             "test_malformed_then_silent_uses_one_retry"),
            ("council_model.py", 'message.get(key) != value or type(message.get(key)) is not type(value)',
             'False', "test_identity_and_duplicate_messages_never_change_tally"),
            ("council_model.py", 'if sum(seat["status"] == "abstained" for seat in seats) >= 2:',
             'if False:', "test_two_silent_seats_retry_abstain_abort"),
            ("council_store.py", 'atomic_write(root / "STATE.json", json.dumps(state, indent=2, allow_nan=False) + "\\n")',
             'if state["status"] != "aborted":\n            atomic_write(root / "STATE.json", json.dumps(state, indent=2, allow_nan=False) + "\\n")',
             "test_persistence_crash_after_terminal_state_is_recoverable"),
        ]
        with tempfile.TemporaryDirectory(prefix="council-mutants-", dir="/tmp") as temp:
            copied = Path(temp) / "council"
            shutil.copytree(ROOT, copied)
            env = dict(os.environ, COUNCIL_TEST_ROOT=str(copied), PYTHONDONTWRITEBYTECODE="1")
            test_file = copied / "tests/test_liveness.py"
            baseline = subprocess.run([sys.executable, "-W", "error", str(test_file)], env=env,
                                      capture_output=True, text=True, timeout=30, check=False)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            self.assertRegex(baseline.stderr, r"Ran [1-9][0-9]+ tests")
            print("PASS: mutation baseline exercised the production-policy suite")
            for file, original, changed, test in cases:
                with self.subTest(safeguard=test, file=file):
                    path = copied / "bin" / file
                    source = path.read_text()
                    self.assertEqual(source.count(original), 1, "mutation anchor must be unique")
                    path.write_text(source.replace(original, changed, 1))
                    try:
                        self.assertIn(changed, path.read_text())
                        run = subprocess.run([sys.executable, "-W", "error", str(test_file),
                                              f"CouncilTests.{test}"], env=env,
                                             capture_output=True, text=True, timeout=10, check=False)
                        self.assertNotEqual(run.returncode, 0, "mutant survived")
                        self.assertIn("FAIL: " + test, run.stderr)
                        self.assertIn("AssertionError", run.stderr)
                        self.assertNotIn("ERROR:", run.stderr)
                        print(f"PASS: applied mutant caught by {test}")
                    finally:
                        path.write_text(source)


if __name__ == "__main__":
    unittest.main()
