# greenlight

Intelligent PreToolUse safety hook for Claude Code. Evaluates every tool call using a three-tier decision pipeline:

1. **Deterministic ALLOW** — 150+ known-safe readonly commands, plus deep subcommand analysis for git, gh, docker, kubectl, terraform, aws, gcloud, npm, and more (including a fast path for an autonomous forge-style inner loop: `story`, `git add/commit/checkout`, `cargo|npm|go test/build`, `make test`)
2. **Deterministic PASS with warning** — Known-destructive commands (`rm`, `sudo`, `kill`, `chmod`, etc.) surface clear `[greenlight]` warnings
3. **AI Fallback (opt-in)** — Uncertain commands evaluated by Claude Haiku via structured API call; off by default (`ai_enabled: false`) since it sits on the critical path of any autonomous loop

## Permission Mode Awareness

Greenlight auto-disables in **Bypass Permissions** mode and stays active in all other modes. Configurable per-mode via `/greenlight enable|disable <mode>`.

| Mode | Default |
|------|---------|
| Normal (default) | Enabled |
| Plan Mode | Enabled |
| Accept Edits | Enabled |
| Bypass Permissions | Disabled |

## Configuration

Config at `~/.config/greenlight/config.yaml` (auto-initialized on first run from bundled defaults).

| Setting | Default | Description |
|---------|---------|-------------|
| `disabled_modes` | `bypassPermissions` | Space-separated modes to disable in |
| `mode` | `standard` | `standard` / `strict` / `permissive` |
| `ai_enabled` | `false` | Claude API fallback for uncertain commands — opt-in |
| `ai_model` | `claude-haiku-4-5` | Model for AI evaluation (must support structured outputs) |
| `ai_timeout` | `10` | API call timeout (seconds) |
| `ai_show_rationale` | `false` | Inject the AI's rationale into context when it approves a command |
| `custom_allow` | _(empty)_ | Space-separated commands to always allow |
| `custom_pass` | _(empty)_ | Space-separated commands to always pass |

## Management

Use `/greenlight` to manage at runtime:

```
/greenlight status                   Show config and mode status
/greenlight enable <mode>            Enable in a permission mode
/greenlight disable <mode>           Disable in a permission mode
/greenlight mode strict              Change analysis mode
/greenlight ai off                   Disable AI fallback
/greenlight allow make               Always allow 'make'
/greenlight block terraform          Always pass 'terraform' to user
/greenlight test "curl -s ..."       Dry-run through the hook
/greenlight reset                    Restore defaults
```

## AI Fallback

Opt-in — run `/greenlight ai on` (or set `ai_enabled: true`) to turn it on. Set `ANTHROPIC_API_KEY` in your environment. When enabled and a command is uncertain, greenlight calls the configured model (`claude-haiku-4-5` by default — must be a structured-outputs-capable model) with a structured prompt asking "Is this command potentially destructive?" and gets `{answer: boolean, rationale: string}` back. The rationale is only shown to the user when `ai_show_rationale: true`.

## Requirements

- `jq` (JSON parsing)
- `curl` (AI fallback API calls)
- `ANTHROPIC_API_KEY` environment variable (for AI fallback; optional)
