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
  [ -n "${TMUX:-}" ] || die "freshen requires tmux. Claude must be running inside a tmux session."
  [ -n "${TMUX_PANE:-}" ] || die "freshen requires \$TMUX_PANE. Claude must be running inside a tmux pane."
}

cmd_queue() {
  local command="" source=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) source="$2"; shift 2 ;;
      --source=*) source="${1#*=}"; shift ;;
      *) [ -z "$command" ] && command="$1" && shift || die "unexpected argument: $1" ;;
    esac
  done

  [ -n "$command" ] || die "usage: freshen.sh queue <command> --source <name>"
  [ -n "$source" ] || die "usage: freshen.sh queue <command> --source <name>"

  require_tmux

  # Validate source name (alphanumeric + hyphens only)
  [[ "$source" =~ ^[a-zA-Z0-9_-]+$ ]] || die "source must be alphanumeric (got: $source)"

  mkdir -p "$FRESHEN_DIR"

  local signal_file="$FRESHEN_DIR/${source}.signal"

  # Warn if a signal from a DIFFERENT source already exists
  for existing in "$FRESHEN_DIR"/*.signal; do
    [ -f "$existing" ] || continue
    local existing_source
    existing_source=$(basename "$existing" .signal)
    if [ "$existing_source" != "$source" ]; then
      echo "Warning: signal already pending from '$existing_source' ($(cat "$existing"))" >&2
    fi
  done

  echo "$command" > "$signal_file"
  echo "freshen: queued '${command}' (source: ${source})"
}

cmd_status() {
  local found=0
  for signal in "$FRESHEN_DIR"/*.signal; do
    [ -f "$signal" ] || continue
    local src
    src=$(basename "$signal" .signal)
    echo "  ${src}: $(cat "$signal")"
    found=1
  done
  [ "$found" -eq 1 ] || echo "  (no pending signals)"
}

cmd_cancel() {
  local source="" all=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) source="$2"; shift 2 ;;
      --source=*) source="${1#*=}"; shift ;;
      --all) all=1; shift ;;
      *) die "unexpected argument: $1" ;;
    esac
  done

  if [ "$all" -eq 1 ]; then
    rm -f "$FRESHEN_DIR"/*.signal 2>/dev/null
    echo "freshen: all signals cancelled"
  elif [ -n "$source" ]; then
    local signal_file="$FRESHEN_DIR/${source}.signal"
    if [ -f "$signal_file" ]; then
      rm "$signal_file"
      echo "freshen: cancelled signal from '$source'"
    else
      echo "freshen: no signal from '$source'"
    fi
  else
    die "usage: freshen.sh cancel [--source <name> | --all]"
  fi
}

# Route subcommand
case "${1:-}" in
  queue)  shift; cmd_queue "$@" ;;
  status) cmd_status ;;
  cancel) shift; cmd_cancel "$@" ;;
  *)      die "usage: freshen.sh <queue|status|cancel> [args]" ;;
esac
