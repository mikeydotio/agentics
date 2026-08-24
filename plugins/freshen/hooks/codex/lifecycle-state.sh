#!/usr/bin/env bash

FRESHEN_CODEX_DIR="${FRESHEN_CODEX_DIR:-.freshen}"
FRESHEN_CODEX_RESET_ROOT="$FRESHEN_CODEX_DIR/.codex-reset"
FRESHEN_CODEX_ACTIVE="$FRESHEN_CODEX_RESET_ROOT/active"

. "$CODEX_PLUGIN_DIR/lib/transition-log.sh"

freshen_codex_active() { [ -d "$FRESHEN_CODEX_ACTIVE" ]; }
freshen_codex_field() { [ -f "$FRESHEN_CODEX_ACTIVE/$1" ] && cat "$FRESHEN_CODEX_ACTIVE/$1"; }

freshen_codex_write_field() {
  local name="$1" value="$2" tmp="$FRESHEN_CODEX_ACTIVE/.$1.$$"
  printf '%s\n' "$value" > "$tmp" && mv -f "$tmp" "$FRESHEN_CODEX_ACTIVE/$name"
}

freshen_codex_checksum() {
  [ -f "$1" ] || return 1
  set -- $(cksum < "$1")
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  printf '%s:%s\n' "$1" "$2"
}

freshen_codex_audit() {
  local message="$1" nonce="unknown" now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ -f "$FRESHEN_CODEX_ACTIVE/nonce" ] && nonce="$(cat "$FRESHEN_CODEX_ACTIVE/nonce")"
  freshen_codex_active && printf '%s %s\n' "$now" "$message" >> "$FRESHEN_CODEX_ACTIVE/audit.log" 2>/dev/null || true
  freshen_log_transition "codex-reset[$nonce]: $message"
}

freshen_codex_phase() { freshen_codex_field phase; }

freshen_codex_transition() {
  local expected="$1" next="$2" current
  current="$(freshen_codex_phase 2>/dev/null || true)"
  [ "$current" = "$expected" ] || {
    freshen_codex_audit "transition rejected: expected $expected, found ${current:-missing}, requested $next"
    return 1
  }
  freshen_codex_write_field phase "$next" || return 1
  freshen_codex_audit "phase $next"
}

freshen_codex_fail() {
  local reason="$1" safe current
  safe="$(printf '%s' "$reason" | tr -c 'a-zA-Z0-9_-' '-')"
  current="$(freshen_codex_phase 2>/dev/null || true)"
  case "$current" in failed-*|cancelled-*) freshen_codex_audit "additional failure: $reason"; return 0 ;; esac
  freshen_codex_write_field failure "$reason" || true
  freshen_codex_write_field phase "failed-$safe" || true
  freshen_codex_audit "failure: $reason; signal preserved"
}

freshen_codex_find_signal() {
  local signal
  signal="$(ls -tr "$FRESHEN_CODEX_DIR"/*.signal 2>/dev/null | head -1)" || true
  [ -n "$signal" ] && printf '%s\n' "$signal"
}

freshen_codex_claim() {
  local signal claimed basename checksum nonce cwd
  [ ! -f "$FRESHEN_CODEX_DIR/.disabled" ] || return 1
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 1
  signal="$(freshen_codex_find_signal)" || return 1
  basename="$(basename "$signal")"
  cwd="$(pwd -P)"
  nonce="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM:-0}"
  mkdir -p "$FRESHEN_CODEX_RESET_ROOT" || return 1
  mkdir "$FRESHEN_CODEX_ACTIVE" 2>/dev/null || return 1
  claimed="$FRESHEN_CODEX_ACTIVE/claimed.signal"
  if ! mv "$signal" "$claimed"; then
    rmdir "$FRESHEN_CODEX_ACTIVE" 2>/dev/null || true
    return 1
  fi
  checksum="$(freshen_codex_checksum "$claimed")" || {
    freshen_codex_fail claimed-signal-checksum
    return 1
  }
  freshen_codex_write_field nonce "$nonce" \
    && freshen_codex_write_field signal_basename "$basename" \
    && freshen_codex_write_field signal_checksum "$checksum" \
    && freshen_codex_write_field tmux_socket "${TMUX%%,*}" \
    && freshen_codex_write_field pane "$TMUX_PANE" \
    && freshen_codex_write_field cwd "$cwd" \
    && freshen_codex_write_field claimed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    && freshen_codex_write_field phase claimed || {
      freshen_codex_fail journal-initialization
      return 1
    }
  freshen_codex_audit "phase claimed; signal=$basename checksum=$checksum pane=$TMUX_PANE"
}

freshen_codex_claimed_signal() {
  printf '%s/claimed.signal\n' "$FRESHEN_CODEX_ACTIVE"
}

freshen_codex_bound_signal() {
  local basename
  basename="$(freshen_codex_field signal_basename)" || return 1
  case "$basename" in */*|''|.|..) return 1 ;; esac
  printf '%s/%s\n' "$FRESHEN_CODEX_DIR" "$basename"
}

freshen_codex_validate_context() {
  local expected_tmux expected_pane expected_cwd
  freshen_codex_active || return 1
  [ ! -f "$FRESHEN_CODEX_ACTIVE/cancelled" ] || { freshen_codex_fail cancelled; return 1; }
  [ ! -f "$FRESHEN_CODEX_DIR/.disabled" ] || { freshen_codex_fail disabled; return 1; }
  expected_tmux="$(freshen_codex_field tmux_socket)" || return 1
  expected_pane="$(freshen_codex_field pane)" || return 1
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] \
    && [ "${TMUX%%,*}" = "$expected_tmux" ] && [ "$TMUX_PANE" = "$expected_pane" ] \
    || { freshen_codex_fail tmux-binding-mismatch; return 1; }
  expected_cwd="$(freshen_codex_field cwd)" || return 1
  [ "$(pwd -P)" = "$expected_cwd" ] || { freshen_codex_fail cwd-binding-mismatch; return 1; }
}

freshen_codex_validate() {
  local signal expected actual
  freshen_codex_validate_context || return 1
  signal="$(freshen_codex_claimed_signal)"
  [ -f "$signal" ] || { freshen_codex_fail claimed-signal-missing; return 1; }
  expected="$(freshen_codex_field signal_checksum)" || return 1
  actual="$(freshen_codex_checksum "$signal")" || return 1
  [ "$actual" = "$expected" ] || { freshen_codex_fail signal-changed; return 1; }
}

freshen_codex_bootstrap_message() {
  printf "Sending input only to fire session start hooks. Go ahead and end your turn once they're done. Freshen reset %s.\n" \
    "$(freshen_codex_field nonce)"
}

freshen_codex_emit_ack() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Freshen reset startup acknowledged. End this bootstrap turn now; the queued continuation will follow."}}'
}

freshen_codex_detach_worker() {
  nohup bash "$CODEX_HOOK_DIR/deferred-stop.sh" "$1" "$2" \
    >> "$FRESHEN_CODEX_DIR/codex-deferred-stop.log" 2>&1 < /dev/null &
}

freshen_codex_claim_continuation_signal() {
  local claimed inflight expected actual
  freshen_codex_validate || return 1
  claimed="$(freshen_codex_claimed_signal)"
  inflight="$FRESHEN_CODEX_ACTIVE/continuation.signal"
  [ ! -e "$inflight" ] || { freshen_codex_fail continuation-already-claimed; return 1; }
  mv "$claimed" "$inflight" || { freshen_codex_fail continuation-claim-move; return 1; }
  expected="$(freshen_codex_field signal_checksum)" || return 1
  actual="$(freshen_codex_checksum "$inflight" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    [ -e "$claimed" ] || mv "$inflight" "$claimed" 2>/dev/null || true
    freshen_codex_fail signal-changed-during-claim
    return 1
  fi
  freshen_codex_audit "continuation signal claimed into journal"
  printf '%s\n' "$inflight"
}

freshen_codex_restore_continuation_signal() {
  local claimed inflight
  claimed="$(freshen_codex_claimed_signal)"
  inflight="$FRESHEN_CODEX_ACTIVE/continuation.signal"
  [ -f "$inflight" ] || return 0
  if [ ! -e "$claimed" ]; then
    mv "$inflight" "$claimed" 2>/dev/null || true
    freshen_codex_audit "failed continuation signal restored inside journal"
  else
    freshen_codex_audit "failed continuation signal retained in journal; claim path is occupied"
  fi
}

freshen_codex_consume_and_retire() {
  local inflight expected actual nonce destination
  freshen_codex_validate_context || return 1
  inflight="$FRESHEN_CODEX_ACTIVE/continuation.signal"
  [ -f "$inflight" ] || { freshen_codex_fail continuation-claim-missing; return 1; }
  expected="$(freshen_codex_field signal_checksum)" || return 1
  actual="$(freshen_codex_checksum "$inflight" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    freshen_codex_fail claimed-signal-changed
    return 1
  fi
  freshen_codex_transition continuation-submit-armed continuation-stop || return 1
  freshen_codex_write_field retired_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  nonce="$(freshen_codex_field nonce)" || nonce="$$"
  destination="$FRESHEN_CODEX_RESET_ROOT/completed-$nonce"
  mv "$FRESHEN_CODEX_ACTIVE" "$destination" || { freshen_codex_fail journal-retire; return 1; }
  freshen_log_transition "codex-reset[$nonce]: retired completed journal"
}
