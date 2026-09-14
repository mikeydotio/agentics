"""Exact both-host integrity instructions, not autonomous model-compliance proof."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "references/integrity-results.md"
HOSTS = {
    "claude": {
        "loop": ROOT / "references/execution-loop.md",
        "skill": ROOT / "claude/skills/execute/SKILL.md",
        "reference": "${CLAUDE_PLUGIN_ROOT}/references/integrity-results.md",
        "generator": "**Spawn generator agent**",
        "evaluator": "**Spawn\nevaluator agent**",
    },
    "codex": {
        "loop": ROOT / "codex/references/execution-loop.md",
        "skill": ROOT / "codex/skills/execute/SKILL.md",
        "reference": "<plugin-root>/references/integrity-results.md",
        "generator": "Spawn a separate generator:",
        "evaluator": "Spawn an independent evaluator",
    },
}


def _ordered(body: str, *tokens: str) -> bool:
    """Return whether each token occurs after its predecessor."""
    position = -1
    for token in tokens:
        position = body.find(token, position + 1)
        if position < 0:
            return False
    return True


def _prose(body: str) -> str:
    """Collapse insignificant Markdown whitespace for phrase checks."""
    return " ".join(body.split())


class IntegrityInstructionContracts(unittest.TestCase):
    """Pin the fail-closed contract at every instructional consumer boundary."""

    def test_shared_contract_is_total_and_states_coverage_limit(self):
        """The shared reference classifies every required producer result."""
        body = _prose(CONTRACT.read_text())
        for token in (
            "instruction contract",
            "does not prove autonomous model compliance",
            "exit status is zero",
            "exactly one JSON object",
            "JSON boolean `true`",
            "JSON boolean `false`",
            "nonnegative integer",
            "nonzero exit",
            "empty stdout",
            "malformed JSON",
            "mixed output",
            "missing, null, or has the wrong type",
            "`ok: false`",
            "lost, unreadable, or corrupt snapshot",
            "unknown or contradictory result shape",
            "command, exit status, stdout, stderr, phase, scope, and session ID",
            "optional capability preflight",
            "required execution-loop snapshot is never a benign skip",
        ):
            with self.subTest(token=token):
                self.assertIn(token, body)

    def test_both_hosts_load_the_only_result_contract(self):
        """Claude and Codex must load the same shared reference."""
        for host, paths in HOSTS.items():
            with self.subTest(host=host):
                loop = paths["loop"].read_text()
                skill = paths["skill"].read_text()
                self.assertIn(paths["reference"], loop)
                self.assertEqual(loop.count("shared integrity result contract"), 4)
                self.assertNotIn("`tampered: true`", loop)
                self.assertIn("verified snapshot", skill)
                self.assertIn("verified clean check", skill)

    def test_valid_snapshots_gate_both_worker_dispatches(self):
        """No host can dispatch either worker from an unverified baseline."""
        for host, paths in HOSTS.items():
            loop = paths["loop"].read_text()
            with self.subTest(host=host, checkpoint="pre-gen"):
                self.assertTrue(_ordered(
                    loop,
                    "snapshot --phase pre-gen",
                    "Spawn no generator unless this result is a verified snapshot.",
                    paths["generator"],
                ))
            with self.subTest(host=host, checkpoint="pre-eval"):
                self.assertTrue(_ordered(
                    loop,
                    "snapshot --phase pre-eval",
                    "Spawn no evaluator unless this result is a verified snapshot.",
                    paths["evaluator"],
                ))

    def test_valid_clean_checks_gate_progress_and_verdict_use(self):
        """Only explicit clean evidence can reach checks or evaluator parsing."""
        for host, paths in HOSTS.items():
            loop = paths["loop"].read_text()
            with self.subTest(host=host, checkpoint="post-generator"):
                self.assertTrue(_ordered(
                    loop,
                    "check --phase pre-gen",
                    "Only a verified clean check may proceed to Step 4.",
                    "### Step 4: Deterministic Pre-Checks",
                ))
            with self.subTest(host=host, checkpoint="post-evaluator"):
                self.assertTrue(_ordered(
                    loop,
                    "check --phase pre-eval",
                    "Only a verified clean check may reach **Parse evaluator response**.",
                    "**Parse evaluator response**",
                ))
                self.assertNotIn("Skip it when the\nspawn resolved", loop)

    def test_unverified_and_tampered_results_have_terminal_actions(self):
        """The shared contract preserves evidence and every established branch."""
        body = _prose(CONTRACT.read_text())
        for token in (
            "Pre-worker unverified",
            "Post-worker unverified",
            "Prevent worker dispatch",
            "discard the worker response",
            "Prevent pre-checks, verdict use, retry, commit, and progression",
            "story move HP-N blocked",
            "write an incomplete handoff",
            "non-committing integrity stop",
            "Do not invoke `forge-step-exit.sh`",
            "queue Freshen",
            "`action: restored`",
            "`action: manual_review_required`",
            "`action: restore_failed`",
            "restoration does not validate the worker response",
        ):
            with self.subTest(token=token):
                self.assertIn(token, body)

    def test_resume_requires_reconciliation_before_a_new_baseline(self):
        """Interrupted verification cannot certify the uncertain worker state."""
        body = CONTRACT.read_text()
        self.assertTrue(_ordered(
            body,
            "preserve the uncertain artifacts and diagnostics",
            "explicitly reconcile",
            "Start a fresh worker attempt",
            "new verified snapshot",
        ))
        self.assertIn("Never snapshot the post-worker state as a replacement baseline.", body)


if __name__ == "__main__":
    unittest.main()
