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
  TMUX_SUBMISSION_LOG="$TEST_DIR/tmux-submissions.log"
  export TMUX_SUBMISSION_LOG
  : > "$TMUX_SUBMISSION_LOG"
  : > "$TEST_DIR/pane-input"

  cat > "$TEST_DIR/shim/tmux" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_CALL_LOG"
case "$1" in
  capture-pane)
    if [ -f "$TEST_DIR/pane-busy" ]; then
      printf '%s\n' 'Thinking... (esc to interrupt)' '›' '100% context left'
    elif [ -f "$TEST_DIR/pane-trust" ]; then
      printf '%s\n' 'OpenAI Codex' 'Do you trust the contents?' '› 1. Yes, continue' 'Press enter to continue'
    else
      input="$(cat "$TEST_DIR/pane-input")"
      printf '%s\n' 'OpenAI Codex' "› $input" '100% context left' '? for shortcuts'
    fi
    ;;
  send-keys)
    shift
    literal=false
    value=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -l) literal=true; shift ;;
        *) value="$1"; shift ;;
      esac
    done
    if [ "$value" = Enter ]; then
      cat "$TEST_DIR/pane-input" >> "$TMUX_SUBMISSION_LOG"
      printf '\n' >> "$TMUX_SUBMISSION_LOG"
      : > "$TEST_DIR/pane-input"
    else
      printf '%s' "$value" > "$TEST_DIR/pane-input"
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
  export FRESHEN_CODEX_STABLE_OBSERVATIONS=1
  export FRESHEN_CODEX_RESET_SETTLE=0
  export FRESHEN_CODEX_TEST_ALLOW_SHORT_SETTLE=1
  export FRESHEN_CODEX_PASTE_SETTLE=0
}

wait_for_phase() {
  local expected="$1" i=0 phase=""
  while [ "$i" -lt 100 ]; do
    phase="$(cat "$TEST_DIR/.freshen/.codex-reset/active/phase" 2>/dev/null || true)"
    [ "$phase" = "$expected" ] && return 0
    sleep 0.02
    i=$((i + 1))
  done
  printf 'expected phase %s, observed %s\n' "$expected" "$phase" >&2
  return 1
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

@test "Codex readiness ignores footer text and requires an empty input row" {
  printf '/new' > "$TEST_DIR/pane-input"
  run bash -c '. "$1"; codex_pane_wait_ready %%1' _ "$CODEX_HOOKS/pane-ready.sh"
  [ "$status" -eq 1 ]
  : > "$TEST_DIR/pane-input"
  run bash -c '. "$1"; codex_pane_wait_ready %%1' _ "$CODEX_HOOKS/pane-ready.sh"
  [ "$status" -eq 0 ]
}

@test "Codex readiness treats the new-session placeholder as an empty input row" {
  printf 'Ask Codex to do anything' > "$TEST_DIR/pane-input"
  run bash -c '. "$1"; codex_pane_wait_ready %%1' _ "$CODEX_HOOKS/pane-ready.sh"
  [ "$status" -eq 0 ]
}

@test "Codex input comparison ignores prompt UI padding around literal text" {
  run bash -c '. "$1"; codex_input_row_from_content "$2"' _ \
    "$CODEX_HOOKS/pane-ready.sh" $'OpenAI Codex\n›   /new   \n100% context left'
  [ "$status" -eq 0 ]
  [ "$output" = "/new" ]
}

@test "Codex input comparison joins hard-wrapped prompt rows before the footer" {
  run bash -c '. "$1"; codex_input_row_from_content "$2"' _ \
    "$CODEX_HOOKS/pane-ready.sh" \
    $'OpenAI Codex\n› Freshen bootstrap nonce. Run startup hooks, then end\n  this turn.\n\n  gpt-5.6-sol default · /workspace'
  [ "$status" -eq 0 ]
  [ "$output" = "Freshen bootstrap nonce. Run startup hooks, then end this turn." ]
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

@test "Codex SessionStart(clear) acknowledges the journal and preserves the signal" {
  printf '%s\n%s\n' '$forge:forge resume' 'planning complete' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_claim; freshen_codex_transition claimed reset-submit-armed'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && printf "%s\n" "{\"source\":\"clear\"}" | PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" on-clear.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  run jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<< "$output"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.codex-reset/active/claimed.signal" ]
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

@test "Codex journal submits reset bootstrap and continuation once, then consumes on continuation Stop" {
  printf '%s\n%s\n' '$forge:forge resume' 'ready for execution' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  wait_for_phase bootstrap-submit-armed
  [ -f "$TEST_DIR/.freshen/.codex-reset/active/claimed.signal" ]
  run grep -c -F -- '-l /new' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
  run grep -c -F -- '-l Sending input only to fire session start hooks.' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]

  run bash -c 'cd "$1" && printf "%s\n" "{\"source\":\"startup\"}" | PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" cleanup-session-start.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  run jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<< "$output"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.codex-reset/active/claimed.signal" ]

  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  wait_for_phase continuation-submit-armed
  run grep -c -F -- '-l $forge:forge resume' "$TMUX_CALL_LOG"
  [ "$output" = "1" ]
  [ -f "$TEST_DIR/.freshen/.codex-reset/active/continuation.signal" ]

  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -d "$TEST_DIR/.freshen/.codex-reset/active" ]
  run grep -c 'phase session-start-ack' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
  run grep -c 'phase continuation-stop' "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
  run awk '
    /phase claimed/ { claimed=NR }
    /phase reset-submit-armed/ { reset=NR }
    /phase bootstrap-submit-armed/ { bootstrap=NR }
    /phase session-start-ack/ { ack=NR }
    /phase bootstrap-stop/ { stop=NR }
    /phase continuation-submit-armed/ { continuation=NR }
    /phase continuation-stop/ { done=NR }
    END { exit !(claimed < reset && reset < bootstrap && bootstrap < ack && ack < stop && stop < continuation && continuation < done) }
  ' "$TEST_DIR/.freshen/transitions.log"
  [ "$status" -eq 0 ]
}

@test "same-source requeue is isolated from the initial claim through continuation" {
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_claim'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$TEST_DIR/.freshen/.codex-reset/active/claimed.signal")" = '$forge:forge resume' ]
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_transition claimed bootstrap-stop; freshen_codex_claim_continuation_signal >/dev/null; freshen_codex_transition bootstrap-stop continuation-submit-armed'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_consume_and_retire'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ "$(head -1 "$TEST_DIR/.freshen/forge.signal")" = '$forge:forge resume' ]
  [ ! -d "$TEST_DIR/.freshen/.codex-reset/active" ]
  find "$TEST_DIR/.freshen/.codex-reset" -maxdepth 1 -type d -name 'completed-*' | grep -q .
}

@test "Codex status and cancellation include the atomically claimed journal signal" {
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_claim'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]

  run bash -c 'cd "$1" && TMUX=1 TMUX_PANE=%%1 bash "$2" status' _ "$TEST_DIR" "$CODEX_CLI"
  [ "$status" -eq 0 ]
  [[ "$output" == *'forge (in-flight claimed): $forge:forge resume'* ]]

  run bash -c 'cd "$1" && TMUX=1 TMUX_PANE=%%1 bash "$2" cancel --source forge' _ "$TEST_DIR" "$CODEX_CLI"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelled signal from 'forge'"* ]]
  [ ! -d "$TEST_DIR/.freshen/.codex-reset/active" ]
  run find "$TEST_DIR/.freshen/.codex-reset" -maxdepth 1 -type d -name 'cancelled-*' -print -quit
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ ! -e "$output/claimed.signal" ]
  [ ! -e "$output/continuation.signal" ]
}

@test "Codex queue permits same-source next cycle but rejects another source while active" {
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_claim'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]

  run bash -c 'cd "$1" && TMUX=1 TMUX_PANE=%%1 bash "$2" queue next --source forge' _ "$TEST_DIR" "$CODEX_CLI"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$TEST_DIR/.freshen/forge.signal")" = next ]

  run bash -c 'cd "$1" && TMUX=1 TMUX_PANE=%%1 bash "$2" queue other --source issue' _ "$TEST_DIR" "$CODEX_CLI"
  [ "$status" -eq 1 ]
  [[ "$output" == *"signal already in flight from 'forge'"* ]]
  [ ! -f "$TEST_DIR/.freshen/issue.signal" ]
}

@test "journal binds the tmux socket and pane while allowing tmux metadata changes" {
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX="/tmp/freshen.sock,111,0" TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_claim; TMUX="/tmp/freshen.sock,222,7" freshen_codex_validate'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/.freshen/.codex-reset/active/tmux_socket")" = "/tmp/freshen.sock" ]
}

@test "ordinary Codex startup preserves a queued signal" {
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  touch "$TEST_DIR/.freshen/.clear-pending" "$TEST_DIR/.freshen/.clear-consumed"
  run bash -c 'cd "$1" && printf "%s\n" "{\"source\":\"startup\"}" | PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" cleanup-session-start.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ ! -f "$TEST_DIR/.freshen/.clear-consumed" ]
}

@test "wrong SessionStart source fails closed with signal and audit intact" {
  printf '%s\n' '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 CODEX_HOOK_DIR="$2/hooks/codex" CODEX_PLUGIN_DIR="$2" bash -c '\'' . "$CODEX_HOOK_DIR/lifecycle-state.sh"; freshen_codex_claim; freshen_codex_transition claimed bootstrap-submit-armed'\''' _ "$TEST_DIR" "$FRESHEN_ROOT"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && printf "%s\n" "{\"source\":\"resume\"}" | PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 bash "$3" cleanup-session-start.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/.codex-reset/active/claimed.signal" ]
  [ "$(cat "$TEST_DIR/.freshen/.codex-reset/active/phase")" = failed-unexpected-session-start-resume ]
  grep -q 'signal preserved' "$TEST_DIR/.freshen/.codex-reset/active/audit.log"
}

@test "deferred Codex worker is bounded and preserves the signal when the pane stays busy" {
  echo '$forge:forge resume' > "$TEST_DIR/.freshen/forge.signal"
  touch "$TEST_DIR/pane-busy"
  run bash -c 'cd "$1" && PLUGIN_ROOT="$2" TMUX=1 TMUX_PANE=%%1 FRESHEN_CODEX_DEFERRED_ATTEMPTS=1 bash "$3" on-stop.sh' _ "$TEST_DIR" "$FRESHEN_ROOT" "$DISPATCH"
  [ "$status" -eq 0 ]
  wait_for_phase failed-reset-prompt-timeout
  [ -f "$TEST_DIR/.freshen/.codex-reset/active/claimed.signal" ]
  run grep -c '^send-keys' "$TMUX_CALL_LOG"
  [ "$output" = "0" ]
}
