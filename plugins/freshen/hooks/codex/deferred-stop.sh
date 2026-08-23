#!/usr/bin/env bash
# Submit Codex's reset only after the Stop hook exits. Every loop is bounded;
# failure leaves the signal for a later Stop event instead of losing work.
set -uo pipefail

CODEX_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_PLUGIN_DIR="${PLUGIN_ROOT:-$(cd "$CODEX_HOOK_DIR/../.." && pwd)}"
PARENT_PID="${1:-}"
FRESHEN_DIR=".freshen"
ATTEMPTS="${FRESHEN_CODEX_DEFERRED_ATTEMPTS:-8}"
DELAY="${FRESHEN_CODEX_DEFERRED_DELAY:-0.35}"

. "$CODEX_HOOK_DIR/pane-ready.sh"

if [[ "$PARENT_PID" =~ ^[0-9]+$ ]]; then
  parent_wait=0
  while kill -0 "$PARENT_PID" 2>/dev/null && [[ "$parent_wait" -lt 100 ]]; do
    sleep 0.05
    parent_wait=$((parent_wait + 1))
  done
fi

# Give Codex a bounded grace period to mark the turn idle after hook exit.
sleep "$DELAY"

attempt=0
reset_confirmed=false
while [[ "$attempt" -lt "$ATTEMPTS" ]]; do
  compgen -G "$FRESHEN_DIR/*.signal" >/dev/null || exit 0
  if [[ -f "$FRESHEN_DIR/.clear-pending" ]]; then
    reset_confirmed=true
    break
  fi
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0

  if ! FRESHEN_CODEX_READY_ATTEMPTS=20 codex_pane_wait_ready "$TMUX_PANE"; then
    sleep "$DELAY"
    attempt=$((attempt + 1))
    continue
  fi

  FRESHEN_CLEAR_COMMAND=/new CLAUDE_PLUGIN_ROOT="$CODEX_PLUGIN_DIR" \
    bash "$CODEX_PLUGIN_DIR/hooks/on-stop.sh" < /dev/null || true

  content="$(tmux capture-pane -p -t "$TMUX_PANE" 2>/dev/null || true)"
  if printf '%s' "$content" | grep -Fq "'/new' is disabled while a task is in progress"; then
    rm -f "$FRESHEN_DIR/.clear-pending"
    echo "freshen: Codex still busy after Stop; retrying /new" >&2
    sleep "$DELAY"
    attempt=$((attempt + 1))
    continue
  fi

  if [[ -f "$FRESHEN_DIR/.clear-pending" ]]; then
    reset_confirmed=true
    break
  fi
  sleep "$DELAY"
  attempt=$((attempt + 1))
done

if [[ "$reset_confirmed" != true ]]; then
  echo "freshen: WARNING deferred Codex /new was not accepted; continuation signal remains" >&2
  exit 0
fi

# Current Codex releases emit SessionStart(clear), which normally consumes the
# signal. This second phase is also a recovery path for releases/surfaces that
# create the new thread without that event.
attempt=0
while [[ "$attempt" -lt "$ATTEMPTS" ]]; do
  compgen -G "$FRESHEN_DIR/*.signal" >/dev/null || exit 0
  [[ -f "$FRESHEN_DIR/.clear-pending" ]] || exit 0
  if FRESHEN_CODEX_READY_ATTEMPTS=20 codex_pane_wait_ready "$TMUX_PANE"; then
    CLAUDE_PLUGIN_ROOT="$CODEX_PLUGIN_DIR" \
      bash "$CODEX_PLUGIN_DIR/hooks/on-clear.sh" < /dev/null || true
    compgen -G "$FRESHEN_DIR/*.signal" >/dev/null || exit 0
  fi
  sleep "$DELAY"
  attempt=$((attempt + 1))
done

echo "freshen: WARNING Codex continuation was not accepted after /new; signal remains" >&2
exit 0
