#!/usr/bin/env bash
set -euo pipefail
# freshen SessionStart(clear) hook — after /clear, process the oldest signal.
#
# Reads the signal file, sends the re-invocation command via tmux send-keys,
# then deletes the signal only on success.
#
# Every exit path must write to stderr to prevent Claude Code's "No stderr
# output" feedback from creating an infinite conversation loop.
trap '[ $? -eq 0 ] && echo "freshen: ok" >&2 || echo "freshen: error" >&2' EXIT

FRESHEN_DIR=".freshen"

# Directory must exist
[ -d "$FRESHEN_DIR" ] || exit 0

# Disabled — silently skip
[ -f "$FRESHEN_DIR/.disabled" ] && exit 0

# Only process if clear-pending flag exists (freshen-initiated clear).
# If missing, this was a user-initiated /clear — skip processing.
[ -f "$FRESHEN_DIR/.clear-pending" ] || exit 0

# Find the oldest signal file (by modification time)
SIGNAL=$(ls -tr "$FRESHEN_DIR"/*.signal 2>/dev/null | head -1)
[ -n "$SIGNAL" ] || { rm -f "$FRESHEN_DIR/.clear-pending"; exit 0; }

COMMAND=$(cat "$SIGNAL")

# tmux is required
[ -n "${TMUX:-}" ] || { rm -f "$FRESHEN_DIR/.clear-pending"; exit 0; }
[ -n "${TMUX_PANE:-}" ] || { rm -f "$FRESHEN_DIR/.clear-pending"; exit 0; }

# Send the re-invocation command (literal mode to avoid key interpretation)
if tmux send-keys -t "$TMUX_PANE" -l "$COMMAND"; then
  tmux send-keys -t "$TMUX_PANE" Enter
  rm "$SIGNAL"
fi

# Clean up the clear-pending flag
rm -f "$FRESHEN_DIR/.clear-pending"
