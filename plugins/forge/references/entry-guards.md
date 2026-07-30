# Entry Guards

Checks that only matter when routing a **bare idea description or explicit `/forge interrogate`
without `--orchestrated`** — i.e. the user is about to start something new. Every other subcommand
(`continue`, `resume`, `status`, `stop`, a direct `--orchestrated` step invocation) skips this
file entirely; `skills/forge/SKILL.md`'s Command Router only points here on the interrogate-routing path
(this used to sit inline in the router body and reload on every single state transition
regardless of relevance).

## Legacy Migration Detection

Before routing, check for legacy ideate artifacts:

If `.planning/ideate/` exists with artifacts (IDEA.md, DESIGN.md, PLAN.md, etc.):
1. Use AskUserQuestion:
   - **header:** "Legacy Data"
   - **question:** "Found legacy ideate artifacts in `.planning/ideate/`. These are from the deprecated ideate plugin. Would you like to migrate them to the unified pipeline?"
   - **options:**
     - "Migrate to .forge/ (Recommended)" / "Copy legacy artifacts into the unified pipeline. Pros: cleanest path, single source of truth. Cons: original .planning/ideate/ files remain (manual cleanup)."
     - "Ignore — start fresh" / "Discard legacy work and begin from scratch. Pros: no legacy baggage. Cons: loses prior interrogation/design work."
     - "Keep both — I'll manage manually" / "Leave legacy in place, proceed with empty .forge/. Pros: full control, no data movement. Cons: two artifact trees to track."
2. If "Migrate":
   - Copy `.planning/ideate/IDEA.md` → `.forge/IDEA.md`
   - Copy `.planning/ideate/research/` → `.forge/research/`
   - Copy `.planning/ideate/DESIGN.md` → `.forge/DESIGN.md`
   - Copy `.planning/ideate/PLAN.md` → `.forge/PLAN.md`
   - Commit: `git add .forge/ && git commit -m "forge: migrate legacy ideate artifacts to .forge/"`
   - Resume with state detection on `.forge/`
3. If "Ignore" → proceed as normal (empty `.forge/` → interrogate)
4. If "Keep both" → proceed as normal, user manages legacy artifacts

Only check this once — if `.forge/` already has artifacts, skip the migration check.

## Incomplete Work Detection

Check for existing incomplete work before proceeding:

1. If `.forge/` does not exist or has no artifacts → skip (no prior work)
2. Run state detection: `bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-state.sh`
3. If state is `"interrogate"` → skip (clean slate, no artifacts)
4. If state is `"complete"` → silently clean up: `rm -rf .forge/`, proceed to interrogate with the new idea
5. If state is anything else → **incomplete work detected**

### Summarize (plain text, not AskUserQuestion)

Read the first H1 from `.forge/IDEA.md` for the project name (or "Unknown" if missing). Map the detected state to a human-readable description:

| State | Description |
|-------|-------------|
| `research` | Interrogation complete, awaiting research |
| `design` | Research complete, awaiting design |
| `plan` | Design complete, awaiting planning |
| `decompose` | Plan complete, awaiting story decomposition |
| `execute` | Execution in progress |
| `blocked` | One or more stories permanently blocked — user decision needed |
| `review_validate` | Execution complete, awaiting review and/or validate |
| `triage` | Review complete, awaiting triage |
| `fix_loop` | Fix cycle in progress (cycle N of M) |
| `document` | Triage complete, awaiting documentation |
| `pause_deploy` | Documentation complete, awaiting deploy decision |
| `pause_escalate` | Escalated items pending review |
| `deploy` | Deploy approved, awaiting deployment |

Present the user with a summary:

> **Existing pipeline detected.** The `.forge/` directory contains artifacts from a previous pipeline.
>
> **Project:** [project name from IDEA.md H1]
> **Stage reached:** [human-readable description from table above]
> **Artifacts present:** [comma-separated list of true artifacts from state JSON]

### Offer Options (AskUserQuestion)

- **header:** "Prior Work"
- **question:** "Starting a new idea will replace this incomplete pipeline. How would you like to proceed?"
- **options:**
  - "Archive and start fresh (Recommended)" / "Save a compressed backup of the current `.forge/` directory, then begin the new idea. Pros: nothing is lost, backup available if needed. Cons: creates an archive file in `.forge-archives/`."
  - "Overwrite — start fresh" / "Delete the current `.forge/` directory and begin the new idea immediately. Pros: cleanest slate, no leftover files. Cons: incomplete work is gone (though committed artifacts remain in git history)."
  - "Cancel — handle previous work first" / "Abort the new idea so you can resume or finish the existing pipeline. Pros: no data loss, continue where you left off. Cons: delays starting the new idea. Hint: use `/forge continue` to resume."

### Execute User's Choice

- **If "Archive and start fresh":**
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-archive.sh .forge .forge-archives
  ```
  Verify the JSON output has `ok: true`. Report the archive path to the user in plain text. If `ok: false`, report the error and suggest the "Overwrite" option instead. Then proceed to interrogate with the new idea.

- **If "Overwrite — start fresh":**
  ```bash
  rm -rf .forge/
  ```
  Proceed to interrogate with the new idea.

- **If "Cancel":**
  Report: "New idea cancelled. Run `/forge continue` to resume the existing pipeline, or `/forge status` to see where it left off."
  **STOP** — do not proceed.
