#!/usr/bin/env bash
set -euo pipefail
# freshen Stop hook — if a signal file exists, send /clear via tmux, with a
# bounded capture-pane read-back to confirm it actually landed before
# committing to the durable .clear-pending state on-clear.sh (and
# hook-guard's breaker) key off of (F045, F041).
#
# The keys buffer in tmux until the prompt appears, so no sleep is needed to
# get the keys delivered; the (separate, bounded) sleep loop lives in
# lib/pane-confirm.sh's post-send confirmation poll. The post-clear hook
# (on-clear.sh) handles the re-invocation.
#
# Every exit path must write to stderr. Claude Code reports "No stderr output"
# as conversation feedback when a hook exits silently, which creates an infinite
# loop: feedback → Claude responds → stop event → hook fires → feedback → ...
trap '[ $? -eq 0 ] && echo "freshen: ok" >&2 || echo "freshen: error" >&2' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Circuit breaker — prevent stop hook infinite loops
_GUARD_LIB="${PLUGIN_ROOT}/../hook-guard/lib/stop-guard.sh"
# shellcheck source=plugins/hook-guard/lib/stop-guard.sh
[ -f "$_GUARD_LIB" ] && . "$_GUARD_LIB" && stop_guard_check || true

# F045/F041: capture-pane confirm/retry, and F047's transition audit log.
# shellcheck source=plugins/freshen/lib/pane-confirm.sh
. "${PLUGIN_ROOT}/lib/pane-confirm.sh"
# shellcheck source=plugins/freshen/lib/transition-log.sh
. "${PLUGIN_ROOT}/lib/transition-log.sh"

FRESHEN_DIR=".freshen"

# Directory must exist
[ -d "$FRESHEN_DIR" ] || exit 0

# Disabled — silently skip
[ -f "$FRESHEN_DIR/.disabled" ] && exit 0

# Delete stale signals (older than 2 hours)
find "$FRESHEN_DIR" -name '*.signal' -mmin +120 -delete 2>/dev/null || true

# Any signal files pending?
SIGNAL=$(ls "$FRESHEN_DIR"/*.signal 2>/dev/null | head -1) || true
[ -n "$SIGNAL" ] || exit 0
SIGNAL_SOURCE="$(basename "$SIGNAL" .signal)"

# Another Stop hook in this same batch may already have sent (and confirmed)
# /clear for this signal (forge's session-stop.sh does this itself rather
# than depending on hook ordering — see its comments). .clear-pending is the
# single "a /clear has already been sent for this Stop event" marker; if
# it's already set, sending a second /clear would double up in the tmux
# pane. Leave the signal in place — on-clear.sh still consumes it normally
# once the pending clear actually lands.
[ -f "$FRESHEN_DIR/.clear-pending" ] && exit 0

# tmux is required — if not available, leave the signal for manual handling
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

# F045/F041: send /clear and confirm (bounded poll + resend, see
# lib/pane-confirm.sh) that it actually left the input line -- was accepted,
# not just typed -- before treating the clear as done. Only on confirmed
# success do we set .clear-pending, the durable flag on-clear.sh and
# hook-guard's breaker-skip both key off of. This is safe to gate on
# confirmation rather than setting it unconditionally up front (the old
# behavior): Stop hooks in the same batch run sequentially, so this entire
# script -- including the confirm/resend loop below -- always finishes
# before any other plugin's Stop hook in the same batch starts. There is no
# new race window from waiting to set .clear-pending until confirmed; the
# only change in behavior is that a send which is never confirmed no longer
# marks .clear-pending at all, leaving the signal for the next Stop event to
# retry from scratch instead of silently considering the clear "done".
freshen_log_transition "on-stop: found pending signal from '${SIGNAL_SOURCE}' -- sending /clear"
if pane_send_and_confirm "$TMUX_PANE" keys "/clear"; then
  touch "$FRESHEN_DIR/.clear-pending"
  freshen_log_transition "on-stop: /clear confirmed accepted"
else
  echo "freshen: WARNING /clear send unconfirmed after retries -- leaving signal '${SIGNAL_SOURCE}.signal' for the next Stop event to retry" >&2
  freshen_log_transition "on-stop: /clear unconfirmed after retries -- NOT marking clear-pending, signal remains for retry"
fi
