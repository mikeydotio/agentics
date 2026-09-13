"""RCA's production status ladder must not mistake partial artifacts for delivered work."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve()
ROOT = Path(os.environ.get("RCA_DELIVERY_TEST_ROOT", SOURCE.parents[1]))
sys.path.insert(0, str(ROOT / "bin"))
from delivery_store import execute


class RCADeliveryTests(unittest.TestCase):
    """Use complete-looking artifacts and genuine production delivery transitions."""

    def setUp(self):
        """Prepare a completed-looking investigation in an isolated directory."""
        self.temp = tempfile.TemporaryDirectory(dir="/tmp", prefix="rca-delivery-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / ".rca" / "fixture"
        self.root.mkdir(parents=True)
        (self.root / "meta.json").write_text('{"tier":"light","description":"fixture"}')
        for name in ("GRID", "REPRO", "DIAGNOSIS", "REPORT", "REMEDIATION", "POSTMORTEM"):
            (self.root / f"{name}.md").write_text(f"# {name}\n\nPartial evidence\n")
        (self.root / "APPROVAL.md").write_text("decision: handoff\n")
        self.batch = self.root / "deliveries" / "one"
        self.now = [time.time(), time.monotonic()]
        self.result = execute(self.batch, "init", dict(owner="rca", host="codex", session="parent",
                              step="postmortem", capacity=1, tasks=[dict(task_id="write", task="Write postmortem",
                              role="technical-writer", writer=True)]), lambda: tuple(self.now))

    def call(self, command, **fields):
        """Drive the persisted command boundary with the last returned revision."""
        self.result = execute(self.batch, command, dict(revision=self.result["state"]["revision"], **fields),
                              lambda: tuple(self.now))

    def status(self):
        """Run the actual status command, never a fixture replica of the ladder."""
        result = subprocess.run(["bash", str(ROOT / "bin/rca-status.sh"), "--rca-dir", str(self.root.parent)],
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)["investigations"][0]

    def test_pending_then_successful_baseline(self):
        """Pending delivery overrides completion until the actual writer result arrives."""
        self.assertEqual(self.status()["state"], "delivery_recovery")
        identity = dict(task_id="write", attempt_id=self.result["state"]["tasks"][0]["attempt_id"])
        self.call("record", **identity, kind="dispatch-attempted")
        self.call("record", **identity, kind="dispatched", agent_id="native-writer")
        task = self.result["state"]["tasks"][0]
        body = dict(identity, task_digest=task["task_digest"], batch_id=self.result["state"]["batch_id"],
                    kind="result", payload="Postmortem written with evidence")
        self.call("record", **identity, kind="delivery", sender="native-writer", body=json.dumps(body))
        self.call("record", **identity, kind="stopped", agent_id="native-writer", stopped=True, integrity_ok=True)
        self.call("finish", outcome="succeeded", integrity_ok=True)
        self.assertEqual(self.status()["state"], "complete")

    def test_failed_and_corrupt_state_never_satisfy_gates(self):
        """Terminal failure and corrupt state preserve the incomplete handoff route."""
        self.call("finish", outcome="failed", reason="permission unavailable")
        self.assertEqual(self.status()["dispatch"], "delivery_recovery")
        (self.batch / "STATE.json").write_text("{}")
        self.assertEqual(self.status()["dispatch"], "delivery_recovery")

    def test_all_host_entrypoints_require_delivery(self):
        """Standalone step entry cannot bypass the shared runtime guard."""
        for host in ("claude", "codex"):
            paths = list((ROOT / host / "skills").glob("*/SKILL.md"))
            self.assertEqual(len(paths), 8)
            for path in paths:
                with self.subTest(path=path):
                    body = path.read_text()
                    self.assertTrue("references/delivery.md" in body, str(path))
                    self.assertTrue("delivery_recovery" in body, str(path))


    def test_pipeline_guard_negative_controls(self):
        """Removing each real gate must fail its ordinary production-flow oracle."""
        condition = "if ! printf '%s' \"$delivery\" | jq -e '.ok == true and .blocked == false' >/dev/null; then"
        cases = [('rca-status.sh', 'test_pending_then_successful_baseline')]
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="rca-guard-mutations-") as directory:
            target = Path(directory)
            shutil.copytree(ROOT / "bin", target / "bin")
            for filename, case in cases:
                with self.subTest(script=filename):
                    path = target / "bin" / filename
                    source = path.read_text()
                    self.assertEqual(source.count(condition), 1)
                    args = [sys.executable, "-B", "-W", "error", str(SOURCE), "RCADeliveryTests." + case]
                    env = dict(os.environ, RCA_DELIVERY_TEST_ROOT=str(target))
                    baseline = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
                    self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
                    path.write_text(source.replace(condition, "if false; then"))
                    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("FAIL:", result.stderr, result.stdout + result.stderr)
                    path.write_text(source)


if __name__ == "__main__":
    unittest.main()
