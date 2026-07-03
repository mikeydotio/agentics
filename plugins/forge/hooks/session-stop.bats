#!/usr/bin/env bats
# Tests for forge's session-stop.sh Stop hook, focused on the cross-plugin
# hook-ordering fix: Claude Code does not guarantee whether forge's
# session-stop.sh or freshen's on-stop.sh runs first within the same Stop
# event, and the two used to depend on that order (forge writes a signal
# file that freshen's hook reads and acts on). See references/auto-resume.md
# ("Cross-Plugin Hook Ordering") for the full writeup.
#
# tmux itself is shimmed (a fake executable on PATH that logs invocations) —
# this is not mocking forge's own behavior, only standing in for a real tmux
# pane so these tests don't require an actual tmux session. Everything else
# (state.json, lock.json, the freshen signal protocol) is the real thing.

FORGE_HOOK="$BATS_TEST_DIRNAME/session-stop.sh"
FRESHEN_HOOK="$BATS_TEST_DIRNAME/../../freshen/hooks/on-stop.sh"
FORGE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
FRESHEN_PLUGIN_ROOT="$BATS_TEST_DIRNAME/../../freshen"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  mkdir -p "$TEST_DIR/.forge" "$TEST_DIR/.freshen"

  cat > "$TEST_DIR/.forge/state.json" <<'EOF'
{"status": "running", "sessions_completed": 0, "stories_attempted": 2, "stories_this_session": 1}
EOF
  cat > "$TEST_DIR/.forge/lock.json" <<EOF
{"holder": "test-session", "acquired_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

  # tmux shim: log every invocation to a file instead of driving a real pane.
  SHIM_DIR="$TEST_DIR/shim"
  mkdir -p "$SHIM_DIR"
  TMUX_LOG="$TEST_DIR/tmux.log"
  touch "$TMUX_LOG"
  cat > "$SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMUX_LOG"
exit 0
EOF
  chmod +x "$SHIM_DIR/tmux"
  export PATH="$SHIM_DIR:$PATH"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]]; then
    local guard_file
    guard_file="$(guard_file_for "$TEST_DIR")"
    rm -f "$guard_file" "${guard_file}.tmp"
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

run_forge_stop() {
  CLAUDE_PROJECT_DIR="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$FORGE_PLUGIN_ROOT" \
    TMUX=1 TMUX_PANE="%1" \
    bash "$FORGE_HOOK" < /dev/null
}

run_freshen_stop() {
  ( cd "$TEST_DIR" && \
    CLAUDE_PLUGIN_ROOT="$FRESHEN_PLUGIN_ROOT" TMUX=1 TMUX_PANE="%1" \
    bash "$FRESHEN_HOOK" )
}

send_count() {
  grep -c "send-keys" "$TMUX_LOG" || true
}

# Mirrors stop-guard.sh's own _stop_guard_file() key derivation exactly, so
# tests can pre-seed / clean up the real on-disk guard file for a given
# project dir without sourcing the lib (which would pollute the test's own
# shell with its functions/vars).
guard_file_for() {
  local project="$1" hash
  hash=$(printf '%s' "$project" | md5sum 2>/dev/null | cut -c1-8)
  [ -z "$hash" ] && hash=$(printf '%s' "$project" | md5 2>/dev/null | cut -c1-8)
  echo "/tmp/claude-stop-guard-${USER:-uid$(id -u)}-${hash}"
}

@test "freshen's Stop hook alone sends nothing before forge has written a signal" {
  # This is the exact ordering that used to silently strand auto-resume:
  # freshen's Stop hook running before forge's finds no signal yet and exits
  # without ever sending /clear.
  run_freshen_stop
  [ ! -s "$TMUX_LOG" ]
}

@test "forge's Stop hook sends /clear itself, regardless of whether freshen's hook already ran and found nothing" {
  run_freshen_stop
  run_forge_stop
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(send_count)" = "1" ]
}

@test "freshen's Stop hook does not double-send /clear if forge already sent it this batch" {
  run_forge_stop
  [ "$(send_count)" = "1" ]
  run_freshen_stop
  # Still exactly one /clear -- freshen's hook must see .clear-pending
  # (set by forge) and skip sending a second one.
  [ "$(send_count)" = "1" ]
}

@test "the forge signal file survives both hooks so on-clear.sh can still consume it" {
  run_forge_stop
  run_freshen_stop
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
}

@test "forge's Stop hook sends nothing when status is not running" {
  echo '{"status": "paused"}' > "$TEST_DIR/.forge/state.json"
  run_forge_stop
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -s "$TMUX_LOG" ]
}

@test "forge's Stop hook skips the signal and /clear entirely without tmux" {
  # Explicitly unset TMUX/TMUX_PANE -- the test harness itself may be running
  # inside a real tmux session, whose env vars would otherwise leak through.
  env -u TMUX -u TMUX_PANE CLAUDE_PROJECT_DIR="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$FORGE_PLUGIN_ROOT" \
    bash "$FORGE_HOOK" < /dev/null
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -s "$TMUX_LOG" ]
}

# --- F050: a tripped circuit breaker must not leak the lock / skip the checkpoint ---

@test "a tripped circuit breaker still lets the durable checkpoint run, but suppresses the auto-resume signal" {
  local guard_file now
  guard_file="$(guard_file_for "$TEST_DIR")"
  mkdir -p "$(dirname "$guard_file")"
  now=$(date +%s)
  # Four distinct ticks (>2s apart so stop_guard_check's own same-event
  # dedup window doesn't collapse them), all inside the 30s trip window --
  # this alone reaches the default threshold (4), so the very next
  # stop_guard_check call (made by session-stop.sh itself below) trips.
  {
    echo $((now - 20))
    echo $((now - 15))
    echo $((now - 10))
    echo $((now - 5))
  } > "$guard_file"

  run_forge_stop

  # The durable checkpoint must have completed despite the trip (F050).
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
  [ ! -f "$TEST_DIR/.forge/lock.json" ]
  [ -f "$TEST_DIR/.forge/handoffs/handoff-execute.md" ]
  # ...but the breaker trip must still suppress the one thing it exists to
  # gate: queuing the freshen auto-resume signal / sending /clear.
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -s "$TMUX_LOG" ]
}

# --- F055: portable duration computation (no GNU-only `date -d`) ---

@test "session-stop computes a real duration via jq's fromdate, not GNU date -d" {
  run_forge_stop
  run grep -oE '\*\*Duration\*\*: [0-9]+s' "$TEST_DIR/.forge/handoffs/handoff-execute.md"
  [ "$status" -eq 0 ]
}

@test "an unparseable lock timestamp degrades to Duration: unknown instead of crashing" {
  cat > "$TEST_DIR/.forge/lock.json" <<'EOF'
{"holder": "test-session", "acquired_at": "not-a-real-timestamp"}
EOF
  run_forge_stop
  run grep -F '**Duration**: unknown' "$TEST_DIR/.forge/handoffs/handoff-execute.md"
  [ "$status" -eq 0 ]
}

# --- F051: bounded story handoff (timeout), reordered after the checkpoint ---

@test "a hanging story handoff is bounded by a timeout and never blocks the checkpoint" {
  cat > "$SHIM_DIR/story" <<'SHIM'
#!/usr/bin/env bash
sleep 30
echo "should never print -- killed by the timeout wrapper first"
SHIM
  chmod +x "$SHIM_DIR/story"

  local start end elapsed
  start=$(date +%s)
  run_forge_stop
  end=$(date +%s)
  elapsed=$((end - start))

  # Bounded well under the hook's 15s timeout budget (internal timeout is
  # 5s) -- the checkpoint must have completed regardless of the hang.
  [ "$elapsed" -lt 12 ]
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
  [ ! -f "$TEST_DIR/.forge/lock.json" ]
}
