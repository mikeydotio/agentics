#!/usr/bin/env bash
# forge-verdict.sh — deterministic append to .forge/verdicts.jsonl (WS4/F034).
#
# execution-loop.md's old Step 5b had the model hand-construct the JSON line
# (including its own timestamp) for every single evaluation. This script owns
# the timestamp and the line format instead.
#
# Field shape matches the ONE authoritative evaluator verdict schema in
# plugins/agents/agents/evaluator.md's "Output Format" (as unified by WS3) —
# see that file's "Storage split" note: verdicts.jsonl is the durable,
# uncapped home for the evaluator's FULL response object (no size limit,
# gitignored, local-only), while only the compact `{verdict, failures}`
# projection goes to the storyhook comment. This script writes the jsonl
# line; it has no opinion on what gets stored in storyhook.
#
# Usage:
#   forge-verdict.sh --story <id> --attempt <n> --verdict pass|fail \
#     --failures-json '[...]' [--verdict-json '<full evaluator response>'] \
#     [--forge-dir <dir>]
#
# --failures-json is always required (pass '[]' when there are none, e.g. a
#   passing verdict). It is what dry-run mode and any caller that only has
#   the compact projection can supply on its own.
# --verdict-json is optional: the FULL evaluator response object verbatim
#   (criteria_checks, edge_case_findings, security_findings, design_adherence,
#   design_drift_details, summary — see evaluator.md). When given, it is
#   used as-is for verdict_full (after confirming its own `.verdict` field
#   agrees with --verdict, so the two can't silently diverge) so the jsonl
#   line matches the unified schema exactly. When omitted, verdict_full
#   falls back to the minimal `{verdict, failures}` shape (still valid per
#   the schema — evaluator.md's fields beyond `verdict`/`failures` are not
#   marked as always-required by every consumer, just by the FULL response).
#
# Output: {ok, display, line} — `line` is the exact JSON object appended (jq
# always exits 0; callers branch on `ok`, matching every other bin/ script).
set -euo pipefail

FORGE_DIR=".forge"
STORY=""
ATTEMPT=""
VERDICT=""
FAILURES_JSON=""
VERDICT_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)       FORGE_DIR="$2"; shift 2 ;;
    --forge-dir=*)     FORGE_DIR="${1#*=}"; shift ;;
    --story)           STORY="$2"; shift 2 ;;
    --story=*)         STORY="${1#*=}"; shift ;;
    --attempt)         ATTEMPT="$2"; shift 2 ;;
    --attempt=*)       ATTEMPT="${1#*=}"; shift ;;
    --verdict)         VERDICT="$2"; shift 2 ;;
    --verdict=*)       VERDICT="${1#*=}"; shift ;;
    --failures-json)   FAILURES_JSON="$2"; shift 2 ;;
    --failures-json=*) FAILURES_JSON="${1#*=}"; shift ;;
    --verdict-json)    VERDICT_JSON="$2"; shift 2 ;;
    --verdict-json=*)  VERDICT_JSON="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

fail() {
  echo "$1" >&2
  exit 1
}

[ -n "$STORY" ]   || fail "Error: --story is required"
[ -n "$ATTEMPT" ] || fail "Error: --attempt is required"
case "$VERDICT" in
  pass|fail) ;;
  *) fail "Error: --verdict must be 'pass' or 'fail' (got '$VERDICT')" ;;
esac
[ -n "$FAILURES_JSON" ] || fail "Error: --failures-json is required (pass '[]' if none)"
echo "$FAILURES_JSON" | jq -e . >/dev/null 2>&1 || fail "Error: --failures-json is not valid JSON"

if [ -n "$VERDICT_JSON" ]; then
  echo "$VERDICT_JSON" | jq -e . >/dev/null 2>&1 || fail "Error: --verdict-json is not valid JSON"
  embedded_verdict="$(echo "$VERDICT_JSON" | jq -r '.verdict // ""')"
  if [ -n "$embedded_verdict" ] && [ "$embedded_verdict" != "$VERDICT" ]; then
    fail "Error: --verdict '$VERDICT' does not match --verdict-json's own .verdict '$embedded_verdict'"
  fi
  verdict_full="$VERDICT_JSON"
else
  verdict_full="$(jq -n --arg v "$VERDICT" --argjson f "$FAILURES_JSON" '{verdict: $v, failures: $f}')"
fi

VERDICTS_FILE="$FORGE_DIR/verdicts.jsonl"
mkdir -p "$FORGE_DIR"

line="$(jq -n -c \
  --arg story "$STORY" \
  --argjson attempt "$ATTEMPT" \
  --arg timestamp "$(jq -n -r '(now | todate)')" \
  --argjson verdict_full "$verdict_full" \
  '{story: $story, attempt: $attempt, timestamp: $timestamp, verdict_full: $verdict_full}')"

echo "$line" >> "$VERDICTS_FILE"

jq -n \
  --argjson ok true \
  --argjson line "$line" \
  --arg display "[forge] verdict: logged $STORY attempt $ATTEMPT ($VERDICT)" \
  '{ok: $ok, line: $line, display: $display}'
