#!/usr/bin/env bash
# freshen Stop hook — if a signal file exists, send /clear via tmux.
#
# The keys buffer in tmux until the prompt appears, so no sleep is needed.
# The post-clear hook (on-clear.sh) handles the re-invocation.

FRESHEN_DIR=".freshen"

# Any signal files pending?
SIGNAL=$(ls "$FRESHEN_DIR"/*.signal 2>/dev/null | head -1)
[ -n "$SIGNAL" ] || exit 0

# tmux is required — if not available, leave the signal for manual handling
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

# Send /clear — keys buffer until the prompt accepts input
tmux send-keys -t "$TMUX_PANE" "/clear" Enter
