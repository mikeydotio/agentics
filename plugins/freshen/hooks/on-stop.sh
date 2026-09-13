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
CLEAR_COMMAND="${FRESHEN_CLEAR_COMMAND:-/clear}"

# Directory must exist
[ -d "$FRESHEN_DIR" ] || exit 0

# Disabled — silently skip
[ -f "$FRESHEN_DIR/.disabled" ] && exit 0

# AGE-100: acceptance is not execution. A /clear which never executes cannot
# consume its marker, so deduplication must expire on a later eligible Stop.
# Check even without a signal: another hook may queue one later in this batch.
if [ -f "$FRESHEN_DIR/.clear-pending" ]; then
  CLEAR_PENDING_TTL=120
  if ! PENDING_MTIME="$(stat -c%Y "$FRESHEN_DIR/.clear-pending" 2>/dev/null \
    || stat -f%m "$FRESHEN_DIR/.clear-pending")"; then
    PENDING_MTIME=""
  fi
  if ! NOW_TS="$(date +%s)"; then
    NOW_TS=""
  fi

  # on-clear may have consumed the marker while metadata was being read.
  if [ -f "$FRESHEN_DIR/.clear-pending" ]; then
    # Canonical decimal seconds only; bound the width before Bash arithmetic
    # so malformed utility output cannot wrap, use octal, or become shell math.
    if ! [[ "$PENDING_MTIME" =~ ^(0|-?[1-9][0-9]{0,11})$ \
      && "$NOW_TS" =~ ^(0|-?[1-9][0-9]{0,11})$ ]]; then
      echo "freshen: WARNING cannot determine age of $FRESHEN_DIR/.clear-pending (stat/date timestamp unavailable or invalid) -- retaining marker; no clear sent" >&2
      exit 0
    fi
    PENDING_AGE=$((NOW_TS - PENDING_MTIME))
    if [ "$PENDING_AGE" -ge "$CLEAR_PENDING_TTL" ]; then
      if ! rm -f "$FRESHEN_DIR/.clear-pending"; then
        echo "freshen: ERROR failed to remove $FRESHEN_DIR/.clear-pending (age ${PENDING_AGE}s, threshold ${CLEAR_PENDING_TTL}s) -- no clear sent" >&2
        exit 1
      fi
      echo "freshen: WARNING expired .clear-pending (age ${PENDING_AGE}s, threshold ${CLEAR_PENDING_TTL}s) -- allowing queued signal retry" >&2
      freshen_log_transition "on-stop: expired .clear-pending (age ${PENDING_AGE}s, threshold ${CLEAR_PENDING_TTL}s) -- allowing queued signal retry"
    fi
  fi
fi

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
freshen_log_transition "on-stop: found pending signal from '${SIGNAL_SOURCE}' -- sending ${CLEAR_COMMAND}"
if pane_send_and_confirm "$TMUX_PANE" keys "$CLEAR_COMMAND"; then
  touch "$FRESHEN_DIR/.clear-pending"
  freshen_log_transition "on-stop: ${CLEAR_COMMAND} confirmed accepted"
else
  echo "freshen: WARNING ${CLEAR_COMMAND} send unconfirmed after retries -- leaving signal '${SIGNAL_SOURCE}.signal' for the next Stop event to retry" >&2
  freshen_log_transition "on-stop: ${CLEAR_COMMAND} unconfirmed after retries -- NOT marking clear-pending, signal remains for retry"
fi
