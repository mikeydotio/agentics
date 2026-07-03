#!/usr/bin/env bash
# Reset the stop-hook circuit breaker on fresh sessions.
# This ensures the breaker auto-recovers after a loop is broken.
#
# F052: resetting unconditionally on every SessionStart(clear) defeats the
# breaker for its single most important loop vector. freshen's *normal*
# operation is /clear + re-invoke (its Stop hook sends /clear, then the
# resulting SessionStart(clear) re-invokes the queued command) -- so a
# runaway freshen-mediated loop produces a SessionStart(clear) every single
# cycle, and a reset-on-every-clear policy wipes the counter every cycle
# too. The one loop the breaker most needs to catch can never trip it.
#
# Fix: distinguish a genuine user-initiated /clear (reset is correct -- the
# user broke the loop themselves) from a freshen-initiated one (skip the
# reset so the count survives across cycles):
#   - source == startup/resume: always reset (unambiguous fresh session).
#   - source == clear: reset ONLY if there is no pending freshen signal.
#     freshen marks its own automatic clears with .freshen/.clear-pending
#     (touched by the Stop hook right before send-keys, removed by
#     on-clear.sh after it re-invokes) -- its presence here means this
#     /clear was freshen-initiated. This is a file-based, best-effort
#     signal (WS6 is expected to replace it with a tmux pane option that
#     survives /clear more robustly); until then it's the only "freshen is
#     mid-transition" signal that exists.
set -uo pipefail

INPUT="$(cat 2>/dev/null)" || INPUT=""
SOURCE=""
PROJECT_DIR=""
if command -v jq >/dev/null 2>&1; then
  SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)"
  PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
else
  # F054: this is NOT the "plugin inactive" silent-skip case -- hook-guard
  # runs unconditionally on every SessionStart. Without jq we can't read
  # `source`, so we fall back to the safe-but-degraded old behavior (always
  # reset) rather than silently and invisibly losing the F052 protection.
  echo "hook-guard: WARNING jq not found -- cannot read SessionStart source, falling back to unconditional reset" >&2
fi
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

SKIP_RESET=0
if [ "$SOURCE" = "clear" ] && [ -f "$PROJECT_DIR/.freshen/.clear-pending" ]; then
  SKIP_RESET=1
fi

_GUARD_LIB="${CLAUDE_PLUGIN_ROOT}/lib/stop-guard.sh"
if [ "$SKIP_RESET" -eq 0 ] && [ -f "$_GUARD_LIB" ]; then
  . "$_GUARD_LIB"
  stop_guard_reset
fi

if [ "$SKIP_RESET" -eq 1 ]; then
  echo "hook-guard: skipped reset (freshen-initiated /clear pending)" >&2
else
  echo "hook-guard: ok" >&2
fi
