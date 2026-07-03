---
name: triage
description: Deliberate on review and validation findings. Label each as FIX or ESCALATE. Create ESCALATE stories via out-of-band decompose. Produces TRIAGE.md.
argument-hint: "[--yolo]"
---

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

For each ESCALATE finding, create a storyhook story with rich context:

```bash
story new "ESCALATE: [finding title]"
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

**If `--orchestrated`:** Follow the Step Exit Protocol:
1. Write `.forge/TRIAGE.md`
2. Write `.forge/handoffs/handoff-triage.md` with:
   - Key Decisions: FIX vs ESCALATE decisions, ESCALATE story IDs
   - Context for Next Step: FIX items for plan step (if any), ESCALATE count
   - Pipeline State: fix cycle count, yolo mode
3. Commit: `git add .forge/ .storyhook/ && git commit -m "forge(triage): [FIX count] FIX, [ESCALATE count] ESCALATE"`
4. Queue freshen: `bash plugins/freshen/bin/freshen.sh queue "/forge continue" --source forge --summary "Triage complete — [FIX count] FIX, [ESCALATE count] ESCALATE"`
5. STOP

The orchestrator reads TRIAGE.md on next `continue`:
- If FIX items exist and cycle < max → archives current cycle, dispatches to plan (FIX loop)
- If no FIX items → dispatches to document

**If standalone:** Write TRIAGE.md, report decisions to user, exit.
