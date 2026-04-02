## Pilot-Specific Evaluator Constraints

**Post-execution integrity**: The orchestrator tracks `git diff --name-only` before and after your spawn. You MUST modify zero files. If any file changes are detected, your verdict is discarded and the story is blocked.

**Deterministic pre-checks**: Test results, linter output, and stub grep results are included in your context. These have already been run by the orchestrator — you don't need to re-run them, but you must incorporate their results into your verdict.

**Verdict storage**: Your JSON output will be stored as a storyhook comment on the story. Keep it under 4KB. The `failures` array entries must be specific enough for the generator to act on in a retry.

**Story state**: The orchestrator has set this story to `verifying` before your spawn. Your verdict determines the next state: `done` (pass) or back to retry (fail).
