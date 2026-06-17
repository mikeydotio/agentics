---
module: "plugins/agents/agents (chunk 2)"
summary: "Shared agent library slice — specialist subagent contracts, investigator through technical-writer"
read_when: "Touching the shared agents investigator through technical-writer (incl. map-verifier)"
sources:
  - path: plugins/agents/agents/investigator.md
    blob: 3a140ee738ce520e566b8e61f683eabfca3433e6
  - path: plugins/agents/agents/lawyer.md
    blob: 5fda3e7a2e1bdc8297d9be3b223c932af798f127
  - path: plugins/agents/agents/map-repairer.md
    blob: 564b2ad94074890dcdf5a2a60ae0bb91b237d421
  - path: plugins/agents/agents/map-verifier.md
    blob: ac52315a17ab18080ad6ad89c57a77998e802aed
  - path: plugins/agents/agents/observability-engineer.md
    blob: eca36942ef2fc5771d811f8a7e758867d7207bf6
  - path: plugins/agents/agents/performance-engineer.md
    blob: 846b109f5b2225e9084733564c9dfbd38df0a527
  - path: plugins/agents/agents/project-manager.md
    blob: e969875e8b4425656e79735a9a52baeaafed37d1
  - path: plugins/agents/agents/qa-engineer.md
    blob: cf5566ed98b94145f5a4a2a60a3e18f8a75de330
  - path: plugins/agents/agents/reviewer.md
    blob: 0271c45f317b4ff3e824559b49f0a305938dea4f
  - path: plugins/agents/agents/security-researcher.md
    blob: ab64243cb5c0edbd1c34797b5941472a45e0732a
  - path: plugins/agents/agents/skeptic.md
    blob: f961e8361a32ff2be468d16c71c9575ad2e84069
  - path: plugins/agents/agents/software-architect.md
    blob: c3abdf88838589d5c78cfe5669e730737bf0195c
  - path: plugins/agents/agents/software-engineer.md
    blob: 8ebb8be26e64490f77669942f1b88c3bab9a2246
  - path: plugins/agents/agents/technical-writer.md
    blob: fcec96880785ebb5409208d8d8d2abc35ef9f375
references_modules: [plugins-agents-agents-chunk-1, plugins-atlas-misc]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/agents/agents (chunk 2)

## Purpose

The investigator-through-technical-writer slice of the shared agent library: each file is one
spawnable subagent contract. YAML frontmatter is the machine-readable signature (`tools`, `tier`,
`pipeline`, `read_only`); the `<role>` body fixes mission, methodology, output format, and
guardrails. It also holds the two pipeline-bound composites — forge's reviewer and atlas's
map-verifier and map-repairer — composing general-tier methodology via declared Lineage.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `investigator` | agent | `plugins/agents/agents/investigator.md:2` | Read-only RCA: evidence-vs-theory split, multi-hypothesis, 5 Whys, red-herring filter |
| `lawyer` | agent | `plugins/agents/agents/lawyer.md:2` | Read-only license/privacy/billing risk analysis; disclaimer mandatory in every output |
| `map-repairer` | agent | `plugins/agents/agents/map-repairer.md:2` | Atlas-bound; surgically corrects flagged map-doc claims; Edit-only, never re-surveys |
| `map-verifier` | agent | `plugins/agents/agents/map-verifier.md:2` | Atlas-bound; refutes sampled map-doc claims; replies with one JSON verdict under 4KB |
| `observability-engineer` | agent | `plugins/agents/agents/observability-engineer.md:2` | Write-capable; structured logs, golden-signal metrics, tracing, SLOs; never logs PII |
| `performance-engineer` | agent | `plugins/agents/agents/performance-engineer.md:2` | Read-only complexity/N+1/memory analysis with production scale factors and budgets |
| `project-manager` | agent | `plugins/agents/agents/project-manager.md:2` | Writes plans: parallel waves, machine-evaluable acceptance criteria, traceability |
| `qa-engineer` | agent | `plugins/agents/agents/qa-engineer.md:2` | Writes tests: no-mock policy, 11-Category Edge Case Taxonomy, `.env.test.example` scaffolding |
| `reviewer` | agent | `plugins/agents/agents/reviewer.md:2` | Forge-bound; read-only eight-dimension codebase review, severity-ranked for FIX/ESCALATE triage |
| `security-researcher` | agent | `plugins/agents/agents/security-researcher.md:2` | Read-only OWASP Top 10 walk, trust-boundary map, exploit scenarios, secrets/CVE audit |
| `skeptic` | agent | `plugins/agents/agents/skeptic.md:2` | Read-only assumption map and Socratic challenge; "What's Working Well" is mandatory |
| `software-architect` | agent | `plugins/agents/agents/software-architect.md:2` | Read-only design/review: SOLID, coupling, layering, inward dependency rule |
| `software-engineer` | agent | `plugins/agents/agents/software-engineer.md:2` | Write-capable; red-green TDD non-optional; minimum correct code, YAGNI/DRY |
| `technical-writer` | agent | `plugins/agents/agents/technical-writer.md:2` | Write-capable docs: placement framework, audience targeting, ADR template |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `<files_to_read>` | spawn-protocol marker | `plugins/agents/agents/investigator.md:17` | Each agent must Read all files in this prompt block before acting; spawner handoffs rely on it |

## Relationships

- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-1.api-designer (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-1.copy-editor (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-2.software-architect (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-2.security-researcher (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-2.performance-engineer (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-2.qa-engineer (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-2.observability-engineer (extends)`
- `plugins-agents-agents-chunk-2.reviewer -> plugins-agents-agents-chunk-2.lawyer (extends)`
- `plugins-agents-agents-chunk-2.map-verifier -> plugins-agents-agents-chunk-1.hypothesis-challenger (extends)`
- `plugins-agents-agents-chunk-2.map-verifier -> plugins-agents-agents-chunk-1.evaluator (extends)`
- `plugins-agents-agents-chunk-2.map-verifier -> plugins-agents-agents-chunk-2.skeptic (extends)`
- `plugins-agents-agents-chunk-2.map-repairer -> plugins-agents-agents-chunk-2.map-verifier (reads)`
- `plugins-agents-agents-chunk-2.map-repairer -> plugins-agents-agents-chunk-2.software-engineer (extends)`
- `plugins-agents-agents-chunk-2.map-repairer -> plugins-atlas-misc.map-format (reads)`

## Type notes

- reviewer: `pipeline: forge` (`plugins/agents/agents/reviewer.md:8`).
- map-verifier: `pipeline: atlas` (`plugins/agents/agents/map-verifier.md:7`).
- map-repairer: `pipeline: atlas`, `read_only: false` — uses Edit (not Write) to preserve byte-identical untouched lines (`plugins/agents/agents/map-repairer.md:7`).
- `read_only: true` mirrors the tool grant: no Write/Edit (e.g. `plugins/agents/agents/skeptic.md:8`).
- A 2000-line output cap and 3-retry tool rule recur per agent (e.g. `plugins/agents/agents/lawyer.md:188`).
- map-verifier and map-repairer inline "All shared-library guardrails apply" rather than listing them separately; the text comes from `plugins/agents/agents/_guardrails.md` (owned by chunk-1).

## External deps

- None — self-contained markdown; `tools:` names Claude Code built-ins, not packages.

## Gotchas

- Only map-verifier and map-repairer invoke "All shared-library guardrails apply" by reference (`plugins/agents/agents/map-verifier.md:82`, `plugins/agents/agents/map-repairer.md:68`).
- The rest inline their own Guardrails sections (e.g. `plugins/agents/agents/investigator.md:183`).
- A library-wide guardrail change therefore touches every agent file in this slice.
