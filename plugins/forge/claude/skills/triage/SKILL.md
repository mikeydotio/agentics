---
name: triage
description: Deliberate on review and validation findings. Label each as FIX or ESCALATE. Create ESCALATE stories via out-of-band decompose. Produces TRIAGE.md.
argument-hint: "[--yolo]"
effort: xhigh
---

<!-- AGE-104 DELIVERY BEGIN -->
Read `${CLAUDE_PLUGIN_ROOT}/references/delivery.md` completely before this step, including standalone entry.
The local helper owns all specialist dispatch/wait/retry/cleanup; persist intent before
native dispatch and use the state-derived result envelope. On delivery_recovery, inspect
and recover existing batches before any fresh dispatch, artifact-based advancement or
cleanup. Preserve partial changes and write an incomplete handoff on failure; never
convert delivery failure into an evaluator verdict or a fresh generator retry.
In Plan mode inspect only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# Triage: FIX or ESCALATE Deliberation

You are the triage skill. Your job is to deliberate on findings from the review and validation reports, deciding which should be automatically fixed (FIX) and which require user decision (ESCALATE).

**Read inputs:**
- `.forge/REVIEW-REPORT.md` (required)
- `.forge/VALIDATE-REPORT.md` (required)
- `.forge/IDEA.md` (for priority context)
- `.forge/DESIGN.md` (for impact assessment)
- `.forge/config.json` (for yolo mode, when_in_doubt, max_fix_cycles)
- `.forge/handoffs/handoff-review.md` (for context)
- `.forge/handoffs/handoff-validate.md` (for context)
- `references/team-roles.md` (before spawning — "Resolving subagent_type" governs every spawn
  below; `triager` has a forge override, `qa-engineer` and `skeptic` don't)

## Steps

### 1. Check Mode

Read `.forge/config.json`:
- If `yolo: true` → skip deliberation, assign FIX to all findings
- If `yolo: false` → proceed with deliberation

### 2. Spawn Triage Team

Resolve `subagent_type` per `references/team-roles.md` for each (`agents:<name>` preferred;
`general-purpose` + inlined shared definition — plus the override for `triager` — only as
fallback):

- `triager` — Primary deliberation agent. `read_only: true` — it does NOT write `.forge/TRIAGE.md`
  itself; it returns its decisions as its response (per its Output Format), and this step
  synthesizes the file from all three agents' returned output — see Step 6.
- `qa-engineer` — Risk assessment perspective
- `skeptic` — Challenge triage decisions

All agents receive both reports, IDEA.md, DESIGN.md, and config.json.

### 3. Deliberation

For each finding in both reports, the team votes:

**FIX** — auto-fix without user input:
- Single obvious correct solution
- Low risk of unintended consequences
- Doesn't change user-facing behavior surprisingly
- Doesn't require design decisions beyond DESIGN.md

**ESCALATE** — user must weigh in:
- Multiple valid solutions with different trade-offs
- Changes user-facing behavior or UX
- Requires design decisions not in DESIGN.md
- High risk if wrong choice is made
- Critical severity involving security or data integrity

When the team is split → use `when_in_doubt` from config.json (default: "escalate").

### 4. Out-of-Band Decompose for ESCALATE Items

For each ESCALATE finding, create a storyhook story with rich context. `--type escalate` sets the real, queryable `story_type` field (`forge-state.sh` detects pending escalations by this field, not by a title-substring match); the `ESCALATE:` title prefix is kept only as a human-readable convention, not the detection mechanism:

```bash
story new "ESCALATE: [finding title]" --type escalate
story prioritize HP-N critical
story comment HP-N '{"type":"escalate","finding":"[title]","severity":"[level]","description":"[full description]","options":[{"label":"Option 1","solution":"...","pros":"...","cons":"..."},{"label":"Option 2",...}],"recommendation":"[team recommendation]"}'
```

This gives the user structured context when they review ESCALATE items during the post-document pause.

### 5. FIX Cycle Check

Read the current fix cycle count from `.forge/fix-cycles/`:
- If fix cycle count >= `max_fix_cycles` (or `max_fix_cycles_yolo` in yolo mode):
  - Promote remaining FIX items to ESCALATE
  - Log: "Max fix cycles reached — remaining FIX items promoted to ESCALATE"

### 6. Write TRIAGE.md

Write `.forge/TRIAGE.md`:

```markdown
# Triage Report

## Summary
- Total findings: X
- FIX: Y
- ESCALATE: Z
- Yolo mode: true/false
- Fix cycle: N / max

## FIX Items

### [Finding Title] — FIX
- **Source**: REVIEW-REPORT / VALIDATE-REPORT
- **Severity**: Critical / Important / Useful
- **Chosen Solution**: [which option and why]
- **Rationale**: [why FIX, not ESCALATE]

## ESCALATE Items

### [Finding Title] — ESCALATE
- **Source**: REVIEW-REPORT / VALIDATE-REPORT
- **Severity**: Critical / Important / Useful
- **Story**: HP-N (created in storyhook)
- **Description**: [full description]
- **Options**:
  1. [Option with pros/cons]
  2. [Option with pros/cons]
  3. [Option with pros/cons]
- **Recommendation**: [team recommendation]
- **Rationale**: [why ESCALATE]
```

## Exit

**If `--orchestrated`:** Write `.forge/TRIAGE.md`, then follow the Step Exit Protocol
(`references/step-handoff.md`) — write `handoff-triage.md` (Triage Handoff table) and run:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step triage \
  --summary "[FIX count] FIX, [ESCALATE count] ESCALATE" --next "/forge continue"
```
No `--extra-path` is needed: any ESCALATE stories this step created live in storyhook's own
store outside the repository (see `references/handoff-format.md`).

The orchestrator reads TRIAGE.md on next `continue`:
- If FIX items exist and cycle < max → archives current cycle, dispatches to plan (FIX loop)
- If no FIX items → dispatches to document

**If standalone:** Write TRIAGE.md, report decisions to user, exit.
