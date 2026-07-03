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
#     (touched by the Stop hook right before send-keys). This is a
#     file-based, best-effort signal (WS6 is expected to replace it with a
#     tmux pane option that survives /clear more robustly); until then it's
#     the only "freshen is mid-transition" signal that exists.
#
# Cross-plugin ordering hazard (also F052): freshen's own SessionStart(clear)
# hook (on-clear.sh, a different plugin) ALSO reads .clear-pending on this
# same event, and Claude Code does not guarantee which of the two hooks runs
# first (see CLAUDE.md's "Hook ordering" section). on-clear.sh consumes the
# flag once it's done with it; if it happened to run before this script and
# had simply deleted .clear-pending, this script would find nothing, wrongly
# conclude the /clear was user-initiated, and reset the breaker anyway --
# defeating the very protection above under an ordering the codebase
# explicitly documents as unenforceable. To stay correct regardless of
# ordering, on-clear.sh hands the flag off by renaming it to
# .clear-consumed instead of deleting it, so the "this /clear was
# freshen-initiated" fact survives on-clear.sh's own processing no matter
# which hook ran first. This script is the sole reader/deleter of
# .clear-consumed (on-clear.sh never touches it), so there's no further race
# over its cleanup.
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
if [ "$SOURCE" = "clear" ]; then
  if [ -f "$PROJECT_DIR/.freshen/.clear-pending" ]; then
    SKIP_RESET=1
  elif [ -f "$PROJECT_DIR/.freshen/.clear-consumed" ]; then
    # on-clear.sh already ran and handed the flag off to us (see comments
    # above) -- this /clear was still freshen-initiated. Consume it: we are
    # the only reader/deleter of this marker, so no ordering hazard here.
    SKIP_RESET=1
    rm -f "$PROJECT_DIR/.freshen/.clear-consumed"
  fi
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
