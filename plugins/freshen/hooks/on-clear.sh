#!/usr/bin/env bash
set -euo pipefail
# freshen SessionStart(clear) hook — after /clear, process the oldest signal.
#
# Reads the signal file, sends the re-invocation command via tmux send-keys
# with a capture-pane read-back to confirm it was actually accepted (not
# just typed into a possibly-wrong pane state), then deletes the signal only
# once confirmed (F056, F041). Bounded retry on failure to confirm; if still
# unconfirmed after every attempt, the signal is left in place for the next
# freshen cycle to retry rather than retried indefinitely here.
#
# Every exit path must write to stderr to prevent Claude Code's "No stderr
# output" feedback from creating an infinite conversation loop.
trap '[ $? -eq 0 ] && echo "freshen: ok" >&2 || echo "freshen: error" >&2' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# F056/F041: capture-pane confirm/retry, and F047's transition audit log.
# shellcheck source=plugins/freshen/lib/pane-confirm.sh
. "${PLUGIN_ROOT}/lib/pane-confirm.sh"
# shellcheck source=plugins/freshen/lib/transition-log.sh
. "${PLUGIN_ROOT}/lib/transition-log.sh"

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

# F056/F041: only delete the signal once BOTH send-keys calls have succeeded
# AND a capture-pane read-back confirms the command actually left the input
# line (was accepted) -- not merely that the literal-text send returned 0
# (the old bug: `rm` was gated only on the FIRST of the two send-keys calls,
# so a failing Enter still deleted the signal with the command sitting
# typed-but-unsubmitted). Bounded retry on failure to confirm (literal mode
# requires both sends to succeed).
#
# If still unconfirmed after every attempt, the signal is deliberately left
# in place rather than retried indefinitely here: a future Stop -> on-stop.sh
# cycle will re-detect the same still-pending signal and try a fresh
# /clear + re-invoke from scratch.
freshen_log_transition "on-clear: sending re-invoke '${COMMAND}'"
if pane_send_and_confirm "$TMUX_PANE" literal "$COMMAND"; then
  rm "$SIGNAL"
  freshen_log_transition "on-clear: re-invoke confirmed accepted, signal consumed"
else
  echo "freshen: WARNING re-invoke command unconfirmed after retries -- leaving signal '$(basename "$SIGNAL")' for the next freshen cycle" >&2
  freshen_log_transition "on-clear: re-invoke unconfirmed after retries -- signal left in place for retry"
fi

# Hand off the clear-pending flag (see consume_clear_pending above). This
# runs unconditionally regardless of the re-invoke outcome above -- F052's
# cross-plugin ordering fix depends on it firing every time a /clear was
# freshen-initiated, independent of whether the re-invoke command itself was
# ultimately confirmed.
consume_clear_pending
