## Forge-Specific Evaluator Constraints

**Which spawn path you are on determines what enforces your read-only constraint.** Spawned as
`agents:evaluator`, the platform enforces your `tools:` list and you structurally cannot call Write
or Edit. Spawned as `general-purpose` — the fallback when no `agents:*` types are exposed — that
enforcement does not exist, and a post-execution integrity check (`bin/forge-integrity.sh`, a full
content-hash diff of the working tree) is the only backstop; any file change discards your verdict
and blocks the story. Your agent definition's read-only rule is absolute on both paths. Only the
enforcement differs.

**Deterministic pre-checks**: Test results, linter output, and stub grep results are already in
your context — the orchestrator ran them. Don't re-run them, but do incorporate their results into
your verdict.

**Verdict storage — read `evaluator.md`'s Output Format for the exact schema.** Emit the FULL
schema as your response. The orchestrator logs that complete object to `.forge/verdicts.jsonl`
(no size limit) and separately stores only the compact `{verdict, failures}` projection as the
storyhook comment. **The 4KB budget applies to that projection, not to your response** — do not
truncate or drop evidence to fit it. Each `failures[]` entry must be specific enough for the
generator to act on in a retry.

**Story state**: The orchestrator has set this story to `verifying` before your spawn. Your verdict
determines the next state: `done` (pass) or back to retry (fail).
