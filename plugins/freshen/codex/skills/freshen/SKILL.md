---
name: freshen
description: Manage automatic Codex context resets — queue a /new + re-invocation, check status, or cancel pending signals. Requires Codex CLI in tmux.
---

# Freshen: Automatic Context Reset

Freshen lets plugins continue multi-phase workflows in the Codex CLI by queueing a `/new` and a follow-up command through tmux.

## Hard rule

Never invoke `enable` or `disable` autonomously. Run them only when the user explicitly requests `$freshen:freshen enable` or `$freshen:freshen disable`; do not suggest them as recovery steps.

## Resolve the plugin

Resolve `<plugin-root>` as three directories above the directory containing this installed file. Substitute that absolute path in every bundled command below; never assume the current working directory is the plugin source checkout.

## Commands

Parse the arguments as one of:

| Argument | Action |
|---|---|
| `queue <cmd> --source <name> [--summary <text>]` | Register a post-reset re-invocation signal |
| `status` | Show pending signals |
| `cancel --source <name>` | Cancel a specific signal |
| `cancel --all` | Cancel all pending signals |
| `enable` | Re-enable Freshen; user-only |
| `disable` | Disable Freshen; user-only |
| empty or `help` | Show usage |

Delegate every command to the Codex adapter and report its output:

```bash
bash <plugin-root>/codex/bin/freshen.sh <subcommand> [args]
```

## Automatic continuation

Automatic continuation requires Codex CLI inside tmux with both `TMUX` and `TMUX_PANE` set. A queued transition works as follows:

1. The Codex `Stop` hook atomically claims the oldest signal into a journal, schedules a bounded worker, and returns valid hook JSON before the worker submits anything. Codex rejects `/new` while the `Stop` hook is still active.
2. The worker waits for a stable empty Codex input row, submits `/new` at most once, waits at least five seconds for the reset to settle, then submits a harmless nonce-bearing bootstrap prompt at most once.
3. Codex lazily emits `SessionStart(startup)` for the new thread when it accepts the bootstrap. That hook acknowledges the reset without consuming the signal; the bootstrap turn's `Stop` then schedules the claimed continuation.
4. The continuation is submitted at most once and remains recoverable in the journal until its own `Stop` event retires it. Failed or unconfirmed sends preserve the journal, and a same-source requeue remains a separate pending signal.

Transition decisions are recorded in `.freshen/transitions.log`.

In the IDE or desktop app, or when tmux is unavailable, do not queue an automatic transition. Preserve the workflow handoff, show the summary, and tell the user exactly: `After /new, run $<plugin>:<skill> <resume arguments>`.

## For plugin authors

Resolve the installed Freshen plugin root and run:

```bash
bash <freshen-plugin-root>/codex/bin/freshen.sh queue "<command>" --source "<plugin-name>" --summary "<progress text>"
```

Then stop the current skill turn. The hooks handle `/new` and re-invocation. Signal state under `.freshen/` is ephemeral and gitignored; cross-source conflicts are rejected so only one workflow owns an automatic transition at a time.
