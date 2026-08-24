#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapter-lib.sh"
. "$CODEX_HOOK_DIR/lifecycle-state.sh"

INPUT="$(cat 2>/dev/null || true)"
if freshen_codex_active; then
  source_name="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)"
  phase="$(freshen_codex_phase 2>/dev/null || true)"
  if [ "$source_name" = startup ] \
    && [ "$phase" = bootstrap-submit-armed ] \
    && freshen_codex_validate \
    && freshen_codex_transition bootstrap-submit-armed session-start-ack; then
    freshen_codex_emit_ack
  elif [ "$source_name" != startup ]; then
    freshen_codex_fail "unexpected-session-start-${source_name:-missing}"
  else
    freshen_codex_audit "startup ignored in phase ${phase:-missing}; signal preserved"
  fi
else
  # Codex can restart while a workflow signal is still queued.  Clear only
  # host-transition markers here; unlike Claude's ordinary startup cleanup,
  # never discard a Codex continuation signal merely because the CLI relaunched.
  rm -f .freshen/.clear-pending .freshen/.clear-consumed 2>/dev/null || true
fi
