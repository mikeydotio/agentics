# Execution Loop: Retry

The `goto retry` target of the loop in `<plugin-root>/codex/references/execution-loop.md`. AUTHORITATIVE for the
retry path exactly as `execution-loop.md` is for Prerequisites and Steps 0–7 — follow it
completely.

Loaded only when an attempt has actually failed: a deterministic pre-check returned
`passed: false` (Step 4), or the evaluator returned `verdict: "fail"` (Step 5a). A story that
passes first attempt never reaches it, so it is not part of the per-story entry cost.

### Retry

```bash
# After preserving evidence, discard only this failed generator's known changes.
  bash "<plugin-root>/bin/forge-loop-state.sh" retry --story-id HP-N --forge-dir .forge
```

Parse the result:
- `action: "retry"` →
  ```bash
  story move HP-N todo  # with evaluator/check feedback already in comments
  ```
  continue (back to top of loop)
- `action: "block"` →
  ```bash
  story move HP-N blocked
  story comment HP-N '{"blocked_reason":"max_retries","description":"Failed <max_retries> attempts","last_feedback":{...}}'
  ```
  continue (back to top of loop — will pick next story)

The script owns `retry_counts[story_id]`, `total_retries`, and the retry-vs-block comparison
against `config.max_retries` — no model-run counter arithmetic or JSON edits.
