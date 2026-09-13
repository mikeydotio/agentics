## Forge evaluator constraints

Your read-only rule is absolute. Native Codex permissions are inherited; role metadata
does not structurally remove write tools. Return your verdict without editing files.
The orchestrator always verifies the full-tree integrity baseline before using it.

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
