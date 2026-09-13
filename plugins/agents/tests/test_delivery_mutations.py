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

    def test_shell_runner_preserves_isolation_and_each_failure(self):
        """The real suite boundary propagates every failure without running later legs."""
        legs = ["test_delivery_mutations.py", "test_delivery.py", "sync-agent-delivery.py"]
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="delivery-runner-") as directory:
            root = Path(directory)
            interpreter = root / "python3"
            interpreter.write_text("""#!/bin/bash
set -euo pipefail
leg=""
for argument in "$@"; do
  case "$argument" in *.py) leg="${argument##*/}" ;; esac
done
printf '%s|%s|%s\\n' "$leg" "$STORYHOOK_INVOKER" "$STORYHOOK_DATA_DIR" >> "$DELIVERY_FIXTURE_LOG"
if [ "$leg" = "$DELIVERY_FAIL_LEG" ]; then exit 17; fi
""")
            interpreter.chmod(0o755)
            log = root / "calls"
            for failure in ("", *legs):
                with self.subTest(failure=failure or "baseline"):
                    log.write_text("")
                    env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                               DELIVERY_FIXTURE_LOG=str(log), DELIVERY_FAIL_LEG=failure)
                    result = subprocess.run(["bash", str(ROOT.parents[1] / "tests/with-isolated-store.sh"),
                                             "bash", str(ROOT / "tests/test-delivery.sh")], cwd=root,
                                            env=env, text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 17 if failure else 0, result.stdout + result.stderr)
                    calls = [line.split("|") for line in log.read_text().splitlines()]
                    expected = legs[:legs.index(failure) + 1] if failure else legs
                    self.assertEqual([call[0] for call in calls], expected)
                    stores = {call[2] for call in calls}
                    self.assertEqual(len(stores), 1)
                    for _, invoker, store in calls:
                        self.assertEqual(invoker, "local")
                        self.assertTrue(store.startswith("/private/tmp/agentics-store."), store)

    def test_packaging_requires_each_prerequisite(self):
        """An unavailable packaging runtime is an explicit failed check, never a pass."""
        tools = {"dirname": "/usr/bin/dirname", "codex": shutil.which("codex"),
                 "jq": shutil.which("jq"), "python3": sys.executable}
        for missing in ("codex", "jq", "python3"):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory(dir="/tmp") as directory:
                for name, executable in tools.items():
                    if name != missing:
                        self.assertIsNotNone(executable, name)
                        (Path(directory) / name).symlink_to(executable)
                result = subprocess.run(["/bin/bash", str(ROOT / "tests/smoke-codex-install.sh")],
                                        env=dict(os.environ, PATH=directory), text=True,
                                        capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"ERROR: {missing} is required", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
