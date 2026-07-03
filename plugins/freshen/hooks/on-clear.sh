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

# F052 (cross-plugin ordering hazard): hook-guard's own SessionStart(clear)
# hook (a different plugin, unordered relative to this one per CLAUDE.md's
# "Hook ordering" section) also reads .clear-pending, to decide whether this
# /clear was freshen-initiated (skip resetting its breaker) or a bare user
# /clear (reset it). If we deleted .clear-pending outright and hook-guard's
# hook happened to run AFTER us in the same batch, it would find nothing,
# conclude this was a bare user /clear, and wrongly reset the breaker —
# reintroducing the exact runaway-loop bug F052 fixed, but only under this
# specific (undocumented-as-safe) ordering.
#
# Fix: hand the flag off instead of destroying it. Every path below that used
# to `rm -f .clear-pending` now renames it to .clear-consumed instead. That
# preserves the "this /clear was freshen-initiated" fact regardless of which
# hook runs first:
#   - hook-guard first:  sees .clear-pending (we haven't touched it yet). We
#     still rename it to .clear-consumed afterward (unconditionally, below) --
#     that write has no reader in THIS event once hook-guard has already run,
#     so it necessarily outlives this SessionStart(clear) event as a leftover
#     file. hook-guard is the sole reader/deleter of .clear-consumed and
#     bounds how long it trusts a marker it didn't just create itself (a
#     short freshness window on its mtime -- see the "Residual regression"
#     comment in hook-guard's hooks/session-start.sh) precisely to keep that
#     leftover from being misread as live evidence by a later, unrelated
#     SessionStart(clear) event.
#   - this script first: renames it to .clear-consumed; hook-guard then finds
#     .clear-consumed instead (still fresh) and treats it identically.
consume_clear_pending() {
  [ -f "$FRESHEN_DIR/.clear-pending" ] && mv -f "$FRESHEN_DIR/.clear-pending" "$FRESHEN_DIR/.clear-consumed"
  return 0
}

# Find the oldest signal file (by modification time)
SIGNAL=$(ls -tr "$FRESHEN_DIR"/*.signal 2>/dev/null | head -1) || true
[ -n "$SIGNAL" ] || { consume_clear_pending; exit 0; }

COMMAND=$(head -1 "$SIGNAL")
SUMMARY=$(tail -n +2 "$SIGNAL" 2>/dev/null || true)

# Display progress summary if present
if [ -n "$SUMMARY" ]; then
  echo "freshen: $SUMMARY"
fi

# tmux is required
[ -n "${TMUX:-}" ] || { consume_clear_pending; exit 0; }
[ -n "${TMUX_PANE:-}" ] || { consume_clear_pending; exit 0; }

# Send the re-invocation command (literal mode to avoid key interpretation)
if tmux send-keys -t "$TMUX_PANE" -l "$COMMAND"; then
  tmux send-keys -t "$TMUX_PANE" Enter
  rm "$SIGNAL"
fi

# Hand off the clear-pending flag (see consume_clear_pending above).
consume_clear_pending
