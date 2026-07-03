#!/usr/bin/env bash
# forge-lock.sh — deterministic .forge/lock.json session-locking protocol
# (WS4/F030). references/session-locking.md documented acquire/heartbeat-
# staleness/release entirely as prose the model hand-executed (timestamp
# arithmetic + JSON edits) up to three times per loop iteration; this script
# is the scripted replacement.
#
# Usage:
#   forge-lock.sh acquire  --session-id <id> [--window-min <n>] [--forge-dir <dir>]
#   forge-lock.sh heartbeat --session-id <id> [--forge-dir <dir>]
#   forge-lock.sh release  [--session-id <id>] [--forge-dir <dir>]
#   forge-lock.sh check    --session-id <id> [--window-min <n>] [--forge-dir <dir>]
#
# `--window-min` (heartbeat staleness window, minutes) defaults to
# `.forge/config.json`'s `heartbeat_window_minutes` when present, else 30 —
# matching the documented default in references/session-locking.md.
#
# All date arithmetic uses jq's `now`/`todate`/`fromdate` builtins rather than
# `date -d` (GNU-only) or a python3 shell-out — jq is already a hard
# dependency of every bin/ script, so this adds no new portability surface
# (BSD `date` cannot parse arbitrary ISO-8601 strings; jq's date filters work
# identically everywhere jq runs).
#
# Output: always one JSON object with `ok` + `display`. Always exits 0 —
# callers branch on the JSON.
#
#   acquire  -> {ok, acquired, broke_stale, held_by, display}
#   heartbeat-> {ok, updated, display}
#   release  -> {ok, released, display}
#   check    -> {ok, held, stale, action:"acquire"|"exit-running"|"break", holder, age_seconds, display}
set -euo pipefail

SUBCOMMAND="${1:-}"
[ $# -gt 0 ] && shift || true

FORGE_DIR=".forge"
SESSION_ID=""
WINDOW_MIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)     FORGE_DIR="$2"; shift 2 ;;
    --forge-dir=*)   FORGE_DIR="${1#*=}"; shift ;;
    --session-id)    SESSION_ID="$2"; shift 2 ;;
    --session-id=*)  SESSION_ID="${1#*=}"; shift ;;
    --window-min)    WINDOW_MIN="$2"; shift 2 ;;
    --window-min=*)  WINDOW_MIN="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

LOCK_FILE="$FORGE_DIR/lock.json"
CONFIG_FILE="$FORGE_DIR/config.json"

resolve_window_min() {
  if [ -n "$WINDOW_MIN" ]; then
    echo "$WINDOW_MIN"
  elif [ -f "$CONFIG_FILE" ]; then
    jq -r '.heartbeat_window_minutes // 30' "$CONFIG_FILE"
  else
    echo 30
  fi
}

# A lock.json is only usable if it is syntactically valid JSON *and* carries
# a well-formed `holder` (non-empty string) and `heartbeat_at` (a string
# `fromdate` can actually parse). write_lock() always produces both together,
# but this file can also be reached by external hands (a user hand-editing a
# stuck lock.json while debugging, or a lock left by tooling that doesn't
# share this exact schema) — schema-valid-but-field-incomplete JSON must not
# reach lock_age_seconds()'s unguarded `fromdate`, which throws under
# `set -euo pipefail` and would crash every acquire/check call (the very
# first gate of every execute-loop iteration and resume). Any such file is
# therefore treated identically to "no lock present": the safe recovery is
# to let the current session acquire a fresh, complete lock rather than
# have the whole script exit non-zero without emitting the promised JSON.
read_lock() {
  if [ -f "$LOCK_FILE" ] && jq -e '
      type == "object"
      and (.holder | type) == "string" and (.holder | length > 0)
      and (.heartbeat_at | type) == "string"
      and (.heartbeat_at | fromdate | type) == "number"
    ' "$LOCK_FILE" >/dev/null 2>&1; then
    cat "$LOCK_FILE"
  else
    echo ""
  fi
}

# age_seconds of a lock's heartbeat_at, via jq's own clock+parser (portable).
lock_age_seconds() {
  local lock_json="$1"
  echo "$lock_json" | jq -r '(now - (.heartbeat_at | fromdate))'
}

write_lock() {
  local holder="$1" acquired_at="$2" heartbeat_at="$3"
  mkdir -p "$FORGE_DIR"
  jq -n \
    --arg holder "$holder" \
    --arg acquired_at "$acquired_at" \
    --arg heartbeat_at "$heartbeat_at" \
    '{holder: $holder, acquired_at: $acquired_at, heartbeat_at: $heartbeat_at}' \
    > "${LOCK_FILE}.tmp" && mv "${LOCK_FILE}.tmp" "$LOCK_FILE"
}

now_iso() {
  jq -n -r '(now | todate)'
}

case "$SUBCOMMAND" in
  # --- acquire: create the lock if absent or stale; report contention if held ---
  acquire)
    [ -n "$SESSION_ID" ] || { echo "Error: --session-id is required for acquire" >&2; exit 1; }
    window_min="$(resolve_window_min)"
    existing="$(read_lock)"
    now="$(now_iso)"

    if [ -z "$existing" ]; then
      write_lock "$SESSION_ID" "$now" "$now"
      jq -n --argjson ok true --argjson acquired true --argjson broke_stale false \
        --arg holder "$SESSION_ID" \
        --arg display "[forge] lock: acquired by $SESSION_ID (no prior lock)" \
        '{ok: $ok, acquired: $acquired, broke_stale: $broke_stale, held_by: $holder, display: $display}'
      exit 0
    fi

    holder="$(echo "$existing" | jq -r '.holder // ""')"
    age="$(lock_age_seconds "$existing")"
    stale_secs=$((window_min * 60))
    # Compare as integers -- jq's `now - fromdate` can yield a fractional
    # value; truncate toward zero via printf, matching bash integer compares.
    age_int="${age%.*}"

    if [ "$age_int" -gt "$stale_secs" ]; then
      write_lock "$SESSION_ID" "$now" "$now"
      jq -n --argjson ok true --argjson acquired true --argjson broke_stale true \
        --arg holder "$SESSION_ID" --arg prior_holder "$holder" \
        --arg display "[forge] lock: broke stale lock (holder: $holder, age: ${age_int}s > ${stale_secs}s) — acquired by $SESSION_ID" \
        '{ok: $ok, acquired: $acquired, broke_stale: $broke_stale, held_by: $holder, prior_holder: $prior_holder, display: $display}'
      exit 0
    fi

    if [ "$holder" = "$SESSION_ID" ]; then
      # Idempotent re-acquire by the same session -- treat as a no-op success.
      jq -n --argjson ok true --argjson acquired true --argjson broke_stale false \
        --arg holder "$holder" \
        --arg display "[forge] lock: already held by this session ($SESSION_ID)" \
        '{ok: $ok, acquired: $acquired, broke_stale: $broke_stale, held_by: $holder, display: $display}'
      exit 0
    fi

    jq -n --argjson ok true --argjson acquired false --argjson broke_stale false \
      --arg holder "$holder" \
      --arg display "[forge] lock: NOT acquired — work is already running in another session (holder: $holder, age: ${age_int}s)" \
      '{ok: $ok, acquired: $acquired, broke_stale: $broke_stale, held_by: $holder, display: $display}'
    ;;

  # --- heartbeat: refresh heartbeat_at for the holding session ---
  heartbeat)
    [ -n "$SESSION_ID" ] || { echo "Error: --session-id is required for heartbeat" >&2; exit 1; }
    existing="$(read_lock)"
    if [ -z "$existing" ]; then
      jq -n --argjson ok false --argjson updated false \
        --arg display "[forge] lock: heartbeat failed — no lock.json present" \
        '{ok: $ok, updated: $updated, display: $display}'
      exit 0
    fi
    holder="$(echo "$existing" | jq -r '.holder // ""')"
    if [ "$holder" != "$SESSION_ID" ]; then
      jq -n --argjson ok false --argjson updated false --arg holder "$holder" \
        --arg display "[forge] lock: heartbeat failed — lock is held by $holder, not $SESSION_ID" \
        '{ok: $ok, updated: $updated, held_by: $holder, display: $display}'
      exit 0
    fi
    acquired_at="$(echo "$existing" | jq -r '.acquired_at')"
    now="$(now_iso)"
    write_lock "$SESSION_ID" "$acquired_at" "$now"
    jq -n --argjson ok true --argjson updated true --arg ts "$now" \
      --arg display "[forge] lock: heartbeat refreshed ($now)" \
      '{ok: $ok, updated: $updated, heartbeat_at: $ts, display: $display}'
    ;;

  # --- release: delete the lock ---
  release)
    if [ ! -f "$LOCK_FILE" ]; then
      jq -n --argjson ok true --argjson released false \
        --arg display "[forge] lock: release no-op — no lock.json present" \
        '{ok: $ok, released: $released, display: $display}'
      exit 0
    fi
    if [ -n "$SESSION_ID" ]; then
      holder="$(jq -r '.holder // ""' "$LOCK_FILE" 2>/dev/null || echo "")"
      if [ -n "$holder" ] && [ "$holder" != "$SESSION_ID" ]; then
        jq -n --argjson ok false --argjson released false --arg holder "$holder" \
          --arg display "[forge] lock: release refused — lock is held by $holder, not $SESSION_ID" \
          '{ok: $ok, released: $released, held_by: $holder, display: $display}'
        exit 0
      fi
    fi
    rm -f "$LOCK_FILE"
    jq -n --argjson ok true --argjson released true \
      --arg display "[forge] lock: released" \
      '{ok: $ok, released: $released, display: $display}'
    ;;

  # --- check: read-only staleness decision (no mutation) ---
  check)
    [ -n "$SESSION_ID" ] || { echo "Error: --session-id is required for check" >&2; exit 1; }
    window_min="$(resolve_window_min)"
    existing="$(read_lock)"

    if [ -z "$existing" ]; then
      jq -n --argjson ok true --argjson held false --argjson stale false \
        --arg action "acquire" \
        --arg display "[forge] lock: check — no lock present, acquire" \
        '{ok: $ok, held: $held, stale: $stale, action: $action, display: $display}'
      exit 0
    fi

    holder="$(echo "$existing" | jq -r '.holder // ""')"
    age="$(lock_age_seconds "$existing")"
    stale_secs=$((window_min * 60))
    age_int="${age%.*}"

    if [ "$holder" = "$SESSION_ID" ]; then
      jq -n --argjson ok true --argjson held true --argjson stale false \
        --arg action "acquire" --arg holder "$holder" --argjson age "$age_int" \
        --arg display "[forge] lock: check — already held by this session" \
        '{ok: $ok, held: $held, stale: $stale, action: $action, holder: $holder, age_seconds: $age, display: $display}'
      exit 0
    fi

    if [ "$age_int" -gt "$stale_secs" ]; then
      jq -n --argjson ok true --argjson held true --argjson stale true \
        --arg action "break" --arg holder "$holder" --argjson age "$age_int" \
        --arg display "[forge] lock: check — stale (holder: $holder, age: ${age_int}s > ${stale_secs}s), break it" \
        '{ok: $ok, held: $held, stale: $stale, action: $action, holder: $holder, age_seconds: $age, display: $display}'
      exit 0
    fi

    jq -n --argjson ok true --argjson held true --argjson stale false \
      --arg action "exit-running" --arg holder "$holder" --argjson age "$age_int" \
      --arg display "[forge] lock: check — held and fresh (holder: $holder, age: ${age_int}s) — work already running" \
      '{ok: $ok, held: $held, stale: $stale, action: $action, holder: $holder, age_seconds: $age, display: $display}'
    ;;

  *)
    jq -n --arg display "[forge] lock: unknown subcommand '$SUBCOMMAND' (expected acquire|heartbeat|release|check)" \
      '{ok: false, display: $display}'
    exit 1
    ;;
esac
