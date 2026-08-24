#!/usr/bin/env bash
set -uo pipefail

CODEX_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_DIR="${PLUGIN_ROOT:-$(cd "$CODEX_HOOK_DIR/../.." && pwd)}"
MODE="${1:-reset}"
PARENT_PID="${2:-}"
GRACE="${FRESHEN_CODEX_DEFERRED_DELAY:-0.35}"
SETTLE="${FRESHEN_CODEX_RESET_SETTLE:-5}"
PASTE_SETTLE="${FRESHEN_CODEX_PASTE_SETTLE:-0.2}"

. "$CODEX_HOOK_DIR/lifecycle-state.sh"
. "$CODEX_HOOK_DIR/pane-ready.sh"

if [[ "$PARENT_PID" =~ ^[0-9]+$ ]]; then
  waited=0
  while kill -0 "$PARENT_PID" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.05
    waited=$((waited + 1))
  done
fi
sleep "$GRACE"

submit_once() {
  local label="$1" expected="$2" next="$3" text="$4" marker
  marker="$FRESHEN_CODEX_ACTIVE/$label-paste-attempted"
  [ ! -e "$marker" ] || { freshen_codex_fail "$label-duplicate-paste-blocked"; return 1; }
  : > "$marker" || return 1
  tmux send-keys -t "$TMUX_PANE" -l "$text" \
    || { freshen_codex_fail "$label-paste-send"; return 1; }
  sleep "$PASTE_SETTLE"
  codex_pane_input_equals "$TMUX_PANE" "$text" \
    || { freshen_codex_fail "$label-paste-verification"; return 1; }
  freshen_codex_transition "$expected" "$next" || return 1
  : > "$FRESHEN_CODEX_ACTIVE/$label-enter-attempted" || return 1
  tmux send-keys -t "$TMUX_PANE" Enter \
    || { freshen_codex_fail "$label-enter-send"; return 1; }
  freshen_codex_audit "$label submitted once"
}

freshen_codex_validate || exit 0

case "$MODE" in
  reset)
    [ "$(freshen_codex_phase)" = claimed ] \
      || { freshen_codex_fail reset-worker-wrong-phase; exit 0; }
    codex_pane_wait_stable_empty "$TMUX_PANE" \
      || { freshen_codex_fail reset-prompt-timeout; exit 0; }
    submit_once reset claimed reset-submit-armed /new || exit 0

    if [ "${FRESHEN_CODEX_TEST_ALLOW_SHORT_SETTLE:-0}" != 1 ]; then
      case "$SETTLE" in ''|*[!0-9]*|0|1|2|3|4) SETTLE=5 ;; esac
    fi
    sleep "$SETTLE"
    [ "$(freshen_codex_phase 2>/dev/null || true)" = direct-session-start-ack ] && exit 0
    freshen_codex_validate || exit 0
    [ "$(freshen_codex_phase)" = reset-submit-armed ] \
      || { freshen_codex_fail bootstrap-worker-wrong-phase; exit 0; }
    codex_pane_wait_stable_empty "$TMUX_PANE" \
      || { freshen_codex_fail bootstrap-prompt-timeout; exit 0; }
    bootstrap="$(freshen_codex_bootstrap_message)" || exit 0
    submit_once bootstrap reset-submit-armed bootstrap-submit-armed "$bootstrap" || exit 0
    ;;
  continuation)
    phase="$(freshen_codex_phase 2>/dev/null || true)"
    case "$phase" in bootstrap-stop|direct-session-start-ack) ;; *) freshen_codex_fail continuation-worker-wrong-phase; exit 0 ;; esac
    codex_pane_wait_stable_empty "$TMUX_PANE" \
      || { freshen_codex_fail continuation-prompt-timeout; exit 0; }
    signal="$(freshen_codex_claim_continuation_signal)" || exit 0
    command="$(head -1 "$signal")"
    if ! submit_once continuation "$phase" continuation-submit-armed "$command"; then
      freshen_codex_restore_continuation_signal
      exit 0
    fi
    ;;
  *) freshen_codex_fail unknown-worker-mode ;;
esac

exit 0
