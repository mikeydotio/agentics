#!/usr/bin/env bash
# Reset the stop-hook circuit breaker on fresh sessions.
# This ensures the breaker auto-recovers after a loop is broken.

_GUARD_LIB="${CLAUDE_PLUGIN_ROOT}/lib/stop-guard.sh"
if [ -f "$_GUARD_LIB" ]; then
  . "$_GUARD_LIB"
  stop_guard_reset
fi
echo "hook-guard: ok" >&2
