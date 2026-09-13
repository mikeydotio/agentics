"""Run production RCA mechanics across host environments in one isolated repo."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SharedMechanics(unittest.TestCase):
    """The host changes instructions, never saved-state or shell behavior."""

    def test_cross_host_lifecycle(self):
        """Reproduce, bisect, resume, and clean up with both host environments."""
        for creator in ("claude", "codex"):
            with self.subTest(creator=creator), tempfile.TemporaryDirectory(
                    prefix="rca host flow ", dir="/private/tmp") as tmp:
                repo = Path(tmp)
                env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1",
                           GIT_AUTHOR_NAME="RCA test", GIT_AUTHOR_EMAIL="test@example.invalid",
                           GIT_COMMITTER_NAME="RCA test", GIT_COMMITTER_EMAIL="test@example.invalid")
                for name in list(env):
                    if name in ("PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT", "AGENTS_PLUGIN_ROOT") or name.startswith("GIT_DIR") or name in ("GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
                        env.pop(name)

                def git(*args):
                    return subprocess.run(["git", "-c", "commit.gpgsign=false", *args],
                                          cwd=repo, env=env, text=True, capture_output=True,
                                          check=True).stdout.strip()

                def call(script, *args, host=creator):
                    host_env = dict(env)
                    if host == "claude":
                        host_env["CLAUDE_PLUGIN_ROOT"] = str(ROOT)
                    elif host == "codex":
                        host_env["PLUGIN_ROOT"] = str(ROOT)
                    elif host == "conflicting":
                        host_env.update(PLUGIN_ROOT="/absent/codex", CLAUDE_PLUGIN_ROOT="/absent/claude")
                    result = subprocess.run(["bash", str(ROOT / f"bin/rca-{script}.sh"), *args],
                                            cwd=repo, env=host_env, text=True, capture_output=True,
                                            check=False, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    return json.loads(result.stdout)

                git("init", "-q", "-b", "main")
                check = repo / "check.sh"
                check.write_text("#!/bin/sh\nexit 0\n")
                git("add", "check.sh"); git("commit", "-qm", "good")
                good = git("rev-parse", "HEAD")
                check.write_text("#!/bin/sh\nexit 1\n")
                git("add", "check.sh"); git("commit", "-qm", "planted defect")
                bad = git("rev-parse", "HEAD")
                (repo / "later.txt").write_text("unrelated\n")
                git("add", "later.txt"); git("commit", "-qm", "later")

                self.assertTrue(call("scaffold", "init", "flow", "--description", "known failure", "--tier", "full")["ok"])
                state = repo / ".rca/flow"

                def assert_state(expected):
                    outputs = [call("status", "--slug", "flow", host=h) for h in
                               ("claude", "codex", "unset", "conflicting")]
                    self.assertTrue(all(output == outputs[0] for output in outputs))
                    self.assertEqual(outputs[0]["investigations"][0]["state"], expected)

                assert_state("intake_incomplete")
                (state / "GRID.md").write_text("Known failure after planted defect.\n")
                assert_state("needs_repro")
                repro = call("repro", "run", "--cmd", "bash check.sh", "--runs", "1")
                self.assertEqual(repro["failure_rate"], 1)
                (state / "REPRO.md").write_text(json.dumps(repro))
                call("scaffold", "set", "flow", "--tier", "full")
                assert_state("needs_locate")
                created = call("worktree", "create", "flow")
                self.assertTrue(Path(created["path"]).is_dir())
                result = call("bisect", "run", "flow", "--good", good, "--bad", "HEAD",
                              "--test-cmd", "bash check.sh")
                self.assertEqual(result["culprit_sha"], bad)
                (state / "ORIGIN.md").write_text(bad)
                assert_state("needs_diagnosis")
                call("worktree", "destroy", "flow", host="codex" if creator == "claude" else "claude")
                self.assertFalse(Path(created["path"]).exists())
                call("scaffold", "set", "flow", "--tier", "light")
                (state / "ORIGIN.md").unlink()
                assert_state("needs_diagnosis")
                (state / "DIAGNOSIS.md").write_text("Verified fixture cause\n")
                assert_state("needs_report")
                for name in ("REPORT.md", "REMEDIATION.md"):
                    (state / name).write_text("Fixture report\n")
                assert_state("awaiting_caller")
                (state / "APPROVAL.md").write_text("decision: handoff\n")
                assert_state("needs_postmortem")
                (state / "APPROVAL.md").write_text("decision: fix\n")
                assert_state("needs_fix")
                (state / "FIX.md").write_text("Fixture completion\n")
                assert_state("needs_postmortem")
                (state / "POSTMORTEM.md").write_text("Fixture lesson\n")
                assert_state("complete")
