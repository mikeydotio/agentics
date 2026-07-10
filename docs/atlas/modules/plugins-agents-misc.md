---
module: "plugins/agents (misc)"
summary: "Plugin manifest, /agents command router, and structural validator for the shared agent library."
read_when: "Changing the /agents command, plugin manifest, or agent validation script"
sources:
  - path: plugins/agents/.claude-plugin/plugin.json
    blob: ebc64164f387e0b2c6d1eec3d0d804481c816632
  - path: plugins/agents/bin/validate-agents.sh
    blob: ce55f55b8ac86af01f2fde7f9cad4ee9e6f7c9f6
  - path: plugins/agents/skills/agents/SKILL.md
    blob: a124fbbf7f5ad088ee35819abd2a57d151497678
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/agents (misc)

## Purpose

This is the agents plugin's own housekeeping layer, not the agent definitions themselves: the plugin.json manifest that registers the shared library as an installable plugin (plugins/agents/.claude-plugin/plugin.json), the /agents skill that lets a user list, describe, or validate the catalog (plugins/agents/skills/agents/SKILL.md), and validate-agents.sh, the structural linter that enforces the shared agent frontmatter contract (required fields, name/filename match, no duplicate names, read-only/tool consistency) across plugins/agents/agents/. Without it the shared library would have no plugin identity, no user-facing entry point, and no automated guard against frontmatter drift in the agent definitions other plugins depend on.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- This module owns the plugin's identity, entry command, and lint tooling only — the agent definitions it validates and describes live in the sibling plugins/agents/agents/ directory, not here; validate-agents.sh sets AGENTS_DIR to that sibling path rather than owning the files itself (plugins/agents/bin/validate-agents.sh:7).
- Files in plugins/agents/agents/ named with a leading underscore (templates, shared guardrails) are structurally excluded from the per-agent checks, not just skipped by convention (plugins/agents/bin/validate-agents.sh:34-35).
- The frontmatter contract this module enforces requires exactly name, description, tools, color, tier, read_only, and tags on every non-underscore agent file (plugins/agents/bin/validate-agents.sh:52).
- read_only: true is a cross-checked invariant, not just documentation: the validator fails any read-only agent whose tools still lists Write or Edit (plugins/agents/bin/validate-agents.sh:74-86).

## External deps


## Gotchas

validate-agents.sh deliberately avoids two GNU/bash-4+ conveniences for macOS portability: it dedupes agent names with a newline-separated string instead of an associative array because macOS ships bash 3.2 (plugins/agents/bin/validate-agents.sh:28), and it strips the frontmatter's closing `---` with `sed '$d'` instead of `head -n -1`, which is GNU-only (plugins/agents/bin/validate-agents.sh:48).
