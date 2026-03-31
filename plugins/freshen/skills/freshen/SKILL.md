---
name: freshen
description: Manage automatic context clearing — queue a /clear + re-invocation, check status, or cancel pending signals. Requires tmux.
argument-hint: queue <command> --source <name> | status | cancel [--source <name> | --all]
---

# Freshen: Automatic Context Clearing

You manage the freshen signal queue. Freshen lets plugins automatically clear context and re-invoke a command between workflow phases, using tmux send-keys.

## How It Works

1. A plugin calls `freshen.sh queue "/some-command" --source plugin-name`
2. This creates `.freshen/plugin-name.signal` containing the command
3. When Claude's turn ends, the **Stop hook** detects the signal and sends `/clear` via tmux
4. After the clear, the **SessionStart(clear) hook** reads the signal, deletes it, and sends the re-invocation command via tmux

**Requires tmux.** The `queue` command fails with an error if Claude is not running inside a tmux session.

## Command Router

Parse the ARGUMENTS to determine the subcommand:

| Argument | Action |
|----------|--------|
| `queue <cmd> --source <name>` | Register a post-clear re-invocation signal |
| `status` | Show pending signals |
| `cancel --source <name>` | Cancel a specific signal |
| `cancel --all` | Cancel all pending signals |
| (empty or help) | Show usage |

## Executing Commands

All commands delegate to the CLI script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/freshen.sh <subcommand> [args]
```

Report the output to the user.

## For Plugin Authors

To use freshen from another plugin's skill, have the orchestrator run:

```bash
bash plugins/freshen/bin/freshen.sh queue "<command>" --source "<your-plugin-name>"
```

Then STOP (return from the skill). The freshen hooks handle `/clear` and re-invocation automatically.

**Requirements:**
- Claude must be running inside tmux (hard requirement — fails with error otherwise)
- The `.freshen/` directory is gitignored and ephemeral
- Signal files are consumed once and deleted — no stale state
- Multiple sources can coexist, but only one is processed per clear cycle (oldest first)
