---
module: plugins/rca
summary: "Orchestrates five-phase root cause analysis: symptom, evidence, hypotheses, verification, remediation."
read_when: "Touching the /rca skill, phase artifacts (.rca/<slug>/), references, or agent overrides"
sources:
  - path: plugins/rca/.claude-plugin/plugin.json
    blob: 2c8f35ec6ee91eae723b3f285b57fca1b47d8a3e
  - path: plugins/rca/README.md
    blob: 65f996dd8e8f6f0627b43e7f2ddab8b68dd21b3b
  - path: plugins/rca/agent-overrides/architect-rca.md
    blob: 6c5765aa64e41195c3841b0775d1847fa4359c31
  - path: plugins/rca/agent-overrides/investigator-rca.md
    blob: 85ff269974b4953c0687a67583763f5f734c334f
  - path: plugins/rca/bin/rca-status.sh
    blob: cbadac1feae9bd9f334eb9c03240664c43d7563f
  - path: plugins/rca/references/architectural-patterns.md
    blob: b167fb9a7ba41edd6b8c4fe215fbbaf7bfb262d3
  - path: plugins/rca/references/rca-methodology.md
    blob: a1711e6a044250dd1297f62b7382a107086990f6
  - path: plugins/rca/references/symptom-vs-root-cause.md
    blob: 7163bcfd24f1d5fe21ce30c56cb4b943441f2ca3
  - path: plugins/rca/skills/rca/SKILL.md
    blob: c5271dfc51b0450cc67a901b66fc599a53601e88
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/rca

## Purpose

This plugin is a root-cause-analysis pipeline: the orchestrator skill (plugins/rca/skills/rca/SKILL.md) drives five sequential phases — symptom intake, evidence collection, hypothesis formation, root cause verification, and remediation design — persisting each phase's output to `.rca/<slug>/` artifacts so an investigation can be resumed via plugins/rca/bin/rca-status.sh. It exists to counteract the pull toward quick, symptom-masking fixes: plugins/rca/agent-overrides/investigator-rca.md fuses the shared investigator agent's git-archaeology and architecture-analysis lenses for Phase 2, and plugins/rca/agent-overrides/architect-rca.md constrains the shared software-architect agent to design a structural fix (never write code) in Phase 5. If this module vanished there would be no systematic mechanism forcing multiple competing hypotheses, heuristic verification, and anti-pattern rejection before a fix ships — bugs would get patched where they're noticed rather than where they originate.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Investigation state lives entirely in `.rca/<slug>/` artifact files, never in memory: plugins/rca/bin/rca-status.sh:33 derives each investigation's status (running/complete/reviewed) purely from which of SYMPTOM.md, VERIFICATION.md, or REMEDIATION.md exist in its directory, so every phase must persist its output before the orchestrator can stop. Phase 2-4 investigative agents are contractually read-only and confined to writing inside `.rca/<slug>/` — stated as Hard Rule 7 in plugins/rca/skills/rca/SKILL.md:22 and re-enforced per-agent in plugins/rca/agent-overrides/investigator-rca.md:39. The Phase 5 software-architect override carries the opposite but equally strict constraint: it must never use Write/Edit on source code and may only write the remediation plan document into the investigation directory (plugins/rca/agent-overrides/architect-rca.md:60) — remediation here is a design artifact, not an applied fix. Artifact presence doubles as a phase-completion signal: VERIFICATION.md existing means Phase 4 is done and the investigation is ready for Phase 5 review (plugins/rca/skills/rca/SKILL.md:195), which rca-status.sh in turn reads as the 'complete' status before REMEDIATION.md later flips it to 'reviewed' (plugins/rca/bin/rca-status.sh:34).

## External deps
