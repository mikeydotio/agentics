---
module: plugins/rca
summary: "Five-phase root cause analysis plugin — symptom intake through verified remediation, artifact-driven state"
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
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/rca

## Purpose

Provides the `/rca` skill: a five-phase orchestrated investigation that traces a reported bug from
observed symptom to a verified structural root cause, then designs a remediation addressing the
cause rather than masking it. The governing principle — "treat the disease, not the symptom" — is
enforced mechanically: evidence precedes hypothesis, multiple competing hypotheses are required, and
every proposed fix is stress-tested against anti-pattern checks before the user approves it. If
this plugin vanished, the project would have no structured methodology for non-superficial bug
diagnosis.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `rca` | skill | `plugins/rca/skills/rca/SKILL.md:2` | `/rca [symptom]`; resumes from `.rca/<slug>/` artifacts or starts Phase 1 fresh |
| `rca-status.sh` | bash script | `plugins/rca/bin/rca-status.sh:2` | `rca-status.sh [rca-dir]` → JSON `{ok, count, investigations}` with status and AskUserQuestion options |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `investigator-rca.md` | agent override | `plugins/rca/agent-overrides/investigator-rca.md:1` | Extends shared investigator with dual Phase 2 focus: git forensics AND architecture analysis; enforces read-only and facts-only constraints |
| `architect-rca.md` | agent override | `plugins/rca/agent-overrides/architect-rca.md:1` | Extends shared software-architect for Phase 5 remediation design; adds anti-pattern self-check table and write-to-`.rca/`-only constraint |
| `rca-methodology.md` | reference | `plugins/rca/references/rca-methodology.md:1` | 5 Whys, Fishbone, Fault Tree, Kepner-Tregoe — the technique kit Phase 3 hypothesis chains must follow |
| `symptom-vs-root-cause.md` | reference | `plugins/rca/references/symptom-vs-root-cause.md:1` | Heuristic tests distinguishing symptoms from root causes; Phase 4 verification and Phase 5 fix checks both apply them |
| `architectural-patterns.md` | reference | `plugins/rca/references/architectural-patterns.md:1` | Seven structural bug pattern archetypes with detection checklist; Phase 4 matches verified cause against them |

## Relationships

- `plugins-rca.rca -> plugins-agents-agents-chunk-2.investigator (calls)` — `plugins/rca/skills/rca/SKILL.md:208` spawns `plugins/agents/agents/investigator.md` for Phase 2
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.evidence-collector (calls)` — `plugins/rca/skills/rca/SKILL.md:214` spawns `plugins/agents/agents/evidence-collector.md` for Phases 2 and 3
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.hypothesis-challenger (calls)` — `plugins/rca/skills/rca/SKILL.md:375` spawns `plugins/agents/agents/hypothesis-challenger.md` for Phase 4
- `plugins-rca.rca -> plugins-agents-agents-chunk-2.software-architect (calls)` — `plugins/rca/skills/rca/SKILL.md:481` spawns `plugins/agents/agents/software-architect.md` for Phase 5
- `plugins-rca.investigator-rca.md -> plugins-agents-agents-chunk-2.investigator (extends)` — `plugins/rca/agent-overrides/investigator-rca.md:1` is applied on top of the shared investigator at spawn time
- `plugins-rca.architect-rca.md -> plugins-agents-agents-chunk-2.software-architect (extends)` — `plugins/rca/agent-overrides/architect-rca.md:1` is applied on top of the shared software-architect at spawn time
- `plugins-rca.rca -> plugins-rca.rca-status.sh (calls)` — `plugins/rca/skills/rca/SKILL.md:31` calls the script on every invocation to detect existing investigations

## Type notes

**Artifact-as-state contract**: The five phases are checkpointed entirely by files in `.rca/<slug>/`.
`rca-status.sh` derives phase from artifact presence: `REMEDIATION.md` → reviewed, `VERIFICATION.md`
→ complete, neither → running (`plugins/rca/bin/rca-status.sh:34–39`). Resume on re-invocation is free.

**Agent override pattern**: RCA spawns shared agents with override files applied on top.
`investigator-rca.md` and `architect-rca.md` add phase-specific context and constraints without
forking the shared definitions (`plugins/rca/skills/rca/SKILL.md:208–210`, `481–482`).

**Phase 2 parallelism**: Investigator and evidence-collector are spawned simultaneously
(`plugins/rca/skills/rca/SKILL.md:205`). The orchestrator synthesizes their results into
`EVIDENCE.md` before Phase 3 begins.

**Inconclusive exits**: Phase 2 and Phase 4 each have explicit exit ramps that write
`INCONCLUSIVE.md` and halt (`plugins/rca/skills/rca/SKILL.md:222–232`, `390–405`). Halted
investigations surface on next `/rca` invocation via `rca-status.sh`, but note: `rca-status.sh`
has no `INCONCLUSIVE.md` branch — these show as `running` status (`plugins/rca/bin/rca-status.sh:34–40`).

## External deps

- `jq` — all JSON assembly in `rca-status.sh` (`plugins/rca/bin/rca-status.sh:11`)
- `git` — log/blame/diff/bisect forensics during Phase 2 (`plugins/rca/agent-overrides/investigator-rca.md:16`)
- `tar` — optional archive of completed investigations (`plugins/rca/skills/rca/SKILL.md:576`)

## Gotchas

- `rca-status.sh` shows inconclusive investigations as `running` because it only checks for `REMEDIATION.md` and `VERIFICATION.md` (`plugins/rca/bin/rca-status.sh:34–40`).
- Phase 5 (Remediation) is not triggered automatically after Phase 4 completes — it only runs when the user re-invokes `/rca` and selects "Review [slug]" (`plugins/rca/skills/rca/SKILL.md:43`).
- Investigative agents in Phases 2–4 must not write outside `.rca/<slug>/`; this is enforced via the investigation prompt constraint (`plugins/rca/skills/rca/SKILL.md:192`), not a hard tool restriction.
