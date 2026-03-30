# Canary Mode

Supervised first-N-stories protocol for validating evaluator calibration before full autonomy.

## Purpose

The first stories processed by pilot are supervised by the user. This validates:
1. **Evaluator calibration** — Is the evaluator too lenient or too strict?
2. **Story sizing** — Are stories the right size for single-agent implementation?
3. **Acceptance criteria quality** — Are criteria specific enough for machine evaluation?
4. **Generator effectiveness** — Is the generator producing useful output?

## Configuration

`canary_stories` in `.pilot/config.json` (default: 3).

Set to 0 to skip canary mode entirely (not recommended for first use).

## Protocol

After the evaluator returns a verdict (pass or fail), if `canary_remaining > 0`:

### 1. Present Verdict to User

Use AskUserQuestion to show the evaluator's assessment:

**header**: "Canary Review: [story title]"
**question**: Present the evaluator verdict summary, then ask: "Do you agree with this assessment?"
**options**:
- "Approved — verdict is correct"
- "Override — I disagree with this verdict"
- "Pause — I need to review the code first"

### 2. Handle Response

- **Approved**: Accept the verdict as-is. Decrement `canary_remaining`.
- **Override**:
  - If evaluator said pass but user says fail → mark story as `todo` for retry
  - If evaluator said fail but user says pass → commit the code, mark story as `done`
  - Note the override in handoff.md for calibration reference
- **Pause**: Write handoff, set status to `paused`. User reviews and manually resumes.

### 3. Transition to Full Autonomy

When `canary_remaining` reaches 0:
- Log: "Canary mode complete — transitioning to full autonomy"
- Subsequent stories proceed without user approval gates

## Re-Calibration Prompts

After canary mode, every 10 stories (`stories_attempted % 10 == 0`), log a note in handoff.md:

"10 stories since last calibration check — review recent verdicts in `.pilot/verdicts.jsonl`"

This reminds the user to periodically check evaluator quality even after canary mode ends.
