---
name: rca
description: Use when a KNOWN bug, regression, or defect needs its true root cause found and fixed well — not for discovering whether bugs exist. Reproduction-gated scientific-debugging pipeline: Kepner-Tregoe intake, deterministic git forensics (bisect/blame/pickaxe/hotspots), competing-hypothesis falsification in disposable worktrees, ODC classification, surgical-vs-redesign verdicts, gated two-hats fixes, committed blameless postmortems. Resumable; latches to GitHub/storyhook issues.
---

<!-- AGE-104 DELIVERY BEGIN -->
Read `<plugin-root>/references/delivery.md` completely before this step, including standalone entry.
Use the local delivery helper for every specialist dispatch, wait, retry and cleanup.
Persist the full roster and dispatch intent before native calls; retain returned IDs
and require the state-derived delivery envelope. On delivery_recovery, reconcile existing
batches before the artifact ladder, fresh dispatch or worktree/artifact cleanup. Failed
workers produce an incomplete HANDOFF.md and leave this step's gate unsatisfied.
Never retry a writer automatically or replace an independent challenge with self-review.
In Plan mode remain read-only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# RCA: Root Cause Analysis Orchestrator

## Resolve runtime first

Walk four directories upward from this file path (three above its containing directory)
to resolve `<plugin-root>`. Read `<plugin-root>/codex/references/runtime.md` completely
before this step. It defines native questions, authorization, agent dispatch, reference
selection, and verification of write boundaries. Substitute absolute paths; do not rely
on environment variables being expanded by the host.


You are a thin state-machine router. Each pipeline step is a separate skill under
`<plugin-root>/skills/<step>/SKILL.md` that reads its inputs from `.rca/<slug>/`,
writes its outputs, and exits. You detect state, Read the right step skill, and follow it
inline. Deterministic mechanics live in `<plugin-root>/bin/` scripts — never
reimplement them ad hoc.

**Pipeline**: intake → reproduce (FIRM GATE) → locate (FULL tier) → diagnose → report
(caller gate: fix now / hand off) → fix → postmortem.

## Hard Rules (bind every step)

1. **Firm repro gate.** No hypothesis, forensics-conclusion, or fix work before
   `.rca/<slug>/REPRO.md` (automated failing test) or `OVERRIDE.md` (user- or council-granted
   only) exists.
2. **No production-code modification until `APPROVAL.md` records `fix`.** Investigation
   writes only `.rca/` artifacts, NEW test files, and the scaffold's `.gitignore` append;
   mutating experiments and `git bisect` run only in the disposable worktree
   (`<plugin-root>/codex/references/worktree-protocol.md`). After every write-capable agent returns, run
   `git status --porcelain` on the main tree and fail loudly on anything outside that
   allowed set.
3. **One question per native question call.** Honor existing authorization per runtime.md.
4. **≥2 competing hypotheses**, each with a falsification experiment; challenger review
   before any verdict. Both tiers.
5. **Symptom-masking fixes are rejected** (`<plugin-root>/references/symptom-vs-root-cause.md`).
6. **Blameless.** "Human error" is never a root cause.
7. **Never bump or deploy.** No `/semver bump`, no `/deployit` — versioning and deployment
   are the user's, from main, later.
8. **Agent spawning**: follow `<plugin-root>/codex/references/runtime.md` for native
   dispatch, dependency fallback, prompt assembly, and pre/post-dispatch write checks.
   Record the selected path and actual enforcement limits in the step artifact.
   Read-only agents return reports; the dispatching step writes the artifacts.
9. **Artifacts are the state.** Everything important lands in `.rca/<slug>/` before a step
   exits; `start a fresh session` + `$rca continue` must always work.

## Plan-mode degradation

If the session is in plan mode (writes blocked): say so, and offer ONLY read-only static
forensics (`bin/rca-forensics.sh`, `bin/rca-hotspots.sh`, code reading) returned in-response
to feed the caller's plan. No scaffold, no repro test, no bisect, no artifacts — the full
pipeline starts after plan approval, in normal mode.

## Command Router

Parse the invocation. A bare description (no recognized subcommand) is a new investigation.
A leading `full` or `light` (or equivalent phrasing like "perform a full rca") is a tier
directive — strip it, pass `--tier` to intake's scaffold call, and the reproduce step will
skip tier confirmation.

| Invocation | Action |
|---|---|
| `$rca` (no args) | **Entry** below |
| `$rca <description>` | Dispatch `intake` with the description |
| `$rca full <desc>` / `$rca light <desc>` | Dispatch `intake` with tier directive |
| `$rca --issue <ref> [<desc>]` | Dispatch `intake` with the explicit issue ref |
| `$rca continue [<slug>]` | **Continue** below |
| `$rca status` | Run status script; show its `display`; stop |
| `$rca <step> [<slug>]` | Standalone step dispatch (steps: intake, reproduce, locate, diagnose, report, fix, postmortem) |
| `$rca abandon <slug>` | **Abandon** below |

## Entry (`$rca` with no args)

```bash
bash "<plugin-root>/bin/rca-status.sh"
```
- `count == 0` → ask for the bug description (one native question, options for common bug
  shapes: regression / wrong behavior / intermittent / performance), then dispatch `intake`.
- `count > 0` → one native question built from each investigation's ready-made `option`
  (label + description) plus "New investigation". Selecting an existing one → **Continue**
  with that slug; "New" → description question, then `intake`.

## Continue

```bash
bash "<plugin-root>/bin/rca-status.sh" --slug <slug>   # or bare when slug omitted
```
- No slug given: exactly one non-complete investigation → use it; several → ask which (ONE
  question, script-built options).
- Read the returned `state`/`dispatch` and act:

| state | Action |
|---|---|
| `intake_incomplete` | Read + follow `skills/intake/SKILL.md` (resume grid) |
| `needs_repro`, `needs_tier` | Read + follow `skills/reproduce/SKILL.md` |
| `needs_locate` | Read + follow `skills/locate/SKILL.md` |
| `needs_diagnosis` | Read + follow `skills/diagnose/SKILL.md` |
| `inconclusive` | Present INCONCLUSIVE.md; ONE question: new angle (→ diagnose with the new evidence) / review artifacts / abandon |
| `needs_report`, `awaiting_caller` | Read + follow `skills/report/SKILL.md` |
| `needs_fix` | Read + follow `skills/fix/SKILL.md` |
| `needs_postmortem` | Read + follow `skills/postmortem/SKILL.md` |
| `complete` | Summarize from POSTMORTEM.md/DIAGNOSIS.md; nothing to dispatch |
| `corrupt` | Show what's on disk; offer abandon or manual repair |

- `worktree_live: true` at ANY state → mention it; if the state doesn't need the worktree,
  offer cleanup (`bash "<plugin-root>/bin/rca-worktree.sh" destroy <slug>`).
- **Dispatch = Read the step's SKILL.md and follow it inline.** Never
  delegate a whole step to a subagent; only the orchestrator dispatches specialists. After the
  step exits, do NOT chain into the next step automatically within the same turn unless the
  step's exit says to — each step ends at a natural checkpoint; tell the user state is on
  disk and `$rca continue` (or `start a fresh session` first) proceeds.

## Abandon

Confirm with one native question (the investigation's summary in the question), then:
```bash
bash "<plugin-root>/bin/rca-worktree.sh" destroy <slug>
```
then disposition (same question): **Archive** (`tar czf rca-<slug>.tar.gz -C .rca <slug>` +
remove dir) / **Delete** (`rm -rf .rca/<slug>`) / **Keep** (leave artifacts; status will keep
listing it).

## Caller contract (for agents invoking rca)

An invoking agent supplies the description (and `--issue <ref>` when known) and answers the
report step's caller gate. rca never merges, pushes, bumps, or deploys on any path; hand-off
returns `HANDOFF.md` + issue comments as the durable interface.

## Dependencies

Required: `git`, `jq`. Optional: `gh` (GitHub latching), `story` (storyhook latching),
`$council-vote` (repro-gate override council). Missing optional deps degrade per
`<plugin-root>/codex/references/issue-latching.md` and `<plugin-root>/codex/references/repro-gate.md`.
