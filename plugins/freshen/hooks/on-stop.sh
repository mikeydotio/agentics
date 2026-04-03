#!/usr/bin/env bash
set -euo pipefail
# freshen Stop hook — if a signal file exists, send /clear via tmux.
#
# The keys buffer in tmux until the prompt appears, so no sleep is needed.
# The post-clear hook (on-clear.sh) handles the re-invocation.
#
# Every exit path must write to stderr. Claude Code reports "No stderr output"
# as conversation feedback when a hook exits silently, which creates an infinite
# loop: feedback → Claude responds → stop event → hook fires → feedback → ...
trap '[ $? -eq 0 ] && echo "freshen: ok" >&2 || echo "freshen: error" >&2' EXIT

FRESHEN_DIR=".freshen"

# Directory must exist
[ -d "$FRESHEN_DIR" ] || exit 0

# Disabled — silently skip
[ -f "$FRESHEN_DIR/.disabled" ] && exit 0

# Delete stale signals (older than 2 hours)
find "$FRESHEN_DIR" -name '*.signal' -mmin +120 -delete 2>/dev/null || true

# Any signal files pending?
SIGNAL=$(ls "$FRESHEN_DIR"/*.signal 2>/dev/null | head -1)
[ -n "$SIGNAL" ] || exit 0

# tmux is required — if not available, leave the signal for manual handling
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

# Set clear-pending flag so on-clear.sh knows this was freshen-initiated
touch "$FRESHEN_DIR/.clear-pending"

# Send /clear — fail-fast if send-keys fails (no retry)
tmux send-keys -t "$TMUX_PANE" "/clear" Enter
