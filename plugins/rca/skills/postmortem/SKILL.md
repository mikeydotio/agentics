---
name: postmortem
description: RCA step 7 — commit the blameless postmortem to docs/rca/, post the closing issue comment, offer the CLAUDE.md/atlas lesson, and clean up worktrees and artifacts.
argument-hint: "[slug]"
---

# RCA Postmortem — Durable Lesson & Cleanup

Read `${CLAUDE_PLUGIN_ROOT}/references/postmortem-format.md` — it defines the doc template,
blameless rules, comment format, and lesson-offer wording.

**Gate check**: `FIX.md` exists (fixed path) or `APPROVAL.md` records `handoff` (diagnosis-only
path — the postmortem still gets written, with Status "Diagnosed, fix handed off"). Inputs:
every artifact in `.rca/<slug>/`.

## 1. Write the committed postmortem (technical-writer)

Spawn the shared **technical-writer** (prefer `subagent_type: "agents:technical-writer"`;
prompt = `${CLAUDE_PLUGIN_ROOT}/agent-overrides/technical-writer-context.md` + DIAGNOSIS.md +
FIX.md/HANDOFF.md + REPORT.md + the template from postmortem-format.md). It writes
`docs/rca/<slug>.md` in the target project directly (it has Write). Verify on return: the doc
exists, follows the template, names at least one concrete preventative action, and contains
zero blame language; `git status --porcelain` shows only that doc.

Commit it (`docs:` conventional commit) on the current feature branch. Hand-off path with no
branch: offer to create one for the doc, or leave it uncommitted at the user's word — never
commit to main.

## 2. Close the loop on the issue

If latched: post the condensed postmortem comment (per postmortem-format.md) and log it in
`ISSUE.json`. Do NOT close the issue — commenting is RCA's only issue write; closing is the
user's call (say so once).

## 3. Lesson offers (max two questions, one each)

Per postmortem-format.md: (a) offer the exact one-line CLAUDE.md gotcha when the lesson is a
durable constraint — the user approves before any CLAUDE.md edit; (b) when the project has
`docs/atlas/` and the lesson is map-worthy, suggest `/atlas update` after the commits land —
suggest only, never run it. Skip either offer when it plainly doesn't apply.

## 4. Cleanup

1. Surviving worktree? `bash ${CLAUDE_PLUGIN_ROOT}/bin/rca-worktree.sh destroy <slug>`.
2. Write `.rca/<slug>/POSTMORTEM.md` (pointer to the committed doc + comment log).
3. ONE AskUserQuestion — artifacts disposition: **Archive** (`tar czf rca-<slug>.tar.gz -C
   .rca <slug>` then remove the dir) / **Delete** (`rm -rf .rca/<slug>`) / **Keep**.

## 5. Exit

Final summary: root cause (one sentence), fix status + SHAs (or hand-off pointer), the
preventative action, postmortem location, anything escalated (redesign issue, sibling
follow-ups). The investigation is complete.
