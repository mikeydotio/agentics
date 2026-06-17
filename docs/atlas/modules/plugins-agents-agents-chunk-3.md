---
module: "plugins/agents/agents (chunk 3)"
summary: "Forge quality-gate tail of the shared agent library — validator hardens tests, triager routes findings"
read_when: "Touching forge triage/validate steps or the triager/validator agent contracts"
sources:
  - path: plugins/agents/agents/triager.md
    blob: 4b91a0e95e560c1a4e48e6bee8d3ddd3ad2561d7
  - path: plugins/agents/agents/validator.md
    blob: e85b72f785ded4cdb4b1965161c2dd2abad5047f
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2]
generator: cartographer/2
baseline: 65c6f5e8e65713af63741fbe8d498384f530200e
verified: true
---

# Module: plugins/agents/agents (chunk 3)

## Purpose

Alphabetical tail of the shared agent library: the two forge quality-gate agents that close the
pipeline's review/validate → triage loop. validator hardens the implemented codebase's test suite
to production readiness; triager adjudicates every reviewer/validator finding into FIX, ESCALATE,
or DEFER so the orchestrator knows what to auto-fix versus hand to a human. Both are
`pipeline-specific` tier distillations of general-purpose agents, wired by declared lineage.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `triager` | agent | `plugins/agents/agents/triager.md:2` | Read-only adjudicator; emits TRIAGE.md with a FIX/ESCALATE/DEFER verdict plus rationale for every finding; decides, never implements (`plugins/agents/agents/triager.md:195`) |
| `validator` | agent | `plugins/agents/agents/validator.md:2` | Write-capable test hardener; emits VALIDATE-REPORT.md plus new tests (`plugins/agents/agents/validator.md:23`); reports implementation bugs as findings, never fixes them |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Batch Consolidation` | triage protocol | `plugins/agents/agents/triager.md:129` | Findings sharing a root cause merge into one verdict; TRIAGE.md consumers must expect a Consolidations section |
| `Decision Rules` | decision matrix | `plugins/agents/agents/triager.md:78` | Severity × fix-scope × config matrix; CRITICAL security always ESCALATEs; `when_in_doubt`/`yolo_mode` read from `.forge/config.json` (`plugins/agents/agents/triager.md:31`) shift thresholds |
| `Edge Case Taxonomy` | checklist | `plugins/agents/agents/validator.md:67` | 11 edge-case categories swept per tested component, prioritized by relevance, not applied exhaustively |
| `No-Mock Policy` | testing protocol | `plugins/agents/agents/validator.md:53` | Mocking the system under test is itself a finding; only external services may be mocked, fakes preferred |

## Relationships

- `plugins-agents-agents-chunk-3.triager -> plugins-agents-agents-chunk-2.reviewer (reads)`
- `plugins-agents-agents-chunk-3.triager -> plugins-agents-agents-chunk-3.validator (reads)`
- `plugins-agents-agents-chunk-3.triager -> plugins-agents-agents-chunk-2.project-manager (extends)`
- `plugins-agents-agents-chunk-3.triager -> plugins-agents-agents-chunk-2.security-researcher (extends)`
- `plugins-agents-agents-chunk-3.triager -> plugins-agents-agents-chunk-2.skeptic (extends)`
- `plugins-agents-agents-chunk-3.triager -> plugins-agents-agents-chunk-2.software-architect (extends)`
- `plugins-agents-agents-chunk-3.validator -> plugins-agents-agents-chunk-1.accessibility-engineer (extends)`
- `plugins-agents-agents-chunk-3.validator -> plugins-agents-agents-chunk-1.data-engineer (extends)`
- `plugins-agents-agents-chunk-3.validator -> plugins-agents-agents-chunk-2.performance-engineer (extends)`
- `plugins-agents-agents-chunk-3.validator -> plugins-agents-agents-chunk-2.qa-engineer (extends)`
- `plugins-agents-agents-chunk-3.validator -> plugins-agents-agents-chunk-2.security-researcher (extends)`
- `plugins-forge-skills.triage -> plugins-agents-agents-chunk-3.triager (calls)`
- `plugins-forge-skills.validate -> plugins-agents-agents-chunk-3.validator (calls)`
- `plugins-forge-agent-overrides.triager-context -> plugins-agents-agents-chunk-3.triager (extends)`
- `plugins-forge-agent-overrides.validator-context -> plugins-agents-agents-chunk-3.validator (extends)`

## Type notes

- Both pin `tier: pipeline-specific` and `pipeline: forge` (`plugins/agents/agents/triager.md:6`).
- Mirrored pins for validator (`plugins/agents/agents/validator.md:6`).
- triager tools are Read, Grep, Glob — read-only by grant (`plugins/agents/agents/triager.md:4`).
- validator adds Write, Edit, Bash to write and run tests (`plugins/agents/agents/validator.md:4`).
- Both Read every `<files_to_read>` file before any action (`plugins/agents/agents/triager.md:19`).
- Guardrails: 2000-line output cap, 3-retry tool cap (`plugins/agents/agents/triager.md:196`).
- validator must rerun the full suite after adding tests (`plugins/agents/agents/validator.md:210`).

## External deps

- None. Both files are markdown agent prompts; no packages or frameworks are touched.

## Gotchas

- Verdicts are tri-state: ADVISORY can DEFER (`plugins/agents/agents/triager.md:94`).
- `yolo_mode` flips triage to FIX-everything (`plugins/agents/agents/triager.md:99`).
- validator never fixes bugs it finds — findings only (`plugins/agents/agents/validator.md:203`).
