# Postmortem Format (blameless, COE/SRE-lite)

The investigation's durable output: a committed doc at `docs/rca/<slug>.md` in the target
project, written by `agents:technical-writer`, plus a condensed comment on the latched issue.
The postmortem outlives the fix — its job is making the defect CLASS unrepeatable and the
lesson findable.

## Blameless rules

Causes are systemic, never personal. "The commit introduced X" states a fact; "Y was careless"
is banned. "Human error" is never a root cause — name what allowed the error: the missing
test, the unstated invariant, the ambiguous contract. Ask how, not who.

## docs/rca/<slug>.md template

```markdown
# <Title: the defect in one line>

- **Date**: <investigation completed>
- **Severity/Impact**: <who/what was affected, how badly, for how long>
- **Status**: Fixed in <sha> | Diagnosed, fix handed off (<issue link>)

## Summary
<3-5 sentences: failure, root cause, fix, one-line lesson.>

## Timeline
<Dated screenplay: defect introduced (sha, date) → first failure observed → reported →
diagnosed → fixed. Use SHAs and issue refs as anchors.>

## Root cause & trigger
<The verified defect→infection→failure chain from DIAGNOSIS.md, per-link evidence.
ODC classification: type/qualifier/trigger. What triggered the failure NOW (the WHEN answer).>

## Contributing factors
<AND-conditions, environmental legs, latent-defect exposers — everything that had to align.>

## The fix
<What changed and why it addresses the origin, not the symptom. Commits. Verdict
(SURGICAL/REDESIGN) + rationale; if REDESIGN: the escalation issue + tech-debt log entry.>

## Preventative action — killing the class
<At least ONE concrete, ideally already-landed guard that makes the defect CLASS impossible or
loudly detected: the regression test (name it), a lint rule, an assertion/invariant made
explicit, a type constraint, a documented contract. "Be more careful" is not an action.>

## Lessons
<What this taught about the codebase. Candidates for CLAUDE.md gotchas / atlas map notes.>
```

## Issue comment (condensed)

One comment: Summary, Root cause (chain in 3-4 lines), Fix commits or HANDOFF pointer,
Preventative action, link to the committed postmortem. Storyhook comments go through
`story comment <id>` as plain text (JSON-safe: let the CLI handle quoting).

## Lesson offers (one AskUserQuestion each, max two)

1. **CLAUDE.md gotcha** — when the lesson is a durable constraint an agent would otherwise
   re-trip on ("X must be validated at Y", "never call A before B"). Offer the exact one-line
   addition; the user approves before any CLAUDE.md edit.
2. **Atlas map** — when the project has `docs/atlas/` and the lesson is map-worthy (a
   load-bearing symbol, a gotcha in a mapped module): suggest `/atlas update` after the fix
   commits land. Suggest only; never run it.

## Completion & cleanup

Write `POSTMORTEM.md` in `.rca/<slug>/` pointing at the committed doc + issue comment. Then:
destroy any surviving worktree (`rca-worktree.sh destroy <slug>`), and offer archive
(tarball) / delete / keep for `.rca/<slug>/`.
