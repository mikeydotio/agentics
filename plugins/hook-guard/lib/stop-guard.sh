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

_stop_guard_file() {
  local project="${CLAUDE_PROJECT_DIR:-$PWD}"
  local hash
  hash=$(printf '%s' "$project" | md5sum | cut -c1-8)
  echo "/tmp/claude-stop-guard-${USER:-uid$(id -u)}-${hash}"
}

stop_guard_check() {
  local guard_file now count cutoff window threshold
  guard_file="$(_stop_guard_file)"
  now=$(date +%s)
  window="${1:-$_STOP_GUARD_WINDOW}"
  threshold="${2:-$_STOP_GUARD_THRESHOLD}"
  cutoff=$((now - window))

  # Append current timestamp
  echo "$now" >> "$guard_file" 2>/dev/null || return 0

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
