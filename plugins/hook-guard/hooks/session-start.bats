#!/usr/bin/env bats
# Tests for hook-guard's SessionStart hook — the circuit-breaker reset that
# ALSO fires on `source: "clear"` (freshen's own /clear + re-invoke cycle),
# which is exactly the loop the breaker most needs to keep counting across
# (F052).

HOOK="$BATS_TEST_DIRNAME/session-start.sh"
PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
LIB="$PLUGIN_ROOT/lib/stop-guard.sh"

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

@test "an unparseable SessionStart payload still resets on startup (fails safe, not silent)" {
  seed_guard_file
  run bash -c "printf 'not json' | CLAUDE_PROJECT_DIR='$TEST_DIR' CLAUDE_PLUGIN_ROOT='$PLUGIN_ROOT' bash '$HOOK'"
  [ "$status" -eq 0 ]
  # source resolves to empty (not "clear"), so the default path resets.
  [ ! -f "$(guard_file_for)" ]
}
