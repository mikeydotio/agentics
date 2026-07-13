# Issue Latching

RCA can attach an investigation to an existing GitHub issue or storyhook story: the issue
seeds intake, receives findings (report + postmortem comments), and anchors hand-offs. `gh`
and `story` are OPTIONAL dependencies — when the relevant CLI is missing, say so once,
disable latching for the run, and continue.

## Reference parsing (explicit `--issue <ref>`)

| Ref shape | Provider | Verify with |
|---|---|---|
| `#123` or bare `123` | GitHub (current repo) | `gh issue view 123 --json number,title,state,body,url` |
| `https://github.com/<o>/<r>/issues/123` | GitHub (that repo) | `gh issue view <url> --json …` |
| storyhook id (project prefix pattern, e.g. `ABC-12`) | storyhook | `story show <id> --json` |

Explicit refs are authoritative: a failed verification (not found, CLI error, closed +
user-unaware) is a HARD error — surface it and ask, never silently proceed unlatched.
Ambiguous bare numbers when both providers exist: one AskUserQuestion.

## Context detection (no explicit ref)

Fallback signals, in order; ANY hit requires one AskUserQuestion confirmation before latching
(never latch silently):

1. The conversation/invocation text names an issue ("fixing #42", a pasted issue URL, a
   storyhook id).
2. The current branch encodes an issue (issue-plugin worktree branches, `fix/42-…` shapes).
3. An in-progress storyhook story (`story list --state in-progress --json`) whose title
   matches the bug description closely.

No hits → run unlatched; note in meta.json (`issue: null`) and move on — do not ask.

## Seeding intake

On latch: pull body + comments (`gh issue view --json body,comments` / `story show --json`)
and pre-fill grid cells with `source: issue`. Reporter language is WHAT/WHEN gold; maintainer
comments often carry IS-NOT cases ("can't repro on staging").

## Posting findings

Exactly two comment moments — report and postmortem (no play-by-play noise):

```bash
gh issue comment <ref> --body-file <tmpfile>     # GitHub
story comment <id> "<condensed text>"            # storyhook
```
Report comment: root cause chain (condensed), confidence, verdict, remediation summary, and —
on hand-off — the HANDOFF.md pointer. Postmortem comment: per `postmortem-format.md`.
Record every posted comment (provider, ref, timestamp) in `ISSUE.json`.

## meta.json / ISSUE.json

`meta.json.issue`: `{provider: "gh"|"storyhook", ref, url}` or `null`. `ISSUE.json`: the
fetched snapshot (title/state/body digest) + log of comments posted. The snapshot is
investigation input; never edit the issue itself (no close, no label) — commenting is the
only write, and closing remains the user's call.
