#!/usr/bin/env bash
set -euo pipefail

# freshen.sh — register a post-clear re-invocation signal
#
# Usage:
#   freshen.sh queue <command> --source <name>
#   freshen.sh status
#   freshen.sh cancel [--source <name> | --all]
#
# Signal files live in .freshen/ (gitignored). Each file is named
# <source>.signal and contains the command to run after /clear.
# The freshen hooks handle the rest:
#   Stop hook      → detects signal → sends /clear via tmux
#   Post-clear hook → reads signal → nukes it → sends command via tmux

FRESHEN_DIR=".freshen"

die() { echo "Error: $*" >&2; exit 1; }

require_tmux() {
  local host_name="Claude"
  [ "${FRESHEN_HOST:-claude}" = "codex" ] && host_name="Codex"
  [ -n "${TMUX:-}" ] || die "freshen requires tmux. ${host_name} must be running inside a tmux session."
  [ -n "${TMUX_PANE:-}" ] || die "freshen requires \$TMUX_PANE. ${host_name} must be running inside a tmux pane."
}

is_disabled() {
  [ -f "$FRESHEN_DIR/.disabled" ]
}

codex_active_dir() {
  [ "${FRESHEN_HOST:-claude}" = codex ] || return 1
  [ -d "$FRESHEN_DIR/.codex-reset/active" ] || return 1
  printf '%s\n' "$FRESHEN_DIR/.codex-reset/active"
}

codex_active_source() {
  local active basename
  active="$(codex_active_dir)" || return 1
  [ -f "$active/signal_basename" ] || return 1
  basename="$(cat "$active/signal_basename")"
  case "$basename" in *.signal) printf '%s\n' "${basename%.signal}" ;; *) return 1 ;; esac
}

codex_active_signal() {
  local active
  active="$(codex_active_dir)" || return 1
  if [ -f "$active/claimed.signal" ]; then
    printf '%s\n' "$active/claimed.signal"
  elif [ -f "$active/continuation.signal" ]; then
    printf '%s\n' "$active/continuation.signal"
  else
    return 1
  fi
}

codex_cancel_active() {
  local requested="${1:-}" active source nonce destination
  active="$(codex_active_dir)" || return 1
  source="$(codex_active_source)" || return 1
  [ -z "$requested" ] || [ "$requested" = "$source" ] || return 1
  : > "$active/cancelled"
  printf 'cancelled-user\n' > "$active/phase"
  rm -f "$active/claimed.signal" "$active/continuation.signal"
  nonce="$(cat "$active/nonce" 2>/dev/null || printf '%s' "$$")"
  destination="$FRESHEN_DIR/.codex-reset/cancelled-$nonce"
  mv "$active" "$destination" || return 1
}

require_enabled() {
  if is_disabled; then
    if [ "${FRESHEN_HOST:-claude}" = "codex" ]; then
      echo "freshen: disabled — run '\$freshen:freshen enable' to re-enable" >&2
    else
      echo "freshen: disabled — run '/freshen enable' to re-enable" >&2
    fi
    exit 1
  fi
}

cmd_queue() {
  require_enabled
  local command="" source="" summary=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) source="$2"; shift 2 ;;
      --source=*) source="${1#*=}"; shift ;;
      --summary) summary="$2"; shift 2 ;;
      --summary=*) summary="${1#*=}"; shift ;;
      *) [ -z "$command" ] && command="$1" && shift || die "unexpected argument: $1" ;;
    esac
  done

  [ -n "$command" ] || die "usage: freshen.sh queue <command> --source <name> [--summary <text>]"
  [ -n "$source" ] || die "usage: freshen.sh queue <command> --source <name> [--summary <text>]"

  require_tmux

  # Validate source name (alphanumeric + hyphens only)
  [[ "$source" =~ ^[a-zA-Z0-9_-]+$ ]] || die "source must be alphanumeric (got: $source)"

  mkdir -p "$FRESHEN_DIR"

  local signal_file="$FRESHEN_DIR/${source}.signal"

  # A Codex transition owns its claimed source until continuation Stop.  The
  # same source may queue the next cycle, but a different workflow must wait.
  local active_source=""
  active_source="$(codex_active_source 2>/dev/null || true)"
  if [ -n "$active_source" ] && [ "$active_source" != "$source" ]; then
    die "signal already in flight from '$active_source'. Cancel it first with: freshen.sh cancel --source $active_source"
  fi

  # Cross-source conflict is a hard error — only one source may be pending at a time.
  # Same-source overwrite is fine (idempotent re-queue).
  for existing in "$FRESHEN_DIR"/*.signal; do
    [ -f "$existing" ] || continue
    local existing_source
    existing_source=$(basename "$existing" .signal)
    if [ "$existing_source" != "$source" ]; then
      die "signal already pending from '$existing_source' ($(cat "$existing")). Cancel it first with: freshen.sh cancel --source $existing_source"
    fi
  done

  if [ -n "$summary" ]; then
    printf '%s\n%s\n' "$command" "$summary" > "$signal_file"
  else
    echo "$command" > "$signal_file"
  fi
  echo "freshen: queued '${command}' (source: ${source})"
}

cmd_status() {
  require_enabled
  local found=0 active source phase signal
  if active="$(codex_active_dir 2>/dev/null)"; then
    source="$(codex_active_source 2>/dev/null || printf unknown)"
    phase="$(cat "$active/phase" 2>/dev/null || printf unknown)"
    signal="$(codex_active_signal 2>/dev/null || true)"
    if [ -n "$signal" ]; then
      echo "  ${source} (in-flight ${phase}): $(head -1 "$signal")"
    else
      echo "  ${source} (in-flight ${phase})"
    fi
    found=1
  fi
  for signal in "$FRESHEN_DIR"/*.signal; do
    [ -f "$signal" ] || continue
    local src
    src=$(basename "$signal" .signal)
    echo "  ${src}: $(head -1 "$signal")"
    found=1
  done
  [ "$found" -eq 1 ] || echo "  (no pending signals)"
}

cmd_cancel() {
  require_enabled
  local source="" all=0 cancelled=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) source="$2"; shift 2 ;;
      --source=*) source="${1#*=}"; shift ;;
      --all) all=1; shift ;;
      *) die "unexpected argument: $1" ;;
    esac
  done

  if [ "$all" -eq 1 ]; then
    codex_cancel_active "" 2>/dev/null && cancelled=1 || true
    rm -f "$FRESHEN_DIR"/*.signal 2>/dev/null
    echo "freshen: all signals cancelled"
  elif [ -n "$source" ]; then
    local signal_file="$FRESHEN_DIR/${source}.signal"
    codex_cancel_active "$source" 2>/dev/null && cancelled=1 || true
    if [ -f "$signal_file" ]; then
      rm "$signal_file"
      cancelled=1
    fi
    if [ "$cancelled" -eq 1 ]; then
      echo "freshen: cancelled signal from '$source'"
    else
      echo "freshen: no signal from '$source'"
    fi
  else
    die "usage: freshen.sh cancel [--source <name> | --all]"
  fi
}

cmd_disable() {
  if is_disabled; then
    echo "freshen: already disabled"
    return
  fi
  mkdir -p "$FRESHEN_DIR"
  codex_cancel_active "" 2>/dev/null || true
  rm -f "$FRESHEN_DIR"/*.signal "$FRESHEN_DIR/.clear-pending" "$FRESHEN_DIR/.clear-consumed" 2>/dev/null
  touch "$FRESHEN_DIR/.disabled"
  echo "freshen: disabled — all pending signals cancelled"
}

cmd_enable() {
  if ! is_disabled; then
    echo "freshen: already enabled"
    return
  fi
  rm -f "$FRESHEN_DIR/.disabled"
  echo "freshen: enabled"
}

# Route subcommand
case "${1:-}" in
  queue)   shift; cmd_queue "$@" ;;
  status)  cmd_status ;;
  cancel)  shift; cmd_cancel "$@" ;;
  enable)  cmd_enable ;;
  disable) cmd_disable ;;
  *)       die "usage: freshen.sh <queue|status|cancel|enable|disable> [args]" ;;
esac
