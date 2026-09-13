# Git Forensics

Deterministic origin-location. Run the scripts, then hand their JSON to the investigator —
the model interprets; the scripts establish facts. All commands are read-only against the main
tree except bisect, which runs only inside the disposable worktree.

## Choosing the lead technique

| Grid signal | Lead with |
|---|---|
| Regression + known-good ref + repro test | **bisect** (binary search names the culprit commit) |
| Regression, no usable known-good | **timeline** + **pickaxe** around the WHEN boundary |
| Longstanding defect | **blame/intro** on implicated lines + **hotspots** for context |
| Symbol/constant suspected | **pickaxe** on the term |

## Bisect

```bash
bash "<plugin-root>/bin/rca-worktree.sh" create <slug> --copy <repro-test-path> --setup-cmd "<deps cmd if needed>"
bash "<plugin-root>/bin/rca-bisect.sh" run <slug> --good <ref> --bad HEAD --test-cmd "<single-test cmd>"
```

- The repro test is usually UNTRACKED in the main tree — linked worktrees do not share
  untracked files, so it must travel via `--copy`. Untracked files survive bisect's checkouts.
- Exit-code contract inside the driver: test fail → bad; pass → good; build/setup failure →
  125 (skip, commit untestable). The script traps `git bisect reset` on every exit.
- **Cost estimate first, always**: steps ≈ log2(commits in range). Multiply by the per-step
  build+test time. On slow stacks (xcodebuild especially) present the estimate and offer
  pickaxe-first as the cheaper alternative; use the narrowest single-test command available
  (`swift test --filter`, `-only-testing:`, `cargo test <name>`, `pytest path::test`).
- `good_is_bad` (test already fails at the "good" ref) means the known-good claim is wrong —
  go back to the grid's WHEN row, don't widen blindly.
- The culprit commit is where the *failure* became observable — not automatically where the
  *defect* lives. A culprit that merely exposed a latent defect (enabled a path, changed
  timing, added a caller) is itself a finding: the infection chain runs through it, deeper.

## Blame / intro (SZZ-lite)

```bash
bash "<plugin-root>/bin/rca-forensics.sh" blame --file <f> --lines <a>,<b>
bash "<plugin-root>/bin/rca-forensics.sh" intro --file <f> --lines <a>,<b>
```
`blame` attributes the current lines; `intro` lists introducing-commit candidates (newest
first). SZZ false-positive modes to keep in mind: cosmetic/format-only commits, moved code
(blame follows the move, not the origin), and bulk refactors — check each candidate's diff
before treating it as the introduction point.

## Pickaxe

```bash
bash "<plugin-root>/bin/rca-forensics.sh" pickaxe --term <symbol-or-string> --since <date>
```
`-S` (default) finds commits that changed the *count* of the term — additions/removals, the
usual want. `--regex` switches to `-G`: any diff line matching, including moves — noisier,
catches renames/rewrites `-S` misses. Start with the default; escalate to `--regex` when the
term may have moved rather than appeared.

## Timeline & hotspots

```bash
bash "<plugin-root>/bin/rca-forensics.sh" timeline --paths <implicated paths> --since <boundary>
bash "<plugin-root>/bin/rca-hotspots.sh" --paths <implicated dirs> --since 12.months
```
Timeline = ordered change history for the implicated area (feed the WHEN-aligned changes from
the grid). Hotspots = churn × size ranking plus co-change couplings. Interpretation:
- A defect in a **top-hotspot file** or a **repeat-offender** (multiple prior fix commits) is
  evidence for a design-level verdict later — record the rank in ORIGIN.md.
- **Co-change couplings** (files that change together with high confidence but no import
  relationship) expose implicit coupling — candidate infection paths that static reading
  misses.
- Hotspot analysis is heuristic ("not strict science" — Tornhill). It prioritizes attention;
  it never convicts on its own.

## ORIGIN.md

Facts only, no causation claims: bisect culprit (sha, subject, diff summary) or "not run:
<reason>"; blame/intro candidates with dates; pickaxe findings; timeline of aligned changes;
hotspot rank + repeat-offender flag + notable couplings for the implicated files. Every entry
cites a SHA. Hypotheses come later — an ORIGIN.md that editorializes contaminates diagnosis.
