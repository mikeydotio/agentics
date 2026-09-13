# The Reproduction Gate

**No hypothesis work, no forensics-driven conclusions, no fix until the failure can be
triggered on demand by an automated test.** A reproduction is the oracle every downstream step
needs: bisect needs it, falsification experiments need it, the fix's RED→GREEN proof needs it,
and the regression test that outlives the investigation IS it. Fixing without reproducing is
the cardinal RCA violation — you cannot prove the diagnosis or the fix.

The gate is satisfied by exactly one of:
- `REPRO.md` + `repro/repro.json` showing a failing automated test, or
- `OVERRIDE.md` — granted ONLY by the user or a council vote (below). Nothing else opens the
  gate. Downstream artifacts must carry the degraded-confidence note verbatim.

## Building the repro (qa-engineer brief)

Spawn `qa-engineer` via runtime.md in Reproduction Mode with: GRID.md, the stack's test command info,
and the constraint that it may create NEW test files only — never modify production code or
existing tests. Its target: one minimal automated test that fails BECAUSE of the reported
defect and will pass when the defect is fixed.

**Fails-for-the-right-reason check** (the skill verifies, not just the agent): the test's
failure output must show the diagnostic signal from GRID.md WHAT-IS — the specific wrong
value, error type, or state. A test that fails from setup problems, missing fixtures, or an
unrelated assertion is a false repro. Run it, read the failure tail, confirm the signal.

Verify with:
```bash
bash "<plugin-root>/bin/rca-repro.sh" run --cmd "<single-test command>" --runs 1
```
`failure_rate` must be 1.0 for a deterministic repro. Record the exact command in
`repro/test-cmd.json` via `rca-scaffold.sh set <slug> --key value` entries.

## Flaky-failure ladder

When the failure is intermittent, quantify before judging:
```bash
bash "<plugin-root>/bin/rca-repro.sh" run --cmd "<cmd>" --runs 20
```
- **failure_rate ≥ 0.9** — treat as reproduced; note the rate in REPRO.md.
- **0.1 ≤ rate < 0.9** — do NOT proceed yet. Hunt determinism handles with qa-engineer: seed
  control, clock/time injection, execution-order control, network/IO fakes, repetition
  wrappers (run-until-fail loops bounded at N). Re-quantify after each handle. A repetition
  wrapper that reaches ≥0.9 within a bounded loop is an acceptable gate-passer (record the
  wrapper as the repro command).
- **rate < 0.1** — reproduction is not yet reliable enough to be an oracle. Either keep
  hunting handles or move to the override discussion. Never treat "passed 20 times after the
  fix" as proof for a <0.1 bug; compute the runs needed for confidence and say so.

Remember: "N consecutive passes" is a statistical statement, not proof. For a bug with true
failure rate p, the chance N passes are coincidence is (1-p)^N — quote this when relevant.

## Override protocol

Present the strongest honest rationale for why the gate cannot be met (each repro attempt and
why it failed, the determinism handles tried). Then EITHER the user explicitly overrides, OR
convene `$council-vote`:

- Question: "Should this RCA proceed without an automated failing repro test for <slug>?"
- Context: grid summary, every attempt + failure reason, stack constraints.
- Panel requirement (pass to the council chair): one seat MUST be qa-engineer, tasked with
  proposing out-of-the-box automation (CLI harness around the app layer, golden-file
  comparison, log-scrape assertion, headless UI driver, record/replay, clock/locale/network
  simulation) before conceding the gate.
- If rca is itself running as a subagent, the council cannot convene (its own hard rule) —
  then only the user can override.

`OVERRIDE.md` records: who/what granted it, rationale, council decision path
(`.council/<slug>/DECISION.md`) if applicable, and the forensic-evidence plan replacing the
oracle (timeline reconstruction from logs, crash dumps, targeted logging awaiting recurrence).

## Minimization (FULL tier)

Reduce the repro until 1-minimal (ddmin spirit): remove half the inputs/steps; if it still
fails, recurse on the remainder; if not, restore and halve the other side; increase
granularity when stuck. Record the minimal case in `MINIMAL.md` — a minimal repro frequently
reveals the cause outright, and it makes every later experiment cheaper.

## Tier triage

After the gate, recommend a tier from measured signals — regression with known-good ref
(bisect will likely name the culprit → FULL pays off), flaky/concurrency signature (FULL),
multi-component path or hotspot file (FULL), sharp single-file distinction with an obvious
candidate (LIGHT). One native question to confirm — skipped entirely when the user invoked
with an explicit `full`/`light` directive (meta.json `tier_directive`).
