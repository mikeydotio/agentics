#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapter-lib.sh"
. "$CODEX_HOOK_DIR/lifecycle-state.sh"

INPUT="$(cat 2>/dev/null || true)"
if freshen_codex_active \
  && [ "$(freshen_codex_phase 2>/dev/null || true)" = reset-submit-armed ] \
  && freshen_codex_validate \
  && freshen_codex_transition reset-submit-armed direct-session-start-ack; then
  freshen_codex_detach_worker continuation "$$"
  freshen_codex_emit_ack
fi
