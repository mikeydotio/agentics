---
name: agents
description: Browse and validate the shared agent library
argument-hint: "list | describe <name> | validate"
---

# Shared Agent Library

You manage the shared agent catalog at `plugins/agents/agents/`.

## Command Router

### `/agents list`

Read `plugins/agents/references/agent-catalog.md` and display the full roster grouped by tier (general-purpose, platform-variant, pipeline-specific). Include name, tools, read-only status, and tags.

### `/agents describe <name>`

Read `plugins/agents/agents/<name>.md` and display the full agent definition — frontmatter metadata and role instructions.

If the file doesn't exist, list available agents and suggest the closest match.

### `/agents validate`

Run `bash plugins/agents/bin/validate-agents.sh` and report results. The script checks:
- YAML frontmatter parses and has required fields
- Read-only agents don't list Write/Edit tools
- Agent names match filenames
- `<role>` tag exists in body
- Guardrails section exists

Report pass/fail per agent with details on any failures.
