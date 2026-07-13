#!/usr/bin/env bash
# rca-repro.sh — run a reproduction command N times and characterize failures.
#
# Usage:
#   rca-repro.sh run --cmd "<cmd>" [--runs N=1] [--timeout SEC=600] [--dir PATH=.]
#
# Runs <cmd> via `bash -c` in PATH, N times, each bounded by a portable timeout
# (macOS has no timeout(1)). A FAILING test is a SUCCESSFUL harness run — the
# nonzero exit is data, not an error.
#
# Output on success (exit 0):
#   {ok:true, runs, failures, failure_rate, deterministic, exit_codes:[...],
#    last_failure_tail}
#   deterministic = (failure_rate is 0 or 1). failure_rate has 4 decimals.
# Errors (exit 1): no_jq, bad_args, cmd_not_found (first run exits 127),
#   timeout (any run exceeds --timeout), bad_subcommand.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }

emit_err() { jq -n --arg e "$1" --arg d "${2:-}" '{ok:false, error:$e, detail:$d}'; exit 1; }

# run_bounded <timeout_sec> <outfile> <cmd> — run cmd, capturing combined output
# to outfile; return the command's exit code, or 124 if the timeout tripped.
run_bounded() {
  local timeout="$1" outfile="$2" cmd="$3" pid elapsed=0
  bash -c "$cmd" >"$outfile" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

cmd_run() {
  local cmd="" runs=1 timeout=600 dir="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --cmd)     cmd="${2:-}"; shift 2 ;;
      --runs)    runs="${2:-1}"; shift 2 ;;
      --timeout) timeout="${2:-600}"; shift 2 ;;
      --dir)     dir="${2:-.}"; shift 2 ;;
      *)         emit_err bad_args "unexpected argument: $1" ;;
    esac
  done
  [ -n "$cmd" ] || emit_err bad_args "run requires --cmd"
  [ -d "$dir" ] || emit_err bad_args "--dir does not exist: $dir"
  case "$runs" in ''|*[!0-9]*) emit_err bad_args "--runs must be a positive integer" ;; esac
  [ "$runs" -ge 1 ] || emit_err bad_args "--runs must be >= 1"

  local workdir; workdir=$(mktemp -d "${TMPDIR:-/tmp}/rca-repro.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  local codes=() failures=0 last_fail_out="" i
  for ((i = 1; i <= runs; i++)); do
    local outfile="$workdir/run.$i" code=0
    # run_bounded's own stderr carries only job-control noise (the command's
    # output is captured to outfile); silence it so it can't clutter callers.
    run_bounded "$timeout" "$outfile" "cd $(printf '%q' "$dir") && ( $cmd )" 2>/dev/null && code=0 || code=$?
    if [ "$code" -eq 124 ]; then
      emit_err timeout "run $i exceeded ${timeout}s"
    fi
    if [ "$i" -eq 1 ] && [ "$code" -eq 127 ]; then
      emit_err cmd_not_found "command not found (exit 127): $cmd"
    fi
    codes+=("$code")
    if [ "$code" -ne 0 ]; then
      failures=$((failures + 1))
      last_fail_out="$outfile"
    fi
  done

  local tail_out=""
  [ -n "$last_fail_out" ] && tail_out=$(tail -n 30 "$last_fail_out" 2>/dev/null || true)

  local deterministic=false
  { [ "$failures" -eq 0 ] || [ "$failures" -eq "$runs" ]; } && deterministic=true

  local codes_json; codes_json=$(printf '%s\n' "${codes[@]}" | jq -s '.')

  jq -n --argjson runs "$runs" --argjson failures "$failures" \
        --argjson codes "$codes_json" --argjson det "$deterministic" \
        --arg tail "$tail_out" '
    {ok:true, runs:$runs, failures:$failures,
     failure_rate:((($failures / $runs) * 10000 | round) / 10000),
     deterministic:$det, exit_codes:$codes, last_failure_tail:$tail,
     display:("[rca] " + ($failures|tostring) + "/" + ($runs|tostring) + " runs failed"
              + (if $det then " (deterministic)" else " (flaky)" end))}'
}

case "${1:-}" in
  run) shift; cmd_run "$@" ;;
  *)   emit_err bad_subcommand "usage: rca-repro.sh run --cmd \"<cmd>\" [--runs N] [--timeout SEC] [--dir PATH]" ;;
esac
