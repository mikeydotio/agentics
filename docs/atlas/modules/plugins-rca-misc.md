---
module: "plugins/rca (misc)"
summary: "Plugin identity for /rca: manifest + README documenting the reproduction-gated root-cause pipeline and its guarantees."
read_when: "Changing the rca plugin manifest or README"
sources:
  - path: plugins/rca/.claude-plugin/plugin.json
    blob: e592cc587f332374332260966588d163c551dede
  - path: plugins/rca/README.md
    blob: 62faa27cf38699a446a5ea5e487fe836278029a5
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/rca (misc)

## Purpose

The rca plugin drives a **known**, already-observed defect through a reproduction-gated scientific-debugging pipeline — intake, reproduce, locate, diagnose, report, fix, postmortem — refusing all hypothesis work (bisect, falsification experiments, the fix's red→green proof) until an automated failing repro test exists as the oracle (plugins/rca/README.md:3-6,12-24,33-34). It is explicitly not a bug finder: its identity (plugins/rca/.claude-plugin/plugin.json:4) and README describe a fixer's pipeline that isolates all instrumentation and defect-toggling in a disposable worktree, produces a calibrated SURGICAL-vs-REDESIGN verdict, and ends in a committed blameless postmortem rather than a silent code change (plugins/rca/README.md:23-24,35-37). Without this module's manifest and README, /rca would have neither a registered plugin identity nor the documented guarantees — repro gate, worktree isolation, bisectable separate commits — that distinguish it from an ad hoc debugging session.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Per-investigation state persists to .rca/<slug>/ (gitignored) as the resume anchor for /clear + /rca continue, one directory per bug slug (plugins/rca/README.md:28-29). All repro/bisect/hypothesis-toggle instrumentation is confined to a disposable linked worktree under .claude/worktrees/rca/; investigation only writes .rca/ artifacts and new test files to the main tree, never touching it before a fix is explicitly approved (plugins/rca/README.md:35-37). A fix's behavior change and any follow-on refactor are committed separately on a feature branch, never main, keeping history bisectable (plugins/rca/README.md:38-39).

## External deps


## Gotchas

- The reproduce step is a FIRM GATE: no hypothesis work (bisect, falsification experiments, the fix's red→green proof) proceeds without an automated failing repro test, overridable only by the user directly or via a /council-vote seating a qa-engineer — not by rca itself (plugins/rca/README.md:13-14,33-34).
- rca never pushes, opens a PR, bumps versions, or deploys: the fix and any refactor land as separate commits on a feature branch, but publishing the result stays the caller's responsibility (plugins/rca/README.md:38-39).
