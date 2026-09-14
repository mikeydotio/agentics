# Integrity Result Contract

This is the single result contract for each required Forge integrity snapshot and check.
Claude and Codex use the same classifications and actions. This is an instruction contract:
its tests prove the shipped instructions and ordering, but this does not prove autonomous model compliance.

## Capture and classify

Capture the exact command, exit status, stdout, and stderr for every operation. Do not infer
success from `display`, a missing error message, or a field's truthiness. Stdout is a result only
when the exit status is zero and stdout contains exactly one JSON object with no mixed output.

A **verified snapshot** satisfies every condition below:

- The exit status is zero.
- Stdout contains exactly one JSON object.
- `.ok` is the JSON boolean `true`.
- `.phase` and `.scope` are strings equal to the requested values.
- `.head` is a nonempty string.
- `.file_count` is a nonnegative integer and is not a boolean.

A check first needs the same zero-exit, single-object, and JSON boolean `true` requirements.
A **verified clean check** also satisfies every condition below:

- `.tampered` is the JSON boolean `false`.
- `.action` is the string `"none"`.
- `.changed` is an empty array.
- `.head_moved` is the JSON boolean `false`.
- `.head_before` and `.head_after` are nonempty equal strings.

A successful tamper result has `.tampered` as the JSON boolean `true`, a `changed` array,
and a recognized, internally consistent action:

- `action: restored` — `head_moved` is false, HEAD values are equal, and changed files exist.
- `action: manual_review_required` — `head_moved` is true and the nonempty HEAD values differ.
- `action: restore_failed` — `head_moved` is false, HEAD values are equal, and changed files exist.

Everything else is **unverified**. This includes a nonzero exit, empty stdout, malformed JSON,
mixed output, `ok: false`, and a lost, unreadable, or corrupt snapshot. It also includes any
required field that is missing, null, or has the wrong type, plus an unknown or contradictory result shape.
Do not interpret `tampered: false` unless every verified-clean condition holds.

## Required actions

An integrity failure uses a **non-committing integrity stop**. Write the incomplete handoff in the preserved
worktree and release only the owned Forge lock when possible. Do not invoke `forge-step-exit.sh`, stage files,
create a commit, or queue Freshen. Stop the step with the worktree intact for explicit reconciliation.

**Pre-worker unverified:** preserve the command, exit status, stdout, stderr, phase, scope, and session ID.
Write an incomplete handoff that identifies the checkpoint and failed predicate. Prevent worker dispatch,
then use the non-committing integrity stop. The story can stay in its current state because no worker ran.
An optional capability preflight can report an unsupported environment before execution, but a required
execution-loop snapshot is never a benign skip.

**Post-worker unverified:** discard the worker response. Prevent pre-checks, verdict use, retry, commit,
and progression. Add a StoryHook comment with the checkpoint and captured diagnostics, then run
`story move HP-N blocked` with an integrity-reconciliation reason. Write an incomplete handoff and pause.
Use the non-committing integrity stop. Once a generator or evaluator ran, an environmental error cannot
turn verification into a skip.

For a successful tamper result, preserve the existing branches:

- **Generator, `action: restored`:** restoration does not validate the worker response. Mark the story
  blocked, comment that the generator modified Forge state, discard its response, and continue to the next story.
- **Evaluator, `action: restored`:** restoration does not validate the worker response. Discard the verdict.
  Re-run the evaluator once only after another verified snapshot. If it tampers again, block the story.
- **Either worker, `action: manual_review_required`:** do not reset HEAD. Block the story, preserve both SHAs,
  write an incomplete handoff, and use the non-committing integrity stop for manual reconciliation.
- **Either worker, `action: restore_failed`:** block the story, preserve the failed restoration diagnostics,
  write an incomplete handoff, and use the non-committing integrity stop for manual reconciliation.

Only a verified clean check can authorize the next downstream step.

## Interrupted verification and resume

If verification is interrupted or its baseline disappears after a worker ran, preserve the uncertain artifacts and diagnostics.
Never snapshot the post-worker state as a replacement baseline. On resume, explicitly reconcile every uncertain artifact
against trustworthy pre-worker evidence. If ownership or integrity remains uncertain, keep the story blocked and pause.
Start a fresh worker attempt only after reconciliation, then take a new verified snapshot before dispatch.
