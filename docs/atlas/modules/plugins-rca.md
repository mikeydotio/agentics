---
module: plugins/rca
summary: "Root cause analysis pipeline — five phases from symptom intake to verified remediation plan"
read_when: "Touching the /rca skill, phase artifacts (.rca/<slug>/), references, or agent overrides"
sources:
  - path: plugins/rca/.claude-plugin/plugin.json
    blob: 454504e821d1a1c2cce7377572811e62205a91ec
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
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2]
generator: cartographer/1
baseline: b9203a6997fdbc2248086c1aa9ee6f62b1e025b6
verified: true
---

# Module: plugins/rca

## Purpose

Root cause analysis pipeline: bug report in, verified structural remediation plan out.
The /rca skill orchestrates; shared agents investigate under RCA-specific override prompts.
The design bet: phase artifacts in .rca/<slug>/ ARE the pipeline state and its resume points.
Registered as plugin "rca" (plugins/rca/.claude-plugin/plugin.json:2).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `rca` | skill | `plugins/rca/skills/rca/SKILL.md:2` | `/rca [symptom]`; phases 1 and 5 interactive, phases 2-4 delegated to one spawned agent |
| `RCA Override: Investigator` | agent override | `plugins/rca/agent-overrides/investigator-rca.md:1` | Phase 2 layer on shared investigator: git forensics + architecture analysis, read-only, facts only; subsumes code-archaeologist and systems-analyst |
| `RCA Override: Software Architect` | agent override | `plugins/rca/agent-overrides/architect-rca.md:1` | Phase 5 layer on shared software-architect: designs the structural fix, never edits source; replaces remediation-architect |
| `rca-status.sh` | bash script | `plugins/rca/bin/rca-status.sh:2` | `rca-status.sh [rca-dir]` → JSON of investigations with status, summary, AskUserQuestion options |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Architectural Root Cause Patterns` | reference doc | `plugins/rca/references/architectural-patterns.md:1` | Seven structural bug patterns with detection checklist; phase 4 matches the verified cause against them |
| `RCA Methodology Reference` | reference doc | `plugins/rca/references/rca-methodology.md:1` | 5 Whys, Fishbone, Fault Tree, Kepner-Tregoe — the technique kit phase 3 hypothesis chains follow |
| `Symptom vs Root Cause Heuristics` | reference doc | `plugins/rca/references/symptom-vs-root-cause.md:1` | Symptom indicators and verification tests gating phase 4 verification and phase 5 fix checks |

## Relationships

- `plugins-rca.rca -> plugins-agents-agents-chunk-2.investigator (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.evidence-collector (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.hypothesis-challenger (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-2.software-architect (calls)`
- `plugins-rca.investigator-rca -> plugins-agents-agents-chunk-2.investigator (extends)`
- `plugins-rca.architect-rca -> plugins-agents-agents-chunk-2.software-architect (extends)`
- `plugins-rca.rca -> plugins-rca.rca-status.sh (calls)`
- `plugins-rca.rca -> plugins-rca.rca-methodology (reads)`
- `plugins-rca.rca -> plugins-rca.symptom-vs-root-cause (reads)`
- `plugins-rca.rca -> plugins-rca.architectural-patterns (reads)`

## Type notes

- Artifacts are the only state (plugins/rca/skills/rca/SKILL.md:589).
- Each investigation lives in gitignored .rca/<slug>/ (plugins/rca/README.md:43).
- Slug: 3-5 hyphenated words from the bug description (plugins/rca/skills/rca/SKILL.md:130).
- Phases 1-3 write SYMPTOM.md, EVIDENCE.md, HYPOTHESES.md (plugins/rca/README.md:47-49).
- Phases 4-5 write VERIFICATION.md, REMEDIATION.md (plugins/rca/README.md:50-51).
- VERIFICATION.md is the investigation-complete signal (plugins/rca/skills/rca/SKILL.md:195).
- Phase 2 writes INCONCLUSIVE.md when no evidence is found (plugins/rca/skills/rca/SKILL.md:222).
- Phase 4 writes INCONCLUSIVE.md when all hypotheses fail (plugins/rca/skills/rca/SKILL.md:392).
- REMEDIATION=reviewed, VERIFICATION=complete, else running (plugins/rca/bin/rca-status.sh:34-40).
- Summary = first body line of SYMPTOM.md, max 120 chars (plugins/rca/bin/rca-status.sh:46).
- Phases 1 and 5 are interactive; 2-4 run in a spawned agent (plugins/rca/skills/rca/SKILL.md:173).
- Phases 2-4 never touch source; writes go to .rca/<slug>/ (plugins/rca/skills/rca/SKILL.md:192).

## External deps

- jq — assembles all rca-status.sh JSON output (plugins/rca/bin/rca-status.sh:11).
- git — log/blame/diff/bisect forensics (plugins/rca/agent-overrides/investigator-rca.md:16).
- tar — optional archive of finished investigations (plugins/rca/skills/rca/SKILL.md:576).
- Claude Code AskUserQuestion tool — one question per call (plugins/rca/skills/rca/SKILL.md:19).
- Claude Code Agent tool — runs phases 2-4 out-of-band (plugins/rca/skills/rca/SKILL.md:172).

## Gotchas

- rca-status.sh never checks INCONCLUSIVE.md (plugins/rca/bin/rca-status.sh:34-40).
- Inconclusive runs show as running, contra SKILL.md (plugins/rca/skills/rca/SKILL.md:232).
- "complete" still awaits remediation; "reviewed" means done (plugins/rca/bin/rca-status.sh:34-37).
- README's team roles are roles, not agent files (plugins/rca/README.md:17-23).
