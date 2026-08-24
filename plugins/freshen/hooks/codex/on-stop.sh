#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapter-lib.sh"
. "$CODEX_HOOK_DIR/lifecycle-state.sh"

if freshen_codex_active; then
  phase="$(freshen_codex_phase 2>/dev/null || true)"
  case "$phase" in
    session-start-ack)
      if freshen_codex_validate && freshen_codex_transition session-start-ack bootstrap-stop; then
        freshen_codex_detach_worker continuation "$$"
        echo "freshen: bootstrap complete; scheduled queued continuation" >&2
      fi
      ;;
    continuation-submit-armed)
      if freshen_codex_consume_and_retire; then
        echo "freshen: queued continuation accepted; signal consumed" >&2
        if compgen -G '.freshen/*.signal' >/dev/null && freshen_codex_claim; then
          freshen_codex_detach_worker reset "$$"
          echo "freshen: claimed next queued signal and scheduled Codex reset" >&2
        fi
      else
        echo "freshen: continuation binding changed; signal preserved" >&2
      fi
      ;;
    claimed|reset-submit-armed|bootstrap-submit-armed|bootstrap-stop|direct-session-start-ack)
      freshen_codex_audit "Stop observed in phase $phase; no duplicate worker started"
      ;;
    failed-*|cancelled-*)
      echo "freshen: Codex reset journal requires manual recovery; signal remains" >&2
      ;;
  esac
elif compgen -G '.freshen/*.signal' >/dev/null; then
  if [[ -z "${TMUX:-}" || -z "${TMUX_PANE:-}" ]]; then
    echo "freshen: Codex CLI tmux pane unavailable; leaving continuation signal for manual /new" >&2
  elif freshen_codex_claim; then
    freshen_codex_detach_worker reset "$$"
    echo "freshen: claimed signal and scheduled Codex reset after Stop" >&2
  else
    echo "freshen: Codex reset claim failed; signal remains" >&2
  fi
fi

printf '{}\n'
