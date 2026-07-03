#!/usr/bin/env bats
# Tests for hook-guard's SessionStart hook — the circuit-breaker reset that
# ALSO fires on `source: "clear"` (freshen's own /clear + re-invoke cycle),
# which is exactly the loop the breaker most needs to keep counting across
# (F052).
#
# Also covers the cross-plugin ordering hazard in that same fix: freshen's
# own SessionStart(clear) hook (on-clear.sh) reads and consumes the same
# .freshen/.clear-pending flag, and Claude Code does not guarantee which of
# the two hooks runs first (CLAUDE.md's "Hook ordering" section). The tests
# below drive freshen's REAL on-clear.sh (not a stand-in) to prove the skip
# survives regardless of which hook wins the race.

HOOK="$BATS_TEST_DIRNAME/session-start.sh"
PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
LIB="$PLUGIN_ROOT/lib/stop-guard.sh"
FRESHEN_ROOT="$BATS_TEST_DIRNAME/../../freshen"
ON_CLEAR="$FRESHEN_ROOT/hooks/on-clear.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
}

teardown() {
  local guard_file
  guard_file="$(guard_file_for)"
  rm -f "$guard_file" "${guard_file}.tmp"
  rm -rf "$TEST_DIR"
}

guard_file_for() {
  local hash
  hash=$(printf '%s' "$TEST_DIR" | md5sum 2>/dev/null | cut -c1-8)
  [ -z "$hash" ] && hash=$(printf '%s' "$TEST_DIR" | md5 2>/dev/null | cut -c1-8)
  echo "/tmp/claude-stop-guard-${USER:-uid$(id -u)}-${hash}"
}

seed_guard_file() {
  echo "$(date +%s)" > "$(guard_file_for)"
}

run_session_start() {
  local source="$1"
  printf '{"source":"%s","cwd":"%s"}' "$source" "$TEST_DIR" \
    | CLAUDE_PROJECT_DIR="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK"
}

# Runs freshen's REAL on-clear.sh against TEST_DIR, with TMUX explicitly
# cleared so it deterministically takes the "no tmux" early-exit path
# (consumes .clear-pending, does not attempt send-keys) regardless of
# whether the outer test process happens to be running inside a tmux pane.
run_on_clear() {
  ( cd "$TEST_DIR" && TMUX= TMUX_PANE= CLAUDE_PLUGIN_ROOT="$FRESHEN_ROOT" bash "$ON_CLEAR" )
}

# Sets a file's mtime N seconds in the past, portably across GNU and BSD
# `date`/`touch` (macOS ships BSD touch; Linux ships GNU touch -- their `-t`
# argument format is shared, but the epoch-seconds -> formatted-timestamp
# step differs: GNU `date -d "@<epoch>"` vs BSD `date -r <epoch>`). Used to
# simulate a genuinely later, distinct SessionStart(clear) event without
# sleeping in the test -- real distinct events are always at least one full
# model round-trip apart (seconds), so backdating past the hook's freshness
# window (default 5s) is a faithful stand-in.
backdate_mtime() {
  local file="$1" seconds_ago="$2" past_epoch ts
  past_epoch=$(( $(date +%s) - seconds_ago ))
  ts="$(date -d "@$past_epoch" +%Y%m%d%H%M.%S 2>/dev/null \
    || date -r "$past_epoch" +%Y%m%d%H%M.%S 2>/dev/null)"
  touch -t "$ts" "$file"
}

@test "source=startup always resets the breaker" {
  seed_guard_file
  run run_session_start startup
  [ "$status" -eq 0 ]
  [ ! -f "$(guard_file_for)" ]
  [[ "$output" == "hook-guard: ok" ]]
}

@test "source=resume always resets the breaker" {
  seed_guard_file
  run run_session_start resume
  [ ! -f "$(guard_file_for)" ]
}

@test "source=clear with NO pending freshen signal resets the breaker (genuine user /clear)" {
  seed_guard_file
  # No .freshen/.clear-pending -- this is a plain user-initiated /clear.
  run run_session_start clear
  [ "$status" -eq 0 ]
  [ ! -f "$(guard_file_for)" ]
  [[ "$output" == "hook-guard: ok" ]]
}

@test "source=clear WITH a pending freshen signal does NOT reset the breaker (F052)" {
  seed_guard_file
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-pending"
  run run_session_start clear
  [ "$status" -eq 0 ]
  # The guard file must survive -- a freshen-mediated loop must keep
  # accumulating ticks across /clear cycles instead of being wiped every time.
  [ -f "$(guard_file_for)" ]
  [[ "$output" == *"skipped reset"* ]]
}

@test "a freshen-mediated loop can still trip the breaker across several /clear cycles" {
  # Simulates F052's exact failure mode: N cycles of (Stop -> tick guard,
  # SessionStart(clear) with .clear-pending -> would-be reset). Before the
  # fix, every cycle wiped the counter and the breaker could never trip no
  # matter how many cycles ran. After the fix, ticks accumulate across
  # cycles and the breaker trips once the threshold is reached.
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-pending"
  local guard_file now
  guard_file="$(guard_file_for)"
  now=$(date +%s)
  # Three prior ticks already recorded (simulating three earlier freshen
  # cycles' Stop-hook ticks), each followed by a would-be reset that must
  # be skipped because .clear-pending is present throughout.
  {
    echo $((now - 20))
    echo $((now - 15))
    echo $((now - 10))
  } > "$guard_file"
  for _ in 1 2 3; do
    run_session_start clear >/dev/null
  done
  [ -f "$guard_file" ]
  [ "$(wc -l < "$guard_file" | tr -d ' ')" = "3" ]

  # The 4th cycle's Stop-hook tick (this test drives stop_guard_check
  # directly, standing in for forge's/freshen's Stop hook) reaches the
  # threshold and trips.
  run bash -c ". '$LIB' && CLAUDE_PROJECT_DIR='$TEST_DIR' stop_guard_check"
  [[ "$output" == *"circuit breaker tripped"* ]]
}

@test "hook-guard running BEFORE on-clear.sh leaves .clear-pending untouched (only reads it)" {
  seed_guard_file
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-pending"
  run run_session_start clear
  [ -f "$(guard_file_for)" ]
  # hook-guard must never delete .clear-pending itself -- that's on-clear.sh's
  # signal to process (or not) the queued freshen re-invocation. Deleting it
  # here would silently strand that logic.
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
}

@test "on-clear.sh consuming .clear-pending FIRST does not defeat hook-guard's skip (cross-plugin ordering, F052)" {
  # Reproduces the regression exactly: freshen's on-clear.sh and hook-guard's
  # session-start.sh are two independent SessionStart(clear) hooks in
  # unspecified relative order. Drive the REAL on-clear.sh first -- if it
  # destructively deleted .clear-pending (the old behavior), hook-guard would
  # find nothing and wrongly reset the breaker, reproducing F052 under this
  # specific ordering. It must instead hand the flag off.
  seed_guard_file
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-pending"

  run run_on_clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"freshen: ok"* ]]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]

  run run_session_start clear
  [ "$status" -eq 0 ]
  # The breaker must survive -- this is the crux of F052.
  [ -f "$(guard_file_for)" ]
  [[ "$output" == *"skipped reset"* ]]
  # hook-guard is the sole reader/deleter of .clear-consumed -- it must clean
  # up after itself so the marker doesn't linger into unrelated future events.
  [ ! -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "source=clear with only .clear-consumed present (on-clear.sh already ran) still skips reset and cleans up the marker" {
  seed_guard_file
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-consumed"
  run run_session_start clear
  [ "$status" -eq 0 ]
  [ -f "$(guard_file_for)" ]
  [[ "$output" == *"skipped reset"* ]]
  [ ! -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "a stale .clear-consumed marker is ignored (not treated as evidence) and still cleaned up" {
  # Direct/isolated regression coverage for the freshness-window mechanism
  # itself: an old .clear-consumed (older than CLEAR_CONSUMED_WINDOW) must
  # NOT suppress the reset, regardless of how it got there.
  seed_guard_file
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-consumed"
  backdate_mtime "$TEST_DIR/.freshen/.clear-consumed" 30
  run run_session_start clear
  [ "$status" -eq 0 ]
  # Stale marker must NOT suppress the reset -- this /clear was not
  # (as far as current evidence shows) freshen-initiated.
  [ ! -f "$(guard_file_for)" ]
  [[ "$output" == *"ignoring stale .clear-consumed"* ]]
  [[ "$output" == *"hook-guard: ok"* ]]
  # Cleaned up regardless of the staleness verdict.
  [ ! -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "a SECOND, unrelated bare /clear after a hook-guard-first freshen cycle resets the breaker (residual regression)" {
  # Reproduces the exact residual regression from adversarial verification of
  # F052's fix: hook-guard sees .clear-pending and skips (ordering: hook-guard
  # first) -> on-clear.sh runs after it in the SAME event and hands the flag
  # off to .clear-consumed as always -> nothing in that cycle ever reads that
  # .clear-consumed back, so it lingers -> a SECOND, wholly unrelated bare
  # user /clear must still reset the breaker, not be fooled by the leftover.
  seed_guard_file
  mkdir -p "$TEST_DIR/.freshen"
  touch "$TEST_DIR/.freshen/.clear-pending"

  # Cycle 1, event A: hook-guard runs FIRST. It must see .clear-pending
  # directly, skip the reset, and -- critically -- leave .clear-pending
  # completely untouched (on-clear.sh still needs its content).
  run run_session_start clear
  [ "$status" -eq 0 ]
  [ -f "$(guard_file_for)" ]
  [[ "$output" == *"skipped reset"* ]]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]

  # Cycle 1, event A continued: on-clear.sh runs SECOND for this SAME event,
  # as always, and hands .clear-pending off by renaming it to
  # .clear-consumed. hook-guard has already finished with event A and will
  # not run again for it -- this .clear-consumed has no reader this cycle.
  run run_on_clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"freshen: ok"* ]]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]

  # A real, distinct SessionStart(clear) event is always at least one full
  # model round-trip away (seconds) -- simulate that elapsed time by
  # backdating the leftover marker past the freshness window instead of
  # sleeping in the test.
  backdate_mtime "$TEST_DIR/.freshen/.clear-consumed" 30

  # Event B: a SECOND, wholly unrelated, bare user /clear. No .clear-pending
  # was ever touched for it -- this has nothing to do with freshen. Before
  # the fix, hook-guard would find the stale .clear-consumed left over from
  # event A and wrongly treat it as evidence that event B was ALSO
  # freshen-initiated, skipping a reset that should happen.
  run run_session_start clear
  [ "$status" -eq 0 ]
  # The breaker MUST reset this time -- this is the crux of the regression.
  [ ! -f "$(guard_file_for)" ]
  [[ "$output" == *"hook-guard: ok"* ]]
  [[ "$output" != *"skipped reset"* ]]
  # The stale marker must still be cleaned up, whichever way it was judged.
  [ ! -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "an unparseable SessionStart payload still resets on startup (fails safe, not silent)" {
  seed_guard_file
  run bash -c "printf 'not json' | CLAUDE_PROJECT_DIR='$TEST_DIR' CLAUDE_PLUGIN_ROOT='$PLUGIN_ROOT' bash '$HOOK'"
  [ "$status" -eq 0 ]
  # source resolves to empty (not "clear"), so the default path resets.
  [ ! -f "$(guard_file_for)" ]
}
