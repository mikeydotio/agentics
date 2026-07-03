#!/usr/bin/env bats
# Tests for stop-guard.sh — the Stop-hook circuit breaker sourced by both
# freshen's on-stop.sh and forge's session-stop.sh.
#
# Mock-free: sources the real lib and drives it against a real guard file
# under a throwaway CLAUDE_PROJECT_DIR (mktemp'd, so each test gets its own
# guard-file key and there is no cross-test state).

LIB="$BATS_TEST_DIRNAME/stop-guard.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export CLAUDE_PROJECT_DIR="$TEST_DIR"
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

# Run stop_guard_check(s) in a fresh subshell each time (bash functions/vars
# from sourcing the lib must not leak between `run` invocations).
check_once() {
  run bash -c "CLAUDE_PROJECT_DIR='$TEST_DIR' . '$LIB' && stop_guard_check $*"
}

reset_once() {
  run bash -c "CLAUDE_PROJECT_DIR='$TEST_DIR' . '$LIB' && stop_guard_reset"
}

@test "first call does not trip and records one tick" {
  check_once
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$(guard_file_for)" | tr -d ' ')" = "1" ]
}

@test "four calls spaced apart within the window trip the breaker" {
  local guard_file now
  guard_file="$(guard_file_for)"
  now=$(date +%s)
  {
    echo $((now - 20))
    echo $((now - 15))
    echo $((now - 10))
  } > "$guard_file"
  # A 4th call (this one) reaches the default threshold of 4.
  check_once
  [[ "$output" == *"circuit breaker tripped"* ]]
}

@test "fewer than threshold calls within the window do not trip" {
  local guard_file now
  guard_file="$(guard_file_for)"
  now=$(date +%s)
  {
    echo $((now - 20))
    echo $((now - 10))
  } > "$guard_file"
  check_once
  [[ "$output" != *"circuit breaker tripped"* ]]
}

@test "entries outside the window do not count toward the threshold" {
  local guard_file now
  guard_file="$(guard_file_for)"
  now=$(date +%s)
  # Three stale entries far outside the default 30s window.
  {
    echo $((now - 300))
    echo $((now - 250))
    echo $((now - 200))
  } > "$guard_file"
  check_once
  [[ "$output" != *"circuit breaker tripped"* ]]
}

# --- F048/F043: same-event dedup (two hooks calling for one Stop event) ---

@test "two calls within the dedup window record only one tick (F048/F043)" {
  # Simulates freshen's on-stop.sh and forge's session-stop.sh both calling
  # stop_guard_check for the SAME Stop event, milliseconds apart.
  run bash -c "CLAUDE_PROJECT_DIR='$TEST_DIR' . '$LIB' && stop_guard_check && stop_guard_check"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$(guard_file_for)" | tr -d ' ')" = "1" ]
}

@test "the dedup window does not suppress a genuinely later, distinct Stop event" {
  local guard_file
  guard_file="$(guard_file_for)"
  # Seed one tick already outside the (default 2s) dedup window.
  echo "$(($(date +%s) - 5))" > "$guard_file"
  check_once
  [ "$(wc -l < "$guard_file" | tr -d ' ')" = "2" ]
}

@test "three real Stop events, each double-ticked by two hooks, trip only at the 4th real event" {
  # Regression for F048/F043: before the fix, 4 *calls* (2 real events x 2
  # hooks each) tripped the breaker -- effectively halving the documented
  # threshold of 4 real Stop events to 2. After the fix it must take 4 real
  # events (8 raw hook calls, correctly deduped in pairs) to trip, not 4
  # raw calls.
  local guard_file
  guard_file="$(guard_file_for)"

  # Simulate one real Stop event: two hooks call stop_guard_check
  # back-to-back in the same process (must collapse to exactly one tick),
  # then backdate that one tick by $1 seconds -- so several "past" events
  # can coexist with a live "current" one inside the 30s window without the
  # test actually sleeping in real time. Portable last-line rewrite (no
  # `sed -i`, no GNU-only `head -n -N`): drop the last line with `sed '$d'`,
  # then append the replacement.
  simulate_event_at_offset() {
    local offset="$1" fake_ts
    bash -c "CLAUDE_PROJECT_DIR='$TEST_DIR' . '$LIB' && stop_guard_check && stop_guard_check" >/dev/null 2>&1
    fake_ts=$(( $(date +%s) - offset ))
    { sed '$d' "$guard_file" 2>/dev/null; echo "$fake_ts"; } > "${guard_file}.new" \
      && mv "${guard_file}.new" "$guard_file"
  }

  simulate_event_at_offset 25
  [ "$(wc -l < "$guard_file" | tr -d ' ')" = "1" ]
  simulate_event_at_offset 18
  [ "$(wc -l < "$guard_file" | tr -d ' ')" = "2" ]
  simulate_event_at_offset 11
  [ "$(wc -l < "$guard_file" | tr -d ' ')" = "3" ]

  # The 4th real event, live: two more back-to-back calls must dedup to one
  # new tick, bringing the total to exactly 4 -- the configured threshold.
  run bash -c "CLAUDE_PROJECT_DIR='$TEST_DIR' . '$LIB' && stop_guard_check && stop_guard_check"
  [[ "$output" == *"circuit breaker tripped"* ]]
  [[ "$output" == *"(4 stop events"* ]]
}

# --- F054: fail loud on a guard-write failure, don't silently disarm ---

@test "a guard file that cannot be written logs a warning instead of silently disarming" {
  # Point the guard file at a path with an unwritable parent directory.
  local bogus_dir="$TEST_DIR/no-such-dir/nested"
  run bash -c "
    . '$LIB'
    _stop_guard_file() { echo '$bogus_dir/guard'; }
    stop_guard_check
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"circuit breaker inactive"* ]]
}

# --- stop_guard_reset ---

@test "stop_guard_reset removes the guard file" {
  local guard_file
  guard_file="$(guard_file_for)"
  echo "$(date +%s)" > "$guard_file"
  reset_once
  [ ! -f "$guard_file" ]
}

# --- F055: md5 fallback when md5sum is unavailable ---

@test "the project-hash key still resolves when md5sum is shadowed by a failing stub" {
  local shim_dir
  shim_dir="$(mktemp -d)"
  cat > "$shim_dir/md5sum" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$shim_dir/md5sum"
  run bash -c "PATH='$shim_dir:$PATH' CLAUDE_PROJECT_DIR='$TEST_DIR' . '$LIB' && _stop_guard_file"
  [ "$status" -eq 0 ]
  [[ "$output" == /tmp/claude-stop-guard-* ]]
  # Must not be the degenerate "no hash at all" guard path.
  [[ "$output" != "/tmp/claude-stop-guard-${USER:-uid$(id -u)}-" ]]
  rm -rf "$shim_dir"
}
