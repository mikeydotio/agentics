---
name: intake
description: RCA step 1 — latch an existing GitHub/storyhook issue, scaffold the investigation, and build the Kepner-Tregoe IS/IS-NOT differential grid from the bug description, issue, and light recon; ask only about genuine gaps.
---

# RCA Intake

## Resolve runtime first

Walk four directories upward from this file path (three above its containing directory)
to resolve `<plugin-root>`. Read `<plugin-root>/codex/references/runtime.md` completely
before this step. It defines native questions, authorization, agent dispatch, reference
selection, and verification of write boundaries. Substitute absolute paths; do not rely
on environment variables being expanded by the host.


You are running the intake step of an RCA investigation. Inputs: a bug description (argument
or conversation) and optionally an issue reference. Output: a scaffolded `.rca/<slug>/` with
`meta.json`, `GRID.md`, and `ISSUE.json`. Read `<plugin-root>/codex/references/kt-intake.md`
and `<plugin-root>/codex/references/issue-latching.md` before proceeding.

Rules in force: one question per native question call; read-only beyond `.rca/` and the target
project's `.gitignore` (handled by the scaffold script); blameless language.

## 1. Issue latch

Follow `issue-latching.md`:
- Explicit `--issue <ref>` → parse provider, verify (`gh issue view … --json` /
  `story show … --json`). Verification failure is a HARD error — surface and ask.
- No explicit ref → context detection (conversation mentions, branch naming, in-progress
  stories). Any hit → confirm with one native question before latching. No hits → proceed
  unlatched without asking.
- Missing `gh`/`story` CLI → note once, proceed unlatched.

## 2. Scaffold

Generate the slug and initialize:

```bash
bash "<plugin-root>/bin/rca-scaffold.sh" slug "<bug description>"
bash "<plugin-root>/bin/rca-scaffold.sh" init <slug> --description "<one-line>" \
  [--issue-provider gh|storyhook --issue-ref <ref>] [--tier full|light]
```

Pass `--tier` ONLY when the user's invocation carried an explicit depth directive (`$rca full
…`, "perform a full rca", `$rca light …`) — it becomes `tier_directive` and suppresses the
tier confirmation later. The script also idempotently gitignores `.rca/` and
`.claude/worktrees/` in the target project. On `slug_exists`, ask: resume that investigation
instead, or re-slug (append a qualifier).

If latched, write `ISSUE.json`: the fetched snapshot (title, state, body digest) and an empty
`comments_posted` array.

## 3. Build the grid

Per `kt-intake.md`:
1. Pre-fill every cell you can from issue body/comments (`source: issue`), the user's
   description (`source: user`), and light read-only recon — grep the error text, check
   version strings, `git log` around mentioned dates (`source: inferred`, with confidence).
2. Ask ONLY about empty/ambiguous cells — one native question per cell, worst gap first,
   options carrying the most likely values plus "don't know". The mandatory question if not
   already answered: "Did this ever work — and when did it last work?" (sets
   Regression/Longstanding + `known_good`).
3. Stop when WHAT-IS, WHEN-IS, EXTENT-IS are filled and no load-bearing cell is empty; offer
   "enough — proceed to reproduction" as an option on the last gap question rather than
   asking an extra standalone question.

Write `GRID.md` (format per kt-intake.md: summary line first — rca-status.sh displays it —
then the grid, Distinctions, Aligned changes, and the classification line).

## 4. Exit

Present a 3-5 line summary: the failure, the sharpest distinction, regression status, latch
status. If orchestrated, the router proceeds to `reproduce`. If invoked standalone, tell the
user: next is the reproduction gate — `$rca continue <slug>`.
