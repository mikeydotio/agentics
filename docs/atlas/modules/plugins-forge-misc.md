---
module: "plugins/forge (misc)"
summary: "Forge's plugin manifest and README — plugin identity plus the user-facing contract for the idea-to-deployment pipeline"
read_when: "Changing forge's marketplace identity or updating the README pipeline overview"
sources:
  - path: plugins/forge/.claude-plugin/plugin.json
    blob: 332a69faf8c603a9f032ee7765befc874b534aca
  - path: plugins/forge/README.md
    blob: 1ce02e4c6294d5613a305d8487b42132d669a063
references_modules: [root-misc]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/forge (misc)

## Purpose

Forge's identity layer: `plugin.json` declares the name and one-line description under which
Claude Code loads the plugin, and `README.md` is the user-facing contract for the pipeline —
command surface, per-step artifact I/O, architecture, and safety bounds. The README's design
claim is the load-bearing one: pipeline state derives entirely from `.forge/` artifacts on
disk, never from conversation (plugins/forge/README.md:54-57). Forge unifies the formerly
separate ideate and forge plugins into a single pipeline (plugins/forge/README.md:7).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Forge Plugin` | README | `plugins/forge/README.md:1` | Pipeline overview: commands, step artifact I/O, FIX/ESCALATE loop, safety rules |
| `forge` | plugin manifest | `plugins/forge/.claude-plugin/plugin.json:2` | Marketplace-facing name; description advertises the unified idea-to-deployment pipeline |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `FIX/ESCALATE Loop` | README section | `plugins/forge/README.md:74` | FIX items re-enter the Plan -> ... -> Triage loop; ESCALATE items wait for user review |
| `Pipeline Steps (11)` | README section | `plugins/forge/README.md:36` | Maps every step to its input and output artifacts, `IDEA.md` through `COMPLETION.md` |
| `State Machine Router` | README section | `plugins/forge/README.md:54` | Resume-anywhere design: the orchestrator re-derives the current step from `.forge/` contents |
| `Step Exit Protocol` | README section | `plugins/forge/README.md:59` | Uniform exit every step follows: write artifacts, write handoff, commit, queue freshen, stop |

## Relationships

- `root-misc.marketplace.json -> plugins-forge-misc.plugin.json (reads)`

## Type notes

- Pipeline state derives from `.forge/` artifacts, never conversation (plugins/forge/README.md:56)
- Each step exits: write artifacts, handoff, commit, queue freshen (plugins/forge/README.md:59-65)
- Handoffs land at `.forge/handoffs/handoff-<step>.md` (plugins/forge/README.md:63)
- Fix cycles are bounded: 3 normally, 10 under `--yolo` (plugins/forge/README.md:77)
- Deploy never runs without explicit user permission (plugins/forge/README.md:83)
- The pipeline always pauses after Document for user review (plugins/forge/README.md:84)

## External deps

- None — manifest JSON and markdown documentation; no third-party packages touched
