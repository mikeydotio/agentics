#!/usr/bin/env bash
# forge-step-exit.sh — Post-handoff commit and freshen queue
# Usage: forge-step-exit.sh --step <name> --summary <text> --next <command>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step="" summary="" next_cmd=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)    step="$2"; shift 2 ;;
    --step=*)  step="${1#*=}"; shift ;;
    --summary) summary="$2"; shift 2 ;;
    --summary=*) summary="${1#*=}"; shift ;;
    --next)    next_cmd="$2"; shift 2 ;;
    --next=*)  next_cmd="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$step" ]     || { echo "Error: --step is required" >&2; exit 1; }
[ -n "$summary" ]  || { echo "Error: --summary is required" >&2; exit 1; }
[ -n "$next_cmd" ] || { echo "Error: --next is required" >&2; exit 1; }

# Commit .forge/ changes
commit_msg="forge(${step}): ${summary}"
git add .forge/
commit_hash=$(git commit -q -m "$commit_msg" && git rev-parse --short HEAD)
committed=true

# Try to queue freshen
freshen_queued=false
fallback_message=null

if bash "$SCRIPT_DIR/../../freshen/bin/freshen.sh" queue "$next_cmd" --source forge --summary "$summary" 2>/dev/null; then
  freshen_queued=true
else
  fallback_message="Run /clear then: ${next_cmd}"
fi

jq -n \
  --argjson ok true \
  --argjson committed "$committed" \
  --arg commit_hash "$commit_hash" \
  --argjson freshen_queued "$freshen_queued" \
  --arg fallback_msg "$fallback_message" \
  '{
    ok: $ok,
    committed: $committed,
    commit_hash: $commit_hash,
    freshen_queued: $freshen_queued,
    fallback_message: (if $fallback_msg == "null" then null else $fallback_msg end)
  }'
