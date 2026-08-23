#!/usr/bin/env bats
# Dual-host contract and Codex adapter tests. Claude's legacy hook behavior is
# still covered by on-stop.bats/on-clear.bats; these cases prove that routing to
# Codex changes only the host-specific reset and hook wire contracts.

FRESHEN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DISPATCH="$BATS_TEST_DIRNAME/host-dispatch.sh"
CODEX_HOOKS="$BATS_TEST_DIRNAME/codex"
CODEX_CLI="$FRESHEN_ROOT/codex/bin/freshen.sh"
SHARED_CLI="$FRESHEN_ROOT/bin/freshen.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  mkdir -p "$TEST_DIR/.freshen" "$TEST_DIR/shim"
  TMUX_CALL_LOG="$TEST_DIR/tmux-calls.log"
  export TMUX_CALL_LOG
  : > "$TMUX_CALL_LOG"

  cat > "$TEST_DIR/shim/tmux" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
case "$1" in
  capture-pane)
    if [ -f "$TEST_DIR/pane-busy" ]; then
      printf '%s\n' 'Thinking... (esc to interrupt)'
    else
      printf '%s\n' 'OpenAI Codex' '›'
    fi
    ;;
esac
exit 0
SHIM
  chmod +x "$TEST_DIR/shim/tmux"
  export PATH="$TEST_DIR/shim:$PATH"

  export PANE_CONFIRM_ATTEMPTS=1
  export PANE_CONFIRM_DELAY=0
  export PANE_SEND_RETRIES=0
  export PANE_PASTE_SETTLE_DELAY=0
  export FRESHEN_CODEX_READY_DELAY=0
  export FRESHEN_CODEX_DEFERRED_DELAY=0
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "Codex manifest is versioned with the repository and exposes the Freshen skill" {
  run jq -e --arg version "$(tr -d '[:space:]' < "$FRESHEN_ROOT/../../VERSION" | sed 's/^v//')" '
    .name == "freshen" and
    .version == $version and
    .skills == "./skills/" and
    .interface.displayName == "Freshen" and
    (.interface.defaultPrompt | length > 0 and length <= 3)
  ' "$FRESHEN_ROOT/.codex-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "root dispatcher isolates host trees and preserves Claude metadata" {
  run grep -q 'HOST_DISPATCH_VERSION' "$FRESHEN_ROOT/skills/freshen/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -q '^model: sonnet$' "$FRESHEN_ROOT/claude/skills/freshen/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -q '^effort: low$' "$FRESHEN_ROOT/claude/skills/freshen/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -Eq '^(model|effort|argument-hint):' "$FRESHEN_ROOT/skills/freshen/SKILL.md"
  [ "$status" -eq 1 ]
}

@test "host dispatcher selects unchanged Claude hooks without PLUGIN_ROOT" {
  run env -u PLUGIN_ROOT bash "$DISPATCH" --resolve on-stop.sh
  [ "$status" -eq 0 ]
  [ "$output" = "claude:$FRESHEN_ROOT/hooks/on-stop.sh" ]
}

@test "host dispatcher selects Codex adapters when PLUGIN_ROOT is present" {
  run env PLUGIN_ROOT="$FRESHEN_ROOT" bash "$DISPATCH" --resolve on-stop.sh
  [ "$status" -eq 0 ]
  [ "$output" = "codex:$FRESHEN_ROOT/hooks/codex/on-stop.sh" ]
}

@test "Claude dispatcher still executes the shared /clear transition" {
  echo '/forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && env -u PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  run grep -c -F -- '%1 /clear' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
  run grep -c -F -- '%1 /new' "$TMUX_CALL_LOG"
  [ "$output" = "0" ]
}

@test "Codex queue wrapper reports Codex while the shared CLI preserves Claude diagnostics" {
  run bash -c 'cd "$1" && env -u TMUX -u TMUX_PANE bash "$2" queue test --source smoke' _ "$TEST_DIR" "$CODEX_CLI"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Codex must be running inside a tmux session"* ]]

  run bash -c 'cd "$1" && env -u TMUX -u TMUX_PANE bash "$2" queue test --source smoke' _ "$TEST_DIR" "$SHARED_CLI"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Claude must be running inside a tmux session"* ]]
}

@test "Codex readiness rejects a trust dialog even when the header and prompt glyph are visible" {
  run bash -c '. "$1"; tmux(){ printf "%s\n" "OpenAI Codex" "Do you trust the contents of this directory?" "› 1. Yes, continue" "Press enter to continue"; }; FRESHEN_CODEX_READY_ATTEMPTS=1 FRESHEN_CODEX_READY_DELAY=0 codex_pane_wait_ready %%1' _ "$CODEX_HOOKS/pane-ready.sh"
  [ "$status" -eq 1 ]
}

@test "Codex Stop no-op emits valid JSON" {
  run bash -c 'cd "$1" && printf "%s\n" "{\"hook_event_name\":\"Stop\"}" | PLUGIN_ROOT="$2" bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  run jq -e 'type == "object"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "Codex Stop without tmux leaves a pending signal and returns valid JSON" {
  echo '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && env -u TMUX -u TMUX_PANE PLUGIN_ROOT="$2" bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"manual /new"* ]]
  [[ "$output" == *"{}"* ]]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
}

@test "Codex SessionStart(clear) consumes a confirmed continuation and serializes its summary" {
  touch "$TEST_DIR/.freshen/.clear-pending"
  printf '%s\n%s\n' '$forge:forge resume' 'planning complete' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && printf "%s\n" "{\"source\":\"clear\"}" | PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" on-clear.sh 2>"$1/codex-clear.err"' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  run jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("planning complete"))' <<< "$output"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  run grep -c -F -- '-l $forge:forge resume' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
}

@test "shared Stop engine accepts Codex /new without changing Claude's default /clear" {
  echo '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && FRESHEN_CLEAR_COMMAND=/new CLAUDE_PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$2/hooks/on-stop.sh"' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  run grep -c -F -- '%1 /new' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
  run grep -c -F -- '%1 /clear' "$TMUX_CALL_LOG"
  [ "$output" = "0" ]
}

@test "deferred Codex worker completes /new and continuation through the shared engine" {
  printf '%s\n%s\n' '$forge:forge resume' 'ready for execution' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 FRESHEN_CODEX_DEFERRED_ATTEMPTS=1 bash "$3/deferred-stop.sh"' _ "$TEST_DIR" "$FRESHEN_ROOT" "$CODEX_HOOKS"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ -f "$TEST_DIR/.freshen/.clear-consumed" ]
  run grep -c -F -- '%1 /new' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
  run grep -c -F -- '-l $forge:forge resume' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
  run grep -c 'on-stop: /new confirmed accepted' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
  run grep -c 'on-clear: re-invoke confirmed accepted' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "deferred Codex worker is bounded and preserves the signal when the pane stays busy" {
  echo '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  touch "$TEST_DIR/pane-busy"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 FRESHEN_CODEX_DEFERRED_ATTEMPTS=1 bash "$3/deferred-stop.sh"' _ "$TEST_DIR" "$FRESHEN_ROOT" "$CODEX_HOOKS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"was not accepted"* ]]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  run grep -c '^send-keys' "$TMUX_CALL_LOG"
  [ "$output" = "0" ]
}
