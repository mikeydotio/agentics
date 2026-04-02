---
name: greenlight
description: Manage the greenlight pre-tool-use safety hook. Control permission mode behavior, analysis settings, allowlists/blocklists, and test commands.
---

# Greenlight — Safety Hook Manager

Greenlight evaluates every tool call for safety before execution. It auto-allows known readonly commands, warns on destructive commands, and uses Claude AI as a fallback for uncertain ones. It is permission-mode-aware and can be selectively enabled/disabled per mode.

## Config File

`~/.config/greenlight/config.yaml` — strict `key: value` flat format (no nesting, no arrays, no multi-line values). Changes take effect immediately — the hook re-reads on every invocation.

## Command Router

Parse the ARGUMENTS after `/greenlight` to determine the action:

| Argument | Action |
|----------|--------|
| `status` or empty | Show current configuration |
| `enable <mode>` | Enable greenlight in a permission mode |
| `disable <mode>` | Disable greenlight in a permission mode |
| `mode <value>` | Change analysis mode |
| `ai <on\|off>` | Toggle AI fallback |
| `model <name>` | Change AI model |
| `allow <cmd>` | Add command to always-allow list |
| `block <cmd>` | Add command to always-pass (block) list |
| `unallow <cmd>` | Remove command from always-allow list |
| `unblock <cmd>` | Remove command from always-pass list |
| `test <command>` | Dry-run a command through the hook |
| `log` | Show recent log entries |
| `log clear` | Clear the log file |
| `reset` | Restore default configuration |

## Permission Mode Commands

Claude Code has four permission modes: `default` (normal), `plan`, `acceptEdits`, and `bypassPermissions`. Greenlight can be enabled or disabled per mode.

**By default, greenlight is enabled in all modes except `bypassPermissions`.**

### /greenlight enable <mode>
Enable greenlight in the given permission mode by removing it from the `disabled_modes` list.

Valid modes: `default`, `plan`, `acceptEdits`, `bypassPermissions`

```bash
# Read current disabled modes
current=$(grep '^disabled_modes:' ~/.config/greenlight/config.yaml | sed 's/^disabled_modes: *//')
# Remove the mode from the list
updated=$(echo "$current" | tr ' ' '\n' | grep -v "^<mode>$" | tr '\n' ' ' | sed 's/ *$//')
# Write back
sed -i "s/^disabled_modes: .*/disabled_modes: ${updated}/" ~/.config/greenlight/config.yaml
```

Report the change: "Greenlight is now **enabled** in `<mode>` mode."

### /greenlight disable <mode>
Disable greenlight in the given permission mode by adding it to the `disabled_modes` list.

```bash
current=$(grep '^disabled_modes:' ~/.config/greenlight/config.yaml | sed 's/^disabled_modes: *//')
# Only add if not already present
if ! echo " $current " | grep -q " <mode> "; then
  updated="${current} <mode>"
  updated=$(echo "$updated" | sed 's/^ *//')
  sed -i "s/^disabled_modes: .*/disabled_modes: ${updated}/" ~/.config/greenlight/config.yaml
fi
```

Report the change: "Greenlight is now **disabled** in `<mode>` mode."

### /greenlight status
Read and display `~/.config/greenlight/config.yaml`. Format as a table showing each setting and its current value. Also:
- Check whether `ANTHROPIC_API_KEY` is set (report set/unset, never show the key)
- Show which permission modes greenlight is active/disabled in:
  - Read `disabled_modes` from config
  - For each of `default`, `plan`, `acceptEdits`, `bypassPermissions`: show enabled/disabled

## Analysis Mode Commands

### /greenlight mode <standard|strict|permissive>
Change the analysis mode:
- **standard**: Deterministic allow/pass for known commands. AI fallback for uncertain commands.
- **strict**: No AI. Everything uncertain passes to user for manual approval.
- **permissive**: More lenient deterministic checks. AI fallback for the rest.

```bash
sed -i 's/^mode: .*/mode: <value>/' ~/.config/greenlight/config.yaml
```

### /greenlight ai <on|off>
Enable or disable AI fallback:
```bash
sed -i 's/^ai_enabled: .*/ai_enabled: <true|false>/' ~/.config/greenlight/config.yaml
```

### /greenlight model <model-name>
Change the AI model for fallback analysis:
```bash
sed -i 's/^ai_model: .*/ai_model: <value>/' ~/.config/greenlight/config.yaml
```
Valid models: `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`, `claude-opus-4-6`

## Allow/Block Commands

### /greenlight allow <command-name>
Add a command to the custom always-allow list. Read current `custom_allow`, append the command, write back:
```bash
current=$(grep '^custom_allow:' ~/.config/greenlight/config.yaml | sed 's/^custom_allow: *//')
sed -i "s/^custom_allow: .*/custom_allow: ${current} <command-name>/" ~/.config/greenlight/config.yaml
```

### /greenlight block <command-name>
Same as `allow` but for the `custom_pass` key. Commands on this list always pass to user for confirmation.

### /greenlight unallow <command-name>
Remove a command from the `custom_allow` list.

### /greenlight unblock <command-name>
Remove a command from the `custom_pass` list.

## Utility Commands

### /greenlight test <command>
Dry-run the hook against a command to see what decision it would make:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"<the command>"},"permission_mode":"default"}' | bash ${CLAUDE_PLUGIN_ROOT}/hooks/greenlight.sh
```
Display the JSON output and interpret: ALLOW (permissionDecision=allow), PASS with warning (additionalContext present), or silent PASS (no output).

### /greenlight log
Show the last 20 lines of the log file (if enabled):
```bash
tail -20 "$(grep '^log_file:' ~/.config/greenlight/config.yaml | sed 's/^log_file: *//')"
```
If `log_file` is empty, report that logging is disabled and offer to enable it.

### /greenlight log clear
Truncate the log file.

### /greenlight reset
Restore default configuration by copying from the plugin's bundled default:
```bash
cp "${CLAUDE_PLUGIN_ROOT}/references/default-config.yaml" ~/.config/greenlight/config.yaml
```
If `CLAUDE_PLUGIN_ROOT` is not available, write the defaults inline:
```bash
cat > ~/.config/greenlight/config.yaml << 'EOF'
disabled_modes: bypassPermissions
mode: standard
ai_enabled: true
ai_model: claude-sonnet-4-6
ai_timeout: 10
ai_show_rationale: true
custom_allow:
custom_pass:
log_file:
verbose: false
EOF
```

## Notes

- The hook re-reads config on every invocation — no restart needed.
- `ANTHROPIC_API_KEY` must be set as an environment variable for AI fallback. Not stored in config.
- The hook never blocks tool execution on failure. Worst case: defers to user.
- Greenlight supersedes the older `safe-readonly.sh` hook.
- **Scope**: Greenlight only evaluates Bash commands. Write and Edit tool calls are not intercepted — they go through Claude Code's built-in permission system.
