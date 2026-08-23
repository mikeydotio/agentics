---
name: agents
description: Browse, validate, or run a specialist from the shared agent library in Codex.
---

# Shared Agent Library for Codex

## Codex interaction contract

Resolve `<plugin-root>` as three directories above this file's installed path. Substitute that
absolute path in every bundled command and file read. Do not assume the current working directory
is the agentics marketplace checkout.

Codex plugins do not register Claude's `agents/*.md` component or create project/user custom-agent
TOML files. This skill therefore runs a catalog role by injecting its full definition into a native
Codex subagent prompt. The role's tool, model, and effort frontmatter remains useful catalog
metadata, but it is not a Codex configuration layer: tool restrictions are prompt-enforced, and the
subagent inherits the active Codex model and reasoning effort.

## Commands

### `$agents:agents list`

Read `<plugin-root>/references/agent-catalog.md` and display the full roster grouped by tier.
Include each role's name, declared tools, read-only status, effort, and tags. Label the tool and
model declarations as Claude-native metadata; on Codex, the `run` command applies the role body
through native orchestration without claiming structural tool enforcement.

### `$agents:agents describe <name>`

Run `bash <plugin-root>/bin/resolve-agent.sh <name>`. On success, read and display the returned file
completely. On failure, show the resolver's error and use `--list` to suggest the closest valid
name. Never construct a role path directly from unvalidated user input.

### `$agents:agents validate`

Run `bash <plugin-root>/bin/validate-agents.sh` and report the pass/fail result. This validates the
canonical role definitions shared with Claude, including names, required frontmatter, read-only
metadata, role tags, guardrails, model policy, and effort values.

### `$agents:agents run <name> <task>`

Require both a catalog name and a concrete task, then:

1. Resolve the role with `bash <plugin-root>/bin/resolve-agent.sh <name>` and read the returned file
   completely. Stop if resolution fails.
2. Read `read_only:` from the validated file's frontmatter. If it is `true`, note the current
   worktree status before delegation and verify afterward that the role made no changes.
3. Call native `spawn_agent` with:
   - a task name derived from `agents_<name>`, replacing hyphens with underscores;
   - no model or reasoning-effort override, so the subagent inherits the active Codex settings;
   - a prompt containing, in order: the full canonical definition, the Codex execution contract
     below, and the user's concrete task.
4. Use `wait_agent` to collect the role's final result. If a prompt-enforced read-only role changed
   files, discard its result, identify the changed paths, and tell the user the boundary failed.
5. Return the role's result and state that it ran through the Codex prompt-adapter path. Do not
   claim that the catalog's Claude tool allowlist was structurally enforced.

Use this Codex execution contract in the delegated prompt:

```markdown
## Codex execution contract

The preceding canonical definition is your specialist role. Its YAML `tools`, `model`, and
`effort` fields describe the Claude-native registration and are not literal Codex tool names or
model overrides. Use only the Codex tools available in this spawned session. Obey `read_only: true`
as a strict no-write boundary. Complete only the task below, do not spawn further agents, and
return the role's requested output to the parent.

## Task

<user task>
```

If native subagent tools are unavailable, `list`, `describe`, and `validate` still work. For `run`,
stop and explain that this Codex surface cannot execute a specialist role; do not silently perform
the task in the parent or pretend an `agents:<name>` namespace exists.
