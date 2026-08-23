#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapter-lib.sh"

# Codex rejects /new while the Stop hook command is active. Detach a bounded
# worker, return valid Stop JSON, and let the worker submit after this exits.
if compgen -G '.freshen/*.signal' >/dev/null \
  && [[ ! -f .freshen/.clear-pending ]] \
  && [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]]; then
  mkdir -p .freshen
  WORKER_LOG=".freshen/codex-deferred-stop.log"
  nohup bash "$CODEX_HOOK_DIR/deferred-stop.sh" "$$" \
    >> "$WORKER_LOG" 2>&1 < /dev/null &
  echo "freshen: scheduled Codex /new after Stop hook completion" >&2
elif compgen -G '.freshen/*.signal' >/dev/null \
  && [[ -z "${TMUX:-}" || -z "${TMUX_PANE:-}" ]]; then
  echo "freshen: Codex CLI tmux pane unavailable; leaving continuation signal for manual /new" >&2
fi

printf '{}\n'
