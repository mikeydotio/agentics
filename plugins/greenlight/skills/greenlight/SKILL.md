---
name: greenlight
description: Manage the greenlight pre-tool-use safety hook. Control permission mode behavior, analysis settings, allowlists/blocklists, and test commands.
model: sonnet
effort: medium
---

# Greenlight — Safety Hook Manager

Greenlight evaluates every tool call for safety before execution. It auto-allows known readonly commands, warns on destructive commands, and uses Claude AI as a fallback for uncertain ones. It is permission-mode-aware and can be selectively enabled/disabled per mode.

## Configuration and routing

The optional `~/.config/greenlight/config.yaml` contains explicit overrides in flat
`key: value` format. Missing keys inherit the current bundled defaults on every
invocation. Reading configuration never creates a file. Do not copy bundled defaults
into the user file or manufacture an inline default snapshot.

Resolve the installed plugin root from `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, or
this skill's package location when neither is available. Run its management helper
with safely quoted arguments:

```bash
bash "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/bin/greenlight-config.sh" status
```

| `/greenlight` arguments | Helper arguments / action |
|---|---|
| `status` or empty | `status` |
| `enable <mode>` | `remove disabled_modes <mode>` |
| `disable <mode>` | `add disabled_modes <mode>` |
| `mode <value>` | `set mode <value>` |
| `ai on` / `ai off` | `set ai_enabled true` / `set ai_enabled false` |
| `model <name>` | `set ai_model <name>` |
| `allow <cmd>` / `unallow <cmd>` | `add custom_allow <cmd>` / `remove custom_allow <cmd>` |
| `block <cmd>` / `unblock <cmd>` | `add custom_pass <cmd>` / `remove custom_pass <cmd>` |
| `unset <key>...` | `unset <key>...` |
| `reset` | `reset` |
| `explore <task>` | Explorer launcher below |
| `test <command>` | Hook replay below |
| `log` / `log clear` | Effective log path, below |

Only report a mutation as successful after exit 0 and `ok:true`. Exit 2 is an
argument error; exit 1 is an operational error. Show contextual stderr on failure.
Do not retry a busy writer lock indefinitely or delete it automatically. An abandoned
`.config.lock` may be removed only after confirming its writer has stopped.

### Status

Display `.settings` as a table with each key's `value`, `default`, `source`, and
`pinned`. A pin equal to today's default still prevents future updates. An empty
scalar entry inherits (`source: bundled`) but remains `pinned: true` until removed.
Show enabled/disabled permission modes using effective `disabled_modes` and report
whether `ANTHROPIC_API_KEY` is set, never its value. Status requires no user file.

### Settings

Valid permission modes: `default`, `plan`, `acceptEdits`, `bypassPermissions`.
Analysis modes: `standard` (deterministic checks with optional AI), `strict` (no AI),
`permissive` (more lenient deterministic checks with optional AI). AI remains opt-in.
Before recommending an AI model, verify the provider's current structured-output
support; setting a name does not establish its availability.

The helper edits only requested overrides, preserving comments and unknown keys.
Lists start from their effective value, so enabling the last disabled mode writes
an explicit empty list. Explicit empty `disabled_modes`, `custom_allow`, `custom_pass`,
and `log_file` values clear those settings; empty scalar settings inherit defaults.
The format supports literal matching outer quotes, CRLF and a missing final newline;
it does not interpret shell expressions, YAML escapes, inline comments, nesting,
arrays, or multiline values. Duplicate or malformed recognized entries are errors.

### Migration and reset

Existing files remain explicit pins: their creation date and resemblance to an old
bundle cannot prove user intent. To adopt the corrected AI defaults while keeping
other customization:

```bash
bash "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/bin/greenlight-config.sh" unset ai_enabled ai_model ai_show_rationale
```

`reset` makes a unique adjacent backup (returned as `.backup`) and empties the user
file. Report the backup path. An absent file needs no backup. The result inherits
current and future bundled defaults; it is not a frozen copy. Invalid configuration
must be corrected before management mutations. Symlink configuration paths can be
read, but the helper refuses to mutate them; edit the intended target explicitly.

## Plan-Explorer Commands

### /greenlight explore <task>
Launch a **governed plan-mode explorer**: a headless Sonnet `claude -p` session
that researches the codebase autonomously inside a *disposable* git worktree.
The explorer runs in `dontAsk`, so the greenlight hook is its sole safety
arbiter — it may read, run safe commands, and experiment with edits **inside the
throwaway worktree**, but the hook hard-denies edits to the real tree and
destructive commands. The worktree and its `greenlight/scratch-*` branch are
removed when the explorer finishes; only the findings survive.

Dispatch to the launcher and report the findings it captured:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/greenlight-explore.sh run --task "<the task>"
# → prints JSON: {ok, findings, worktree, branch, model, kept}
```
Then read and summarize the file at `.findings`. Useful flags: `--model <name>`
(default from `plan_explorer_model`), `--out <file>` (write findings to a known
path — forge uses this to drop them into `.forge/research/`), `--keep` (leave
the worktree for debugging), `--base <ref>`, `--timeout <sec>`.

Requires an authenticated `claude` CLI and a git repo. Configure the policy via
the `plan_explorer_*` keys (see Config File above).

## Utility Commands

### /greenlight test <command>
Dry-run the hook against a command to see what decision it would make:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"<the command>"},"permission_mode":"default"}' | bash ${CLAUDE_PLUGIN_ROOT}/hooks/greenlight.sh
```
This sample uses Claude payload semantics: ALLOW (`permissionDecision=allow`),
context (`additionalContext`), or silent PASS (no output). To replay Codex, add a
`turn_id` key and invoke `bash "${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}/hooks/greenlight.sh"`.
Codex safe calls emit no output, or context only when AI rationale is enabled;
they retain normal host permission checks. Denials retain `deny` and a reason.
The decision log distinguishes a safe classification from silent deferral.

### /greenlight log and log clear

Use the helper's `get log_file` and check exit status before using the path. An empty
value means logging is disabled. Otherwise, show the last 20 lines with `tail -n 20 --
"<resolved path>"`; `log clear` truncates that exact file. Quote the path as data.
Do not read the raw user file: the log path may come from bundled defaults.

## Notes

- The hook re-reads config on every invocation — no restart needed.
- `ANTHROPIC_API_KEY` must be set as an environment variable for AI fallback. Not stored in config.
- Configuration failures defer normal sessions with diagnostics and deny tagged explorers.
- Greenlight supersedes the older `safe-readonly.sh` hook.
- **Scope**: Greenlight only evaluates Bash commands. Write and Edit tool calls are not intercepted — they go through Claude Code's built-in permission system.
