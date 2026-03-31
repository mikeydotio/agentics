#!/usr/bin/env bash
# freshen SessionStart(clear) hook — after /clear, process the oldest signal.
#
# Reads the signal file, deletes it, and sends the re-invocation command
# via tmux send-keys. The keys buffer until the prompt accepts input.

FRESHEN_DIR=".freshen"

# Find the oldest signal file (by modification time)
SIGNAL=$(ls -tr "$FRESHEN_DIR"/*.signal 2>/dev/null | head -1)
[ -n "$SIGNAL" ] || exit 0

COMMAND=$(cat "$SIGNAL")
SOURCE=$(basename "$SIGNAL" .signal)

# Nuke the signal BEFORE sending keys — prevents re-triggering
rm "$SIGNAL"

# tmux is required — if not available, the signal is already nuked so we just lose it
# (this shouldn't happen: freshen.sh queue validates tmux at registration time)
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

# Send the re-invocation command
tmux send-keys -t "$TMUX_PANE" "$COMMAND" Enter
