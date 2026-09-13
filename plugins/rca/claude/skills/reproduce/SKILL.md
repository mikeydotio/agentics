---
name: reproduce
description: RCA step 2 — the firm reproduction gate. Detect the test stack, have qa-engineer build an automated failing repro test, quantify flakiness, minimize (FULL tier), and set the investigation tier. No hypothesis work happens until this gate is passed or explicitly overridden.
argument-hint: "[slug]"
effort: high
---

# RCA Reproduce — The Firm Gate

You are running the reproduction gate. Read `${CLAUDE_PLUGIN_ROOT}/references/repro-gate.md`
first. Inputs: `.rca/<slug>/GRID.md` + `meta.json` (resolve the slug from the argument, or via
`bash ${CLAUDE_PLUGIN_ROOT}/bin/rca-status.sh` when exactly one investigation is at
`needs_repro`; otherwise ask). Outputs: `repro/test-cmd.json`, `repro/repro.json`, `REPRO.md`
(or `OVERRIDE.md`), `MINIMAL.md` (FULL), tier set in `meta.json`.

**The gate**: this step exits successfully ONLY with a failing automated repro recorded, or an
override granted by the user or a council vote. Nothing else. Downstream steps check for
`REPRO.md`/`OVERRIDE.md` and refuse to run without one.

Write allowances: `.rca/<slug>/**` and NEW test files only. Production code and existing tests
are untouchable — enforce on the qa-engineer's return (below).

## 1. Stack detection

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/rca-stack.sh detect
```
- One clear primary → confirm silently, record.
- Ambiguous (multi-stack, `needs:["scheme"]`, or `none`) → ONE AskUserQuestion (options from
  the detected stacks + "custom command").
- Record via `rca-scaffold.sh set <slug>` with `--stack.id`, `--stack.test_cmd`,
  `--stack.single_test_cmd`, `--stack.setup_cmd` and write `repro/test-cmd.json`.

## 2. Build the failing repro (qa-engineer)

Spawn the shared **qa-engineer** in Reproduction Mode (spawn per
`cross-plugin-usage.md`: prefer `subagent_type: "agents:qa-engineer"`; prompt = contents of
`${CLAUDE_PLUGIN_ROOT}/agent-overrides/qa-engineer-context.md` + dynamic context: GRID.md
contents, stack info, slug paths). Brief it to produce ONE minimal automated test that fails
BECAUSE of the defect, in a NEW test file, using the project's existing framework.

On return, verify — do not trust:
1. `git status --porcelain` in the main tree: nothing beyond `.rca/`, the declared new test
   file(s), and the scaffold's `.gitignore` change. Anything else → revert instruction +
   respawn with the violation named.
2. **Fails for the right reason**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/rca-repro.sh run --cmd "<single-test cmd>" --runs 1
   ```
   The failure tail must show the diagnostic signal from GRID.md WHAT-IS. Setup errors,
   missing fixtures, unrelated assertions → false repro → iterate with qa-engineer.

## 3. Flaky ladder (when run 1 passes or fails intermittently)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/rca-repro.sh run --cmd "<cmd>" --runs 20
```
Apply repro-gate.md's ladder: ≥0.9 → reproduced (record rate); 0.1–0.9 → determinism-handle
hunt with qa-engineer (seeds, clock injection, ordering, bounded repetition wrappers),
re-quantify; <0.1 → keep hunting or move to the override discussion. Record final
`repro/repro.json` (the script's output) and the exact command.

## 4. Override path (only when the gate genuinely cannot be met)

Present the honest rationale (every attempt + failure reason). Then ONE AskUserQuestion:
"Override the gate?" with options: user override / convene `/council-vote` / keep trying.
Council mechanics per repro-gate.md — the panel MUST seat qa-engineer briefed for
out-of-the-box repro automation; record the outcome and `.council/<slug>/` path in
`OVERRIDE.md` with the degraded-confidence note that every downstream artifact must carry.

## 5. Minimize (FULL tier, once the gate is passed)

Reduce the repro to 1-minimal (ddmin spirit, per repro-gate.md) with qa-engineer; write
`MINIMAL.md` (the minimal case + what was stripped + what that already reveals).

## 6. Tier

Recommend FULL or LIGHT from measured signals (regression with known_good → FULL pays;
flaky/concurrency signature → FULL; sharp single-file distinction → LIGHT). If
`tier_directive` is set in meta.json, apply it WITHOUT asking. Otherwise ONE AskUserQuestion
to confirm. Record: `rca-scaffold.sh set <slug> --tier <full|light>`.

## 7. Exit

Write `REPRO.md`: the repro command, failure rate, diagnostic-signal evidence (failure tail
excerpt), test file path(s), minimization pointer. Summarize for the user: gate status, tier,
what happens next (`locate` on FULL, `diagnose` on LIGHT — `/rca continue <slug>` if
standalone). State is fully on disk — safe to `/clear`.
