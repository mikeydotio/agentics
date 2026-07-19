# rca

Reproduction-gated root cause analysis for **known** defects. Not a bug finder — a bug
*fixer's* pipeline: it takes a defect you or a user already observed and drives it through
scientific debugging to a verified cause, a calibrated fix-strategy verdict, an optional
gated fix, and a durable lesson.

## Pipeline

```
/rca <bug description>
  intake      Kepner-Tregoe IS/IS-NOT differential grid; GitHub/storyhook issue latching
  reproduce   FIRM GATE — automated failing repro test (flaky bugs get failure-rate
              quantification; override only by you or a /council-vote with a qa-engineer seat)
  locate      (FULL tier) git forensics: bisect in a disposable worktree, blame/SZZ-lite,
              pickaxe, churn×complexity hotspots, co-change couplings
  diagnose    ≥2 competing defect→infection→failure hypotheses; falsification experiments
              (toggle the failure on/off) in the worktree; adversarial challenge; ODC
              classification; SURGICAL vs REDESIGN verdict
  report      REPORT.md + REMEDIATION.md; issue comment; caller gate: fix now / hand off
  fix         RED → implement (behavior only) → GREEN → full suite → fix: commit →
              sibling-pattern sweep → optional separate refactor: commit (two hats)
  postmortem  committed blameless postmortem (docs/rca/<slug>.md) + preventative action;
              CLAUDE.md lesson offer; cleanup
```

Investigation depth is tiered: `/rca full <desc>` / `/rca light <desc>` skip the triage
confirmation; bare `/rca <desc>` triages and asks. Every step persists to `.rca/<slug>/`
(gitignored) — `/clear` + `/rca continue` resumes anywhere.

## Guarantees

- **No hypothesis work without a repro.** The failing test is the oracle for bisect, for
  every falsification experiment, and for the fix's red→green proof.
- **Your main tree is never touched** before you approve a fix: investigation writes only
  `.rca/` artifacts and new test files; instrumentation, defect-toggling, and `git bisect`
  happen in a disposable linked worktree under `.claude/worktrees/rca/`.
- **Fixes stay bisectable**: behavior fix and refactor are separate commits, on a feature
  branch, never main; push/PR stays yours. rca never bumps versions or deploys.

## Commands

| | |
|---|---|
| `/rca <description>` | new investigation |
| `/rca full\|light <description>` | new, with depth directive |
| `/rca --issue <gh#\|url\|storyhook-id> <desc>` | new, latched to an issue |
| `/rca` / `/rca continue [slug]` | resume from disk state |
| `/rca status` | dashboard |
| `/rca <step> [slug]` | run one step standalone |
| `/rca abandon <slug>` | tear down (worktree + artifacts disposition) |

## Dependencies

Required: `git`, `jq`. Optional: `gh` (GitHub issue latching), `story` (storyhook latching),
council plugin (`/council-vote`, repro-gate override), agents plugin (shared agent library —
qa-engineer, investigator, evidence-collector, experimenter, hypothesis-challenger,
software-architect, software-engineer, technical-writer).

## Layout

`skills/rca/` orchestrator + `skills/<step>/` per pipeline step (forge-style direct-Read
dispatch) · `bin/` deterministic scripts (status/scaffold/stack/repro/worktree/bisect/
forensics/hotspots — JSON contracts, plain-bash tests in `tests/`) · `references/`
methodology docs · `agent-overrides/<name>-context.md` pipeline context for shared agents.
