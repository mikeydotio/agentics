"""Prove independent oracles detect removed production delivery invariants."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MutationTests(unittest.TestCase):
    """Only mutate disposable copies, and require the unchanged baseline first."""

    def run_suite(self, directory, *cases):
        """Exercise the production copy through the ordinary behavior tests."""
        return subprocess.run([sys.executable, "-B", "-W", "error", str(ROOT / "tests/test_delivery.py"),
                               *cases], env=dict(os.environ, DELIVERY_TEST_BIN=str(directory)),
                              capture_output=True, text=True, timeout=30)

    def test_negative_controls(self):
        """Missing deadlines, correlation or durable pending evidence must fail."""
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="delivery-mutations-") as directory:
            target = Path(directory) / "bin"
            shutil.copytree(ROOT / "bin", target)
            baseline = self.run_suite(target)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            mutations = [
                ("delivery_model.py", "elif now >= t[\"deadline\"]:", "elif False:",
                 "DeliveryTests.test_silent_worker_retries_once_then_fails"),
                ("delivery_model.py", "if any(result.get(k) != v for k, v in identities.items()):", "if False:",
                 "DeliveryTests.test_identity_rejection_duplicates_and_late_results"),
                ("delivery_store.py", 'atomic_write(root / "STATE.json", json.dumps(s, indent=2, allow_nan=False) + "\\n")',
                 'pass  # deliberately lost pending persistence',
                 "DeliveryTests.test_successful_baseline_each_owner_and_host"),
            ]
            for filename, before, after, case in mutations:
                with self.subTest(invariant=before):
                    path = target / filename
                    source = path.read_text()
                    self.assertEqual(source.count(before), 1)
                    path.write_text(source.replace(before, after))
                    result = self.run_suite(target, case)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    path.write_text(source)


if __name__ == "__main__":
    unittest.main()
