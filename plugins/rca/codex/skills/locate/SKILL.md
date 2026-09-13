---
name: locate
description: RCA step 3 (FULL tier) — deterministic git forensics. Bisect the regression in a disposable worktree, run blame/pickaxe/SZZ-lite and hotspot analysis, and have the investigator synthesize a facts-only ORIGIN.md.
---

# RCA Locate — Origin Forensics

## Resolve runtime first

Walk four directories upward from this file path (three above its containing directory)
to resolve `<plugin-root>`. Read `<plugin-root>/codex/references/runtime.md` completely
before this step. It defines native questions, authorization, agent dispatch, reference
selection, and verification of write boundaries. Substitute absolute paths; do not rely
on environment variables being expanded by the host.


You are running origin location (FULL tier only — LIGHT does slim inline forensics inside
`diagnose`). Read `<plugin-root>/codex/references/git-forensics.md` and
`<plugin-root>/codex/references/worktree-protocol.md` first.

**Gate check**: `.rca/<slug>/REPRO.md` or `OVERRIDE.md` must exist. Missing → stop and route
back to `reproduce`. Inputs: GRID.md (classification + known_good + aligned changes),
REPRO.md (repro command + test paths), meta.json. Output: `forensics/*.json`, `ORIGIN.md`,
`worktree.json` if a worktree was created.

This step mutates nothing in the main tree: forensics scripts are read-only; bisect runs only
inside the slug worktree.

## 1. Choose the lead (per git-forensics.md's table)

Regression + usable `known_good` + deterministic repro → bisect. Otherwise → timeline +
pickaxe around the WHEN boundary; longstanding → blame/intro + hotspots.

## 2. Bisect (when applicable)

Estimate first: steps ≈ log2(commits between good and bad — `git rev-list --count`), times the
per-step build+test cost. On slow stacks (xcodebuild especially) present the estimate and ONE
native question: run bisect / pickaxe-first / skip. Then:

```bash
bash "<plugin-root>/bin/rca-worktree.sh" create <slug> --copy <repro-test-path> \
  [--copy <fixture-path>] [--setup-cmd "<stack setup_cmd>"]
bash "<plugin-root>/bin/rca-bisect.sh" run <slug> --good <known_good> --bad HEAD \
  --test-cmd "<single-test cmd>"
```

The repro test is untracked — it MUST travel via `--copy`. Handle: `good_is_bad` → the
known-good claim is wrong, revisit GRID.md WHEN with the user; `setup_failed` / no setup_cmd
available → degrade per worktree-protocol.md (skip bisect, record the gap). Save the output
as `forensics/bisect.json`. Remember: the culprit is where the failure became *observable* —
possibly an exposer of a deeper defect, not the defect itself.

## 3. Static forensics (always)

Run what the grid implicates, saving each JSON under `forensics/`:

```bash
bash "<plugin-root>/bin/rca-forensics.sh" blame --file <f> --lines <a>,<b>
bash "<plugin-root>/bin/rca-forensics.sh" intro --file <f> --lines <a>,<b>
bash "<plugin-root>/bin/rca-forensics.sh" pickaxe --term <symbol> --since <boundary>
bash "<plugin-root>/bin/rca-forensics.sh" timeline --paths <implicated> --since <boundary>
bash "<plugin-root>/bin/rca-hotspots.sh" --paths <implicated dirs>
```

## 4. Synthesis (investigator)

Spawn the shared **investigator** (use native `spawn_agent` for investigator per runtime.md — read-only,
verified per runtime.md; prompt = `<plugin-root>/agent-overrides/investigator-context.md` +
dynamic context: GRID.md, REPRO.md, every `forensics/*.json`, the bisect culprit's diff). Its
brief: ground in the deterministic record first, walk the implicated code, and return a
FACTS-ONLY origin report — timelines, attributions, structural observations, discrepancies
between script output and code reading. No causation claims.

The investigator is read-only: it returns the report; YOU write `ORIGIN.md` from it (format
per git-forensics.md — every entry cites a SHA).

## 5. Exit

Destroy the worktree only if no mutation experiments are expected imminently (default: keep —
`diagnose` usually needs it; it is recorded in `worktree.json` and surfaced by rca-status as
live). Summarize: culprit or candidates, hotspot/repeat-offender flags, the one or two
sharpest facts. Next: `diagnose` (`$rca continue <slug>` if standalone). State is durable; safe to start a fresh session.
