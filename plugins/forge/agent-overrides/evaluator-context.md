## Forge-Specific Evaluator Constraints

**Tool restriction**: If you were spawned as `agents:evaluator`, the platform enforces
`evaluator.md`'s `tools: Read, Bash, Grep, Glob` — you structurally cannot call Write or Edit, full
stop. If you were spawned as `general-purpose` (fallback path — no `agents:*` types were exposed),
that enforcement doesn't apply at the platform level; the post-execution integrity check below is
the only backstop in that case, so treat the Guardrails section's "NO Write or Edit tools" as
absolute regardless of which path was used.

**Post-execution integrity (belt-and-suspenders, not the primary enforcement)**: The orchestrator
snapshots the working tree before your spawn and diffs it after. You MUST modify zero files. If
any change is detected, your verdict is discarded and the story is blocked. Known gap: the current
heuristic (`git diff --name-only`) cannot see an edit to a file the generator had already touched,
or a brand-new untracked file you create — `bin/forge-integrity.sh` (a full content-hash check)
closes that gap. Don't rely on the heuristic missing something as license to write; the tool
restriction above is the real boundary.

**Deterministic pre-checks**: Test results, linter output, and stub grep results are included in your context. These have already been run by the orchestrator — you don't need to re-run them, but you must incorporate their results into your verdict.

**Verdict storage — read `evaluator.md`'s Output Format for the exact schema and storage split.**
In short: emit the FULL schema (verdict, `failures[]`, `criteria_checks`, `edge_case_findings`,
`security_findings`, `design_adherence`, `summary`) as your response — the orchestrator logs that
complete object to `.forge/verdicts.jsonl` (no size limit there) and separately stores only the
compact `{verdict, failures}` projection as the storyhook comment. The 4KB budget applies to that
compact storyhook-comment projection, not to your full response — do not truncate your response or
drop evidence to fit under it. Each `failures[]` entry must be specific enough for the generator to
act on in a retry.

**Story state**: The orchestrator has set this story to `verifying` before your spawn. Your verdict determines the next state: `done` (pass) or back to retry (fail).
