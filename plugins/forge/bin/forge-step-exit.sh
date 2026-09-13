#!/usr/bin/env bash
# forge-step-exit.sh — the ONE canonical step-exit call every pipeline skill
# uses: stage + commit .forge/ (plus any --extra-path), update state.json,
# and queue (or cancel) the freshen signal.
#
# Usage:
#   forge-step-exit.sh --step <name> --summary <text> --next <command> \
#     [--extra-path <path>]... [--transition-id <id>]
#   forge-step-exit.sh --step <name> --summary <text> --terminal \
#     [--extra-path <path>]... [--transition-id <id>]
#
# Exactly one of --next / --terminal is required:
#   --next <command>   Normal step transition. Commits, marks state.json
#                       paused with a resume pointer, and queues freshen to
#                       re-invoke <command> after /clear.
#   --terminal          Pipeline-ending exit (deploy). Commits, then CANCELS
#                       any pending forge freshen signal instead of queueing
#                       a new one — there is no next command to resume to.
#
# --host claude|codex selects native continuation delivery (default: claude).
# --extra-path <path> may be repeated. Use it when a step's commit must also
# capture changes outside .forge/ (e.g. validate committing new test files it
# wrote) instead of reaching for a broad `git add -A`, which sweeps in
# unrelated untracked files. A path that doesn't exist on disk is silently
# skipped, and skipping one does not stop the others from being staged.
#
# Storyhook is never an --extra-path: story state lives in a store outside the
# repository, so there is no repo path for a step to commit (AGE-11).
#
# --transition-id <id> (optional, agentics#33) — the `transition_id` from
# the `forge-state.sh --record-transition` JSON output the router read
# earlier this same turn, threaded through so this step's "actual" log line
# can be correlated with that "predicted" line by forge-transition-report.sh.
# Omit it (older/manual call sites) and the logged line reads
# `transition_id=none` instead of failing.
#
# Output (always exit 0 on a successful run — callers branch on the JSON):
#   {ok, committed, commit_hash, freshen_queued, freshen_cancelled, fallback_message}
#     committed         - true only if this call actually created a commit.
#                          false means nothing was staged (F053) — this is a
#                          normal, healthy outcome (e.g. a step whose only
#                          change was already committed), not a failure, and
#                          every downstream step (state update, freshen) still
#                          runs.
#     commit_hash        - short hash of HEAD after this call, whether or not
#                          this call itself created the commit.
#     freshen_queued      - true if --next was queued successfully.
#     freshen_cancelled   - true if --terminal cancelled a pending signal.
#     fallback_message    - manual /clear instructions when freshen_queued is
#                          false (no tmux) — null in --terminal mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

host=claude
step="" summary="" next_cmd="" terminal=false transition_id=""
extra_paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="${2:-}"; shift 2 ;;
    --host=*) host="${1#*=}"; shift ;;
    --step)    step="$2"; shift 2 ;;
    --step=*)  step="${1#*=}"; shift ;;
    --summary) summary="$2"; shift 2 ;;
    --summary=*) summary="${1#*=}"; shift ;;
    --next)    next_cmd="$2"; shift 2 ;;
    --next=*)  next_cmd="${1#*=}"; shift ;;
    --terminal) terminal=true; shift ;;
    --extra-path) extra_paths+=("$2"); shift 2 ;;
    --extra-path=*) extra_paths+=("${1#*=}"); shift ;;
    --transition-id) transition_id="$2"; shift 2 ;;
    --transition-id=*) transition_id="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
case "$host" in claude|codex) ;; *) echo "Error: invalid host: $host" >&2; exit 1 ;; esac
# shellcheck source=plugins/forge/bin/forge-host.sh
. "$SCRIPT_DIR/forge-host.sh"
next_cmd="$(forge_resume_command "$host" "$next_cmd")"
[ -n "$transition_id" ] || transition_id="none"

[ -n "$step" ]    || { echo "Error: --step is required" >&2; exit 1; }
[ -n "$summary" ] || { echo "Error: --summary is required" >&2; exit 1; }
if [ "$terminal" = true ]; then
  [ -z "$next_cmd" ] || { echo "Error: --next and --terminal are mutually exclusive" >&2; exit 1; }
else
  [ -n "$next_cmd" ] || { echo "Error: --next is required (or pass --terminal)" >&2; exit 1; }
fi

# AGE-104 DELIVERY GUARD BEGIN
# Refuse before staging, committing, state writes or reset queueing.
delivery=$(python3 "$SCRIPT_DIR/agent-delivery.py" status .forge/deliveries --runs)
if ! printf '%s' "$delivery" | jq -e '.ok == true and .blocked == false' >/dev/null; then
  jq -n --argjson delivery "$delivery" '{ok:false, error:"delivery_recovery_required",
    committed:false, commit_hash:null, freshen_queued:false, freshen_cancelled:false,
    fallback_message:null, delivery:$delivery, display:$delivery.display}'
  exit 0
fi
# AGE-104 DELIVERY GUARD END

# --- Stage + commit ---
#
# F053: a plain `git commit -q -m "$msg" && git rev-parse --short HEAD` aborts
# the whole script under `set -e` when there's nothing to commit (a benign,
# common case — e.g. a step whose artifacts didn't change since the last
# handoff). That silently skipped the paused-state write and the freshen
# queue below, voiding this script's whole guarantee. Guard explicitly: only
# commit when something is actually staged; either way, HEAD's hash is valid
# and every step below still runs.
commit_msg="forge(${step}): ${summary}"
git add .forge/
for p in "${extra_paths[@]+"${extra_paths[@]}"}"; do
  [ -n "$p" ] || continue
  [ -e "$p" ] && git add "$p"
done

committed=false
if ! git diff --cached --quiet; then
  git commit -q -m "$commit_msg"
  committed=true
fi
commit_hash="$(git rev-parse --short HEAD 2>/dev/null || echo "")"

# --- state.json ---
#
# handoff_file follows the universal `.forge/handoffs/handoff-<step>.md`
# naming convention (references/step-handoff.md) — every step's exit writes
# exactly this path, so it can be derived from --step rather than passed
# separately. session-start.sh's resume-context injection reads
# `.resume.handoff_file` when present (falls back gracefully when absent).
STATE_FILE=".forge/state.json"
if [ "$terminal" != true ] && [ -f "$STATE_FILE" ] && command -v jq &>/dev/null; then
  jq --arg cmd "$next_cmd" --arg sum "$summary" --arg hf "handoffs/handoff-${step}.md" \
    '.status = "paused"
     | .updated_at = (now | todate)
     | .resume = {command: $cmd, handoff_file: $hf, summary: $sum}' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# --- Freshen ---
freshen_queued=false
freshen_cancelled=false
fallback_message=null

# F047: append to the same lightweight transition audit log freshen's own
# on-stop.sh/on-clear.sh write to (.freshen/transitions.log), so a stalled
# pipeline's timeline reads as one story: which step queued/cancelled what,
# when, and (from the freshen hooks) whether it was actually confirmed sent.
# Sourced via the same resolved sibling-plugin path already used to invoke
# freshen.sh below (ground rule 5 — never a bare `plugins/freshen/...` path).
# Best-effort: if freshen isn't installed/available, skip logging silently
# rather than fail this script over pure diagnostics.
_TRANSITION_LOG_LIB="$SCRIPT_DIR/../../freshen/lib/transition-log.sh"
if [ "$host" = codex ]; then
  if log_root="$(bash "$SCRIPT_DIR/resolve-dependency.sh" freshen)"; then
    _TRANSITION_LOG_LIB="$log_root/lib/transition-log.sh"
  fi
fi
# shellcheck source=plugins/freshen/lib/transition-log.sh
[ -f "$_TRANSITION_LOG_LIB" ] && . "$_TRANSITION_LOG_LIB" || true
log_step_exit_transition() {
  declare -f freshen_log_transition >/dev/null 2>&1 && freshen_log_transition "$1" || true
}

# agentics#33: log this step-exit's "actual" line, correlated by
# transition_id with the "predicted" line forge-state.sh --record-transition
# wrote when the router read its JSON output earlier this turn (or
# transition_id=none for older/manual call sites that don't thread it
# through). Logged unconditionally, once, before the terminal/next branch
# below — which one ran is already captured by the existing queue/cancel
# line either branch logs next.
log_step_exit_transition "actual step=${step} transition_id=${transition_id}"

if [ "$terminal" = true ]; then
  # Best-effort — a terminal exit has nothing to resume to either way.
  forge_freshen "$SCRIPT_DIR/.." "$host" cancel --source forge >/dev/null && freshen_cancelled=true || true
  log_step_exit_transition "forge-step-exit: step '${step}' terminal -- freshen signal cancelled=${freshen_cancelled}"
else
  # Fully silence freshen.sh's own stdout/stderr — it prints a human-readable
  # confirmation line ("freshen: queued '...'") on success, which would
  # otherwise land BEFORE this script's own final `jq -n` JSON on stdout and
  # corrupt the output for any caller parsing it as JSON. We already
  # synthesize our own freshen_queued/fallback_message below, so none of
  # freshen.sh's own text output is needed here.
  if forge_freshen "$SCRIPT_DIR/.." "$host" queue "$next_cmd" --source forge --summary "$summary" >/dev/null; then
    freshen_queued=true
  else
    if [ "$host" = codex ]; then
      fallback_message="Start a new session (/new in Codex CLI), then: ${next_cmd}"
    else
      fallback_message="Run /clear then: ${next_cmd}"
    fi
  fi
  log_step_exit_transition "forge-step-exit: step '${step}' -> queued next '${next_cmd}' (queued=${freshen_queued})"
fi

jq -n \
  --argjson ok true \
  --argjson committed "$committed" \
  --arg commit_hash "$commit_hash" \
  --argjson freshen_queued "$freshen_queued" \
  --argjson freshen_cancelled "$freshen_cancelled" \
  --arg fallback_msg "$fallback_message" \
  '{
    ok: $ok,
    committed: $committed,
    commit_hash: $commit_hash,
    freshen_queued: $freshen_queued,
    freshen_cancelled: $freshen_cancelled,
    fallback_message: (if $fallback_msg == "null" then null else $fallback_msg end)
  }'
