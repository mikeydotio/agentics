#!/usr/bin/env bash
# Regression repro for Codex Freshen claiming lifecycle success before the
# queued continuation is accepted exactly once in the reset session.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PLUGIN_UNDER_TEST="${FRESHEN_PLUGIN_ROOT:-$SOURCE_PLUGIN_ROOT}"
SMOKE_SCRIPT="$SOURCE_PLUGIN_ROOT/tests/smoke-codex-tmux.sh"
AUTH_SOURCE="${CODEX_SMOKE_AUTH_FILE:-${CODEX_HOME:-$HOME/.codex}/auth.json}"
DIAGNOSTIC_COMMAND='Sending input only to fire session start hooks. Go ahead and end your turn once they are done.'
PRIME_COMMAND='Reply with exactly PRIME_READY and nothing else.'

for command_name in codex tmux jq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'SKIP: %s is required for the real Codex lifecycle repro\n' "$command_name"
    exit 0
  }
done

[ -f "$AUTH_SOURCE" ] || {
  printf 'SKIP: no Codex auth file at %s\n' "$AUTH_SOURCE"
  exit 0
}

[ -f "$SMOKE_SCRIPT" ] || {
  printf 'ERROR: Freshen smoke harness not found at %s\n' "$SMOKE_SCRIPT" >&2
  exit 2
}

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/freshen-codex-lifecycle-reset.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
SMOKE_OUTPUT="$TEST_ROOT/smoke-output.log"
ROLLOUT_LIST="$TEST_ROOT/rollouts.list"
MALFORMED_MESSAGES="$TEST_ROOT/malformed-messages.jsonl"
DIAGNOSTIC_MESSAGES="$TEST_ROOT/diagnostic-messages.jsonl"
BOOTSTRAP_MESSAGES="$TEST_ROOT/bootstrap-messages.jsonl"
PRIME_MESSAGES="$TEST_ROOT/prime-messages.jsonl"
PANE_CAPTURE="$TEST_ROOT/pane.txt"
FIXTURE_ROOT=""

parse_fixture_root() {
  [ -f "$SMOKE_OUTPUT" ] || return 0
  sed -n 's/^Freshen smoke fixture preserved at \(.*\)$/\1/p' "$SMOKE_OUTPUT" \
    | tail -1
}

fixture_root_is_disposable() {
  [ -n "$1" ] || return 1
  [ -d "$1" ] || return 1
  case "${1##*/}" in
    freshen-codex-tmux.*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  if [ -z "$FIXTURE_ROOT" ]; then
    FIXTURE_ROOT="$(parse_fixture_root)"
  fi

  if fixture_root_is_disposable "$FIXTURE_ROOT"; then
    if [ -x "$FIXTURE_ROOT/bin/tmux" ]; then
      "$FIXTURE_ROOT/bin/tmux" kill-server >/dev/null 2>&1 || true
    fi
    rm -rf "$FIXTURE_ROOT"
  elif [ -n "$FIXTURE_ROOT" ]; then
    printf 'WARNING: refusing to clean unexpected fixture path: %s\n' \
      "$FIXTURE_ROOT" >&2
  fi

  case "${TEST_ROOT##*/}" in
    freshen-codex-lifecycle-reset.*) rm -rf "$TEST_ROOT" ;;
    *) printf 'WARNING: refusing to clean unexpected test path: %s\n' \
         "$TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

set +e
FRESHEN_SMOKE_KEEP=1 \
  FRESHEN_SMOKE_PLUGIN_ROOT="$PLUGIN_UNDER_TEST" \
  FRESHEN_SMOKE_COMMAND="$DIAGNOSTIC_COMMAND" \
  FRESHEN_SMOKE_PRIME_COMMAND="$PRIME_COMMAND" \
  bash "$SMOKE_SCRIPT" >"$SMOKE_OUTPUT" 2>&1
smoke_status=$?
set -e

cat "$SMOKE_OUTPUT"
FIXTURE_ROOT="$(parse_fixture_root)"

if [ "$smoke_status" -ne 0 ]; then
  if grep -Eiq \
    '(tmux|socket).*(operation not permitted|permission denied)|(operation not permitted|permission denied).*(tmux|socket)' \
    "$SMOKE_OUTPUT"; then
    printf 'SKIP: the sandbox prevented the disposable tmux lifecycle run\n'
    exit 0
  fi
  printf 'ERROR: Codex lifecycle smoke exited %s before the semantic oracle\n' \
    "$smoke_status" >&2
  exit 2
fi

if grep -q '^SKIP:' "$SMOKE_OUTPUT"; then
  printf 'SKIP: the underlying Codex lifecycle smoke reported unavailable prerequisites\n'
  exit 0
fi

grep -q '^PASS: real Codex CLI completed Freshen /new and resumed queued command$' \
  "$SMOKE_OUTPUT" || {
    printf 'ERROR: lifecycle smoke returned success without its PASS marker\n' >&2
    exit 2
  }

fixture_root_is_disposable "$FIXTURE_ROOT" || {
  printf 'ERROR: could not parse the preserved smoke fixture path\n' >&2
  exit 2
}

scan_isolated_rollouts() {
  : >"$ROLLOUT_LIST"
  : >"$MALFORMED_MESSAGES"
  : >"$DIAGNOSTIC_MESSAGES"
  : >"$BOOTSTRAP_MESSAGES"
  : >"$PRIME_MESSAGES"
  if [ -d "$FIXTURE_ROOT/codex-home/sessions" ]; then
    find "$FIXTURE_ROOT/codex-home/sessions" -type f -name 'rollout-*.jsonl' \
      -print >"$ROLLOUT_LIST"
  fi

  while IFS= read -r rollout; do
    jq -c --arg rollout "$rollout" '
      def user_input_text:
        if .type == "response_item"
           and .payload.type == "message"
           and .payload.role == "user"
        then
          .payload.content[]?
          | select(.type == "input_text")
          | .text
        elif .type == "event_msg" and .payload.type == "user_message"
        then
          (.payload.message // .payload.text // empty)
        else
          empty
        end;

      user_input_text
      | select(type == "string")
      | select(
          startswith("/new") and . != "/new"
        )
      | {rollout: $rollout, prompt: .}
    ' "$rollout" >>"$MALFORMED_MESSAGES"
    jq -c --arg rollout "$rollout" --arg expected "$DIAGNOSTIC_COMMAND" '
      def user_input_text:
        if .type == "response_item"
           and .payload.type == "message"
           and .payload.role == "user"
        then
          .payload.content[]?
          | select(.type == "input_text")
          | .text
        elif .type == "event_msg" and .payload.type == "user_message"
        then
          (.payload.message // .payload.text // empty)
        else
          empty
        end;

      user_input_text
      | select(. == $expected)
      | {rollout: $rollout, prompt: .}
    ' "$rollout" >>"$DIAGNOSTIC_MESSAGES"
    jq -c --arg rollout "$rollout" --arg prime "$PRIME_COMMAND" '
      def user_input_text:
        if .type == "response_item" and .payload.type == "message" and .payload.role == "user"
        then .payload.content[]? | select(.type == "input_text") | .text
        elif .type == "event_msg" and .payload.type == "user_message"
        then (.payload.message // .payload.text // empty)
        else empty end;
      user_input_text
      | select(. == $prime)
      | {rollout: $rollout, prompt: .}
    ' "$rollout" >>"$PRIME_MESSAGES"
    jq -c --arg rollout "$rollout" '
      def user_input_text:
        if .type == "response_item" and .payload.type == "message" and .payload.role == "user"
        then .payload.content[]? | select(.type == "input_text") | .text
        elif .type == "event_msg" and .payload.type == "user_message"
        then (.payload.message // .payload.text // empty)
        else empty end;
      user_input_text
      | select(
          startswith("Sending input only to fire session start hooks.")
          and contains("Freshen reset ")
        )
      | {rollout: $rollout, prompt: .}
    ' "$rollout" >>"$BOOTSTRAP_MESSAGES"
  done <"$ROLLOUT_LIST"
}

# The smoke's transition log is synchronous, but Codex persists the resulting
# user message several seconds later. Keep the isolated pane alive while the
# rollout writer catches up, then apply the semantic oracle.
for _ in $(seq 1 40); do
  scan_isolated_rollouts
  [ ! -s "$MALFORMED_MESSAGES" ] || break
  [ "$(wc -l <"$DIAGNOSTIC_MESSAGES" | tr -d ' ')" -ge 1 ] && break
  sleep 0.25
done
scan_isolated_rollouts

PANE_ID="$("$FIXTURE_ROOT/bin/tmux" list-panes -a -F '#{pane_id}' | head -1)"
[ -n "$PANE_ID" ] || {
  printf 'ERROR: lifecycle smoke left no disposable Codex pane to inspect\n' >&2
  exit 2
}
"$FIXTURE_ROOT/bin/tmux" capture-pane -p -J -t "$PANE_ID" >"$PANE_CAPTURE"

if [ -s "$MALFORMED_MESSAGES" ]; then
  first_malformed="$(sed -n '1p' "$MALFORMED_MESSAGES")"
  printf 'FAIL: Freshen retry submitted concatenated /new commands without a reset\n' >&2
  printf 'Malformed user prompt: %s\n' \
    "$(printf '%s\n' "$first_malformed" | jq -r '.prompt')" >&2
  printf 'Isolated rollout: %s\n' \
    "$(printf '%s\n' "$first_malformed" | jq -r '.rollout')" >&2
  if [ -f "$FIXTURE_ROOT/workspace/.freshen/transitions.log" ]; then
    printf 'Relevant Freshen transition tail:\n' >&2
    tail -20 "$FIXTURE_ROOT/workspace/.freshen/transitions.log" >&2
  fi
  exit 1
fi

diagnostic_count="$(wc -l <"$DIAGNOSTIC_MESSAGES" | tr -d ' ')"
if [ "$diagnostic_count" -ne 1 ]; then
  printf 'FAIL: expected one accepted continuation after reset; observed %s\n' \
    "$diagnostic_count" >&2
  last_prompt_line="$(grep -E '^[[:space:]]*[›❯]' "$PANE_CAPTURE" | tail -1)"
  [ -n "$last_prompt_line" ] \
    && printf 'Last Codex input row: %s\n' "$last_prompt_line" >&2
  if [ -f "$FIXTURE_ROOT/workspace/.freshen/transitions.log" ]; then
    printf 'Relevant Freshen transition tail:\n' >&2
    tail -20 "$FIXTURE_ROOT/workspace/.freshen/transitions.log" >&2
  fi
  exit 1
fi

bootstrap_count="$(wc -l <"$BOOTSTRAP_MESSAGES" | tr -d ' ')"
if [ "$bootstrap_count" -ne 1 ]; then
  printf 'FAIL: expected one accepted nonce bootstrap; observed %s\n' \
    "$bootstrap_count" >&2
  exit 1
fi

prime_rollout="$(jq -r '.rollout' "$PRIME_MESSAGES" | sort -u)"
bootstrap_rollout="$(jq -r '.rollout' "$BOOTSTRAP_MESSAGES" | sort -u)"
diagnostic_rollout="$(jq -r '.rollout' "$DIAGNOSTIC_MESSAGES" | sort -u)"
if [ -z "$prime_rollout" ] \
  || [ "$prime_rollout" = "$diagnostic_rollout" ] \
  || [ "$bootstrap_rollout" != "$diagnostic_rollout" ]; then
  printf 'FAIL: prime must be in the old rollout and bootstrap + continuation in one new rollout\n' >&2
  printf 'prime=%s bootstrap=%s continuation=%s\n' \
    "$prime_rollout" "$bootstrap_rollout" "$diagnostic_rollout" >&2
  exit 1
fi

TRANSITIONS="$FIXTURE_ROOT/workspace/.freshen/transitions.log"
awk '
  /phase claimed/ { claimed=NR }
  /phase reset-submit-armed/ { reset=NR }
  /phase bootstrap-submit-armed/ { bootstrap=NR }
  /phase session-start-ack/ { ack=NR }
  /phase bootstrap-stop/ { bootstrap_stop=NR }
  /phase continuation-submit-armed/ { continuation=NR }
  /phase continuation-stop/ { continuation_stop=NR }
  END {
    exit !(claimed < reset && reset < bootstrap && bootstrap < ack \
      && ack < bootstrap_stop && bootstrap_stop < continuation \
      && continuation < continuation_stop)
  }
' "$TRANSITIONS" || {
  printf 'FAIL: Codex lifecycle transitions were missing or out of order\n' >&2
  cat "$TRANSITIONS" >&2
  exit 1
}

printf 'PASS: Codex accepted bootstrap and queued continuation exactly once in the reset rollout\n'
