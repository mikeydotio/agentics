#!/usr/bin/env bash
# stop-guard.sh — Circuit breaker for Stop hooks.
#
# Source this file from any Stop hook, then call stop_guard_check.
# If too many stop events fire within a short window, the function
# prints a message to stderr and exits the calling script with 0.
#
# Usage (in a Stop hook):
#   _GUARD_LIB="${CLAUDE_PLUGIN_ROOT}/../hook-guard/lib/stop-guard.sh"
#   [ -f "$_GUARD_LIB" ] && . "$_GUARD_LIB" && stop_guard_check || true
#
# The state file lives in /tmp so the OS cleans it up. SessionStart
# hooks can also call stop_guard_reset to clear state explicitly.

_STOP_GUARD_WINDOW="${STOP_GUARD_WINDOW:-30}"
_STOP_GUARD_THRESHOLD="${STOP_GUARD_THRESHOLD:-4}"
# F048/F043: freshen's on-stop.sh AND forge's session-stop.sh both source
# this file and call stop_guard_check on the SAME Stop event, so a naive
# "append one tick per call" counts hook invocations, not Stop events --
# silently halving the configured threshold (and getting worse with every
# additional Stop hook a future plugin registers). There is no shared
# "this is the same Stop event" identifier available here: each hook runs in
# its own subprocess, and neither reads its stdin JSON before calling this
# function. Dedupe on wall-clock proximity instead: multiple hooks for one
# real Stop event run back-to-back in the same batch (same process turn,
# typically << 1s apart); genuinely distinct Stop events are always at least
# one full model round-trip apart (seconds). See stop_guard_check below.
_STOP_GUARD_DEDUP_WINDOW="${STOP_GUARD_DEDUP_WINDOW:-2}"

_stop_guard_file() {
  local project="${CLAUDE_PROJECT_DIR:-$PWD}"
  local hash
  hash=$(printf '%s' "$project" | md5sum 2>/dev/null | cut -c1-8)
  # F055: stock macOS ships no `md5sum`; fall back to BSD `md5` so the
  # breaker's project-hash key doesn't silently go empty (which would key
  # every project on this host to the same guard file).
  if [ -z "$hash" ]; then
    hash=$(printf '%s' "$project" | md5 2>/dev/null | cut -c1-8)
  fi
  if [ -z "$hash" ]; then
    echo "hook-guard: WARNING no md5sum/md5 available -- using unhashed project path for guard key" >&2
    hash=$(printf '%s' "$project" | tr -c 'A-Za-z0-9' '_' | cut -c1-40)
  fi
  echo "/tmp/claude-stop-guard-${USER:-uid$(id -u)}-${hash}"
}

stop_guard_check() {
  local guard_file now count cutoff window threshold last_ts
  guard_file="$(_stop_guard_file)"
  now=$(date +%s)
  window="${1:-$_STOP_GUARD_WINDOW}"
  threshold="${2:-$_STOP_GUARD_THRESHOLD}"
  cutoff=$((now - window))

  # F048/F043: if the most recent recorded tick is within the dedup window,
  # this call is (almost certainly) a second hook firing for the SAME Stop
  # event as the one that just ticked -- skip appending a new entry (the
  # threshold check below still runs against what's already recorded).
  last_ts=""
  [ -f "$guard_file" ] && last_ts="$(tail -1 "$guard_file" 2>/dev/null)"
  if [ -n "$last_ts" ] && [ "$last_ts" -ge $((now - _STOP_GUARD_DEDUP_WINDOW)) ] 2>/dev/null; then
    : # duplicate hook call for the same Stop event -- do not append
  elif ! echo "$now" >> "$guard_file" 2>/dev/null; then
    # F054: fail loud, not silent. A swallowed write failure here disarms
    # the breaker with zero indication it happened.
    echo "hook-guard: WARNING failed to write guard file ${guard_file} -- circuit breaker inactive for this event" >&2
    return 0
  fi

  # Count events within window
  count=0
  while IFS= read -r ts; do
    [ -n "$ts" ] && [ "$ts" -ge "$cutoff" ] 2>/dev/null && count=$((count + 1))
  done < "$guard_file" 2>/dev/null

  if [ "$count" -ge "$threshold" ]; then
    echo "hook-guard: circuit breaker tripped (${count} stop events in ${window}s)" >&2
    # Prune old entries to prevent unbounded growth
    awk -v c="$cutoff" '$1 >= c' "$guard_file" > "${guard_file}.tmp" 2>/dev/null \
      && mv "${guard_file}.tmp" "$guard_file" 2>/dev/null
    exit 0
  fi

  # Prune if file exceeds 50 lines (normal operation cleanup)
  local lines
  lines=$(wc -l < "$guard_file" 2>/dev/null || echo 0)
  if [ "$lines" -gt 50 ]; then
    tail -20 "$guard_file" > "${guard_file}.tmp" 2>/dev/null \
      && mv "${guard_file}.tmp" "$guard_file" 2>/dev/null
  fi

  return 0
}

stop_guard_reset() {
  local guard_file
  guard_file="$(_stop_guard_file)"
  rm -f "$guard_file" "${guard_file}.tmp" 2>/dev/null
}
