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
