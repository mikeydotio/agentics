#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapter-lib.sh"
. "$CODEX_HOOK_DIR/pane-ready.sh"

INPUT="$(cat 2>/dev/null || true)"
if [[ -f .freshen/.clear-pending ]] \
  && compgen -G '.freshen/*.signal' >/dev/null \
  && [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] \
  && ! codex_pane_wait_ready "$TMUX_PANE"; then
  echo "freshen: Codex pane readiness was not confirmed before continuation; continuing with bounded send/read-back" >&2
fi
OUTPUT="$(codex_run_shared_hook on-clear.sh "$INPUT")"
codex_emit_session_start "$OUTPUT"
