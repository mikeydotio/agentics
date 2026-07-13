---
module: plugins/rca/skills
summary: "RCA orchestrator + its seven pipeline step skills: intake, reproduce, locate, diagnose, report, fix, postmortem."
read_when: "Routing an rca pipeline step or editing gate logic"
sources:
  - path: plugins/rca/skills/diagnose/SKILL.md
    blob: 452858ff9907956598ddfbdfd4ec83c6c5dd2e26
  - path: plugins/rca/skills/fix/SKILL.md
    blob: df4eda98a53b8b32dcbfcd1a80a3532241025399
  - path: plugins/rca/skills/intake/SKILL.md
    blob: 62720791201b8f5e1dc4bab8a41240ee826875a1
  - path: plugins/rca/skills/locate/SKILL.md
    blob: 3a0467b4403695fea3087ccb238095fa57f60912
  - path: plugins/rca/skills/postmortem/SKILL.md
    blob: 500fd4f50fdd8445efffe31397da51b57aa15c81
  - path: plugins/rca/skills/rca/SKILL.md
    blob: 3b3e535a6745351cc7ca119c14528210c857754c
  - path: plugins/rca/skills/report/SKILL.md
    blob: 60f1dda4bd7d7ef5cd4b1934dad337e0973f1e11
  - path: plugins/rca/skills/reproduce/SKILL.md
    blob: d11295e7253fc43d910d34d086e99e0f37ddab80
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/rca/skills

## Purpose

The RCA plugin's orchestrator (plugins/rca/skills/rca/SKILL.md) is a thin state-machine router that reads investigation state from `.rca/<slug>/` artifacts and dispatches inline to one of seven step skills — it holds no reasoning of its own, only the routing table and the hard rules (firm repro gate, no production-code edits before APPROVAL.md, one AskUserQuestion per turn) that bind every step. What holds the seven steps together is a single reproduction-gated, hypothesis-falsification discipline: reproduce fails the investigation shut until an automated failing test exists, locate/diagnose form and falsify ≥2 competing root-cause hypotheses in a disposable worktree, and report/fix/postmortem gate escalating write access (an issue comment, then production code, then a committed doc) behind explicit artifact checkpoints. If this module vanished, RCA would have no resumable pipeline — each step's SKILL.md is the only place its gate checks, agent-spawn briefs, and artifact contracts are defined.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- REPRO.md/OVERRIDE.md is the reproduction-gate artifact: written exclusively by reproduce (plugins/rca/skills/reproduce/SKILL.md:12-17), and its existence is checked before locate (plugins/rca/skills/locate/SKILL.md:13-14) or diagnose (plugins/rca/skills/diagnose/SKILL.md:15) may proceed.
- APPROVAL.md is written once, by report's caller gate, recording `decision: fix|handoff` (plugins/rca/skills/report/SKILL.md:55); fix refuses to run unless it records `fix` (plugins/rca/skills/fix/SKILL.md:12), and postmortem reads a `handoff` decision to frame its Status line as "fix pending" (plugins/rca/skills/postmortem/SKILL.md:12; plugins/rca/skills/report/SKILL.md:61-62).
- The investigation's tier (`full`/`light`) is set once, in `meta.json`, during reproduce (plugins/rca/skills/reproduce/SKILL.md:75-80); FULL alone runs the standalone locate step (plugins/rca/skills/locate/SKILL.md:9), while LIGHT substitutes two inline forensics calls inside diagnose instead (plugins/rca/skills/diagnose/SKILL.md:20-27).
- The disposable worktree is created by `rca-worktree.sh` from either locate (for bisect, plugins/rca/skills/locate/SKILL.md:33-34) or diagnose (for falsification experiments, plugins/rca/skills/diagnose/SKILL.md:49-50), and its liveness is tracked in `worktree.json` and surfaced by rca-status until an explicit destroy (plugins/rca/skills/locate/SKILL.md:71-74; plugins/rca/skills/diagnose/SKILL.md:88-90).
- ISSUE.json is created once by intake when an issue is latched (plugins/rca/skills/intake/SKILL.md:43-44) and only ever appended to afterward — report and postmortem each log a posted comment into it, but neither ever closes the underlying issue (plugins/rca/skills/report/SKILL.md:41-42; plugins/rca/skills/postmortem/SKILL.md:29-33).

## External deps


## Gotchas

- Steps are dispatched by reading the target SKILL.md and following it inline — never via the Skill tool or a delegated subagent, because a subagent cannot spawn the step's own agents (plugins/rca/skills/rca/SKILL.md:105-107).
- Worktree-destroy defaults flip between adjacent steps: locate defaults to KEEP because diagnose usually needs the same worktree next (plugins/rca/skills/locate/SKILL.md:71-73), while diagnose defaults to DESTROY unless the user explicitly asked to keep it (plugins/rca/skills/diagnose/SKILL.md:88-90).
- fix's RED gate treats a passing repro as a hard stop, not success — a repro that passes at this point means the tree drifted since diagnosis, and the step must never "fix" a passing repro (plugins/rca/skills/fix/SKILL.md:19-21).
- postmortem's issue close-out is deliberately restricted to posting a comment — closing the latched issue is left to the user, never done by RCA (plugins/rca/skills/postmortem/SKILL.md:29-33).
