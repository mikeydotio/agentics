---
module: plugins/rca/references
summary: "RCA methodology references: KT intake, git forensics, falsification, ODC verdicts, fix/postmortem protocols."
read_when: "Changing rca's methodology or postmortem format"
sources:
  - path: plugins/rca/references/architectural-patterns.md
    blob: fbf3235986780924c4477a2a1bd420de70909048
  - path: plugins/rca/references/fix-protocol.md
    blob: 7524b995ef4c4e83272dc8e151aeb6de33fffe0a
  - path: plugins/rca/references/git-forensics.md
    blob: 5d3fd0b357083289aa9bb2597e742c9e5679aaf0
  - path: plugins/rca/references/hypothesis-falsification.md
    blob: 1818d95ab450f99ca0e708f2b1776996459537ac
  - path: plugins/rca/references/issue-latching.md
    blob: 26869d12d8c68e3e0ca85382e978ebe9de9a2a95
  - path: plugins/rca/references/kt-intake.md
    blob: e600ea6f0a22e636e6d083442199ece7cd5aa561
  - path: plugins/rca/references/odc-classification.md
    blob: ff22bb3cd0da2980593dad9d238db7af2f0552c3
  - path: plugins/rca/references/postmortem-format.md
    blob: 81b16b0cc57d4cda1a6c2483aebaca8f5d46a7eb
  - path: plugins/rca/references/repro-gate.md
    blob: a049b17ca59761b41c7e66c22b4e422602c03ff1
  - path: plugins/rca/references/symptom-vs-root-cause.md
    blob: a823921936e5f86b4992b2a21f9d1d7a136998e2
  - path: plugins/rca/references/worktree-protocol.md
    blob: 46c8e2851d79361b2e383b87af28e7e03a7587b1
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/rca/references

## Purpose

Encodes the evidence-and-verdict methodology RCA's orchestrator steps cite instead of duplicating: Kepner-Tregoe IS/IS-NOT intake (plugins/rca/references/kt-intake.md:9-16), deterministic git forensics handed to an investigator to interpret (plugins/rca/references/git-forensics.md:3-5), Zeller's hypothesis falsification requiring competing hypotheses (plugins/rca/references/hypothesis-falsification.md:16-17), and IBM ODC classification driving the surgical-vs-redesign fix verdict (plugins/rca/references/odc-classification.md:33-51). A shared defect/infection/failure vocabulary (plugins/rca/references/hypothesis-falsification.md:6-8) threads every doc, and the fix protocol enforces each gate between agent turns rather than letting the implementer self-gate (plugins/rca/references/fix-protocol.md:3-4).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Each doc owns one lifecycle artifact the orchestrator writes to .rca/<slug>/: kt-intake.md governs GRID.md (plugins/rca/references/kt-intake.md:55); git-forensics.md governs ORIGIN.md, facts-only with no causation claims (plugins/rca/references/git-forensics.md:74-79); hypothesis-falsification.md governs DIAGNOSIS.md (plugins/rca/references/hypothesis-falsification.md:67-73); repro-gate.md governs REPRO.md or the user/council-only OVERRIDE.md — the only two ways to satisfy the gate (plugins/rca/references/repro-gate.md:9-13); fix-protocol.md governs FIX.md (plugins/rca/references/fix-protocol.md:43-48); postmortem-format.md governs the committed docs/rca/<slug>.md plus a closing POSTMORTEM.md pointer (plugins/rca/references/postmortem-format.md:3-4,67). worktree-protocol.md carries the hard isolation invariant underlying all of it: production code in the main tree is never modified, even temporarily, before fix approval — all mutation (instrumentation, defect toggling, git bisect) happens only in the disposable rca/<slug> linked worktree (plugins/rca/references/worktree-protocol.md:3-6,40-47).

## External deps


## Gotchas

- Linked worktrees do NOT share untracked files, so an untracked repro test (and any fixture it needs) must be explicitly `--copy`'d into the worktree or bisect silently loses it (plugins/rca/references/worktree-protocol.md:28-30).
- A repro test that passes at the fix step's RED gate means the tree drifted since diagnosis, not that the bug is already fixed — stop and re-orient rather than trust it (plugins/rca/references/fix-protocol.md:13-15).
- "N consecutive passes" after a fix is a statistical claim, not proof: for a bug with true failure rate p, the chance N passes are coincidence is (1-p)^N (plugins/rca/references/repro-gate.md:49-50).
- If git bisect's declared "good" ref already fails the test (`good_is_bad`), the known-good claim itself is wrong — go back to the KT grid's WHEN row instead of widening the bisect range blindly (plugins/rca/references/git-forensics.md:31-32).
