---
module: "plugins/agents (misc)"
summary: "Operational shell of the agent library — plugin manifest, /agents skill, structural validator"
read_when: "Adding agents, changing the agent frontmatter contract, or wiring /agents commands"
sources:
  - path: plugins/agents/.claude-plugin/plugin.json
    blob: 8fa7bcc60a0b4c3dd5f7c74cb556a69f1a97a76d
  - path: plugins/agents/bin/validate-agents.sh
    blob: ce55f55b8ac86af01f2fde7f9cad4ee9e6f7c9f6
  - path: plugins/agents/skills/agents/SKILL.md
    blob: a124fbbf7f5ad088ee35819abd2a57d151497678
references_modules: [plugins-agents-agents-chunk-1, plugins-agents-agents-chunk-2, plugins-agents-agents-chunk-3, plugins-agents-agents-ux, plugins-agents-references]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/agents (misc)

## Purpose

Operational shell for the shared agent library: plugin manifest, `/agents` skill, and validator.
Agent definitions are data; this module is the machinery that publishes and polices them.
Remove it and the library is uninstallable and its frontmatter contract goes unenforced.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `agents` | plugin manifest | `plugins/agents/.claude-plugin/plugin.json:2` | Declares the `agents` plugin; description is the marketplace-facing summary of the library |
| `agents` | skill | `plugins/agents/skills/agents/SKILL.md:2` | User entry `/agents`; routes `list`, `describe <name>`, and `validate` subcommands |
| `validate-agents.sh` | bash script | `plugins/agents/bin/validate-agents.sh:2` | Structural gate for agent definitions; run from repo root; exits 1 on any failed check |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `AGENTS_DIR` | variable | `plugins/agents/bin/validate-agents.sh:7` | Scan root (`plugins/agents/agents`) — the validator's whole scope in one assignment |
| `ERRORS` | variable | `plugins/agents/bin/validate-agents.sh:8` | Failure accumulator; non-zero forces exit 1 at `plugins/agents/bin/validate-agents.sh:139` |
| `SEEN_NAMES` | variable | `plugins/agents/bin/validate-agents.sh:29` | Newline-separated registry behind the duplicate-name check; bash-3.2-safe by design |
| `fail` | function | `plugins/agents/bin/validate-agents.sh:15` | Sole `ERRORS` increment; every fatal check funnels through it |
| `yellow` | function | `plugins/agents/bin/validate-agents.sh:13` | WARN channel — prints without touching `ERRORS`, so warn checks never fail the run |

## Relationships

- `plugins-agents-misc.agents -> plugins-agents-misc.validate-agents.sh (calls)`
- `plugins-agents-misc.agents -> plugins-agents-references.agent-catalog.md (reads)`
- `plugins-agents-misc.validate-agents.sh -> plugins-agents-agents-chunk-1.api-designer (reads)`
- `plugins-agents-misc.validate-agents.sh -> plugins-agents-agents-chunk-2.investigator (reads)`
- `plugins-agents-misc.validate-agents.sh -> plugins-agents-agents-chunk-3.triager (reads)`
- `plugins-agents-misc.validate-agents.sh -> plugins-agents-agents-ux.ux-designer-cli (reads)`

## Type notes

The validator globs every `plugins/agents/agents/*.md` (plugins/agents/bin/validate-agents.sh:31).
Chunk edges above name one representative each; the scan covers the whole agent library.
`/agents describe <name>` reads agent files directly, per plugins/agents/skills/agents/SKILL.md:19.
The required-field check at plugins/agents/bin/validate-agents.sh:52 makes missing fields fatal.
Fields: name, description, tools, color, tier, read_only, tags.
`read_only: true` forbids Write/Edit in tools (plugins/agents/bin/validate-agents.sh:78).
Also fatal: name=filename, unique names, `<role>` tags, Guardrails, Mandatory Initial Read.
Missing Anti-Patterns or Output Format only warns (plugins/agents/bin/validate-agents.sh:113).
Underscore-prefixed files are skipped, not validated (plugins/agents/bin/validate-agents.sh:35).

## External deps

- bash — kept bash-3.2 compatible (macOS system bash); runs under `set -euo pipefail`
- BSD/GNU text tools — grep, sed, head, basename via portable flags only

## Gotchas

- No associative arrays: macOS ships bash 3.2 (comment at plugins/agents/bin/validate-agents.sh:28).
- `head -n -1` is avoided as GNU-only (comment at plugins/agents/bin/validate-agents.sh:49).
- The opening `---` must be line 1 of an agent file (plugins/agents/bin/validate-agents.sh:42).
- The check summary at plugins/agents/skills/agents/SKILL.md:25 is a subset; trust the script.
