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
# .clear-consumed (on-clear.sh never touches it).
#
# Residual regression from the .clear-consumed hand-off itself (found by
# adversarial verification of the fix above): the hand-off only has a reader
# in the ordering where on-clear.sh runs FIRST (it creates .clear-consumed,
# then this script reads-and-deletes it in the SAME SessionStart(clear)
# event). When this script instead runs FIRST, it sees .clear-pending
# directly, sets SKIP_RESET, and -- correctly, per the design constraint that
# on-clear.sh still needs .clear-pending's content -- leaves the file alone.
# on-clear.sh then runs second and renames it to .clear-consumed as always,
# but by then this script has already finished handling *this* event and
# won't run again until the next SessionStart(clear). Nothing in that cycle
# ever reads/deletes that .clear-consumed: it lingers on disk after an event
# that has already been fully and correctly processed. If the very next
# SessionStart(clear) is a genuine, unrelated, bare user /clear (no
# .clear-pending involved at all), this script would find that stale
# .clear-consumed, wrongly treat it as live evidence that THIS /clear was
# also freshen-initiated, and skip a reset that should happen.
#
# Fix: don't treat .clear-consumed's mere existence as evidence -- bound its
# validity to a short freshness window on its mtime, the same "same hook
# batch vs. a genuinely later event" reasoning stop-guard.sh's
# _STOP_GUARD_DEDUP_WINDOW already relies on elsewhere in this plugin (see
# lib/stop-guard.sh): hooks racing for the *same* SessionStart event run
# back-to-back in the same batch, reliably well under a second apart; two
# genuinely distinct SessionStart(clear) events are always at least one full
# model round-trip apart (seconds, typically far more). So a .clear-consumed
# younger than CLEAR_CONSUMED_WINDOW seconds is this event's own hand-off;
# anything older is a stale leftover from an event this script already
# finished handling. Either way the marker is single-use: it is always
# deleted here once read, fresh or stale, so it can never accumulate or be
# misread by a later event again.
set -uo pipefail

CLEAR_CONSUMED_WINDOW="${CLEAR_CONSUMED_WINDOW:-5}"

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
    # on-clear.sh may have handed the flag off to us (see comments above) --
    # but its mere presence is no longer treated as proof by itself, since a
    # marker from an already-fully-processed prior event can linger (see the
    # "Residual regression" comment above). Only trust it as THIS event's
    # hand-off if it's still within the freshness window; otherwise it's a
    # stale leftover -- don't skip the reset on its account. Either way we
    # are the sole reader/deleter of this marker, so it is always removed
    # here so it can never be misread again.
    CONSUMED_MTIME="$(stat -c%Y "$PROJECT_DIR/.freshen/.clear-consumed" 2>/dev/null \
      || stat -f%m "$PROJECT_DIR/.freshen/.clear-consumed" 2>/dev/null \
      || echo 0)"
    NOW_TS="$(date +%s)"
    AGE=$((NOW_TS - CONSUMED_MTIME))
    if [ "$CONSUMED_MTIME" -gt 0 ] 2>/dev/null \
      && [ "$AGE" -ge 0 ] 2>/dev/null \
      && [ "$AGE" -le "$CLEAR_CONSUMED_WINDOW" ] 2>/dev/null; then
      SKIP_RESET=1
    else
      echo "hook-guard: ignoring stale .clear-consumed marker (age ${AGE}s > ${CLEAR_CONSUMED_WINDOW}s) -- not treating as freshen-initiated" >&2
    fi
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
