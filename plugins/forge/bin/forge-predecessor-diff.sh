#!/usr/bin/env bash
# forge-predecessor-diff.sh — mechanical predecessor-diff truncation for
# just-in-time generator context (WS4/F033). Replaces execution-loop.md Step
# 2's "most recent 3 stories OR 5000 lines, whichever is smaller — model
# eyeballs it" prose. The "summarize if larger" judgment call stays with the
# model; this script only does the counting/truncation and reports whether
# it truncated.
#
# Usage:
#   forge-predecessor-diff.sh [--limit-stories <n>] [--limit-lines <n>] [--project-dir <dir>]
#
# "Stories" are identified by commit subject convention: every completed
# story is committed as `feat(<story-id>): <title>` (references/
# execution-loop.md Step 5, evaluator-pass path) — the ONLY commit that
# happens inside the execute loop's steady state. Matching that prefix (Rather
# than just "the last N commits") avoids picking up an unrelated manual
# commit a user made mid-session.
#
# Output: {ok, truncated, line_count, limit_lines, limit_stories, diff,
#          commits, display}
#   truncated  - true when line_count exceeds limit_lines. `diff` is empty in
#                that case (it is NOT meant to be pasted at that size) —
#                the model summarizes from `commits` instead.
#   line_count - the REAL line count of the full predecessor diff, even when
#                truncated, so the caller can see how much was cut.
#   diff       - full unified diff text, present only when NOT truncated.
#   commits    - array of {sha, subject} for every matched predecessor-story
#                commit considered (populated either way — useful context
#                regardless of truncation).
#
# Always exits 0 — callers branch on `ok`, matching every other bin/ script.
set -euo pipefail

PROJECT_DIR="."
LIMIT_STORIES=3
LIMIT_LINES=5000

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)    PROJECT_DIR="$2"; shift 2 ;;
    --project-dir=*)  PROJECT_DIR="${1#*=}"; shift ;;
    --limit-stories)  LIMIT_STORIES="$2"; shift 2 ;;
    --limit-stories=*) LIMIT_STORIES="${1#*=}"; shift ;;
    --limit-lines)    LIMIT_LINES="$2"; shift 2 ;;
    --limit-lines=*)  LIMIT_LINES="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

cd "$PROJECT_DIR"

emit_skip() {
  jq -n --arg reason "$1" --arg display "[forge] predecessor-diff: skipped — $1" \
    '{ok: false, truncated: false, line_count: 0, diff: "", commits: [], error: $reason, display: $display}'
  exit 0
}

command -v git >/dev/null 2>&1 || emit_skip "git_missing"
git rev-parse --git-dir >/dev/null 2>&1 || emit_skip "not_a_git_repo"

# Newest-first list of matching story commits, capped at LIMIT_STORIES.
story_log="$(git log --extended-regexp --grep='^feat\(' -n "$LIMIT_STORIES" --format='%H%x09%s' 2>/dev/null || true)"

if [ -z "$story_log" ]; then
  jq -n \
    --argjson ok true \
    --argjson truncated false \
    --argjson line_count 0 \
    --argjson limit_lines "$LIMIT_LINES" \
    --argjson limit_stories "$LIMIT_STORIES" \
    --arg diff "" \
    --argjson commits "[]" \
    --arg display "[forge] predecessor-diff: no prior story commits found" \
    '{ok: $ok, truncated: $truncated, line_count: $line_count, limit_lines: $limit_lines,
      limit_stories: $limit_stories, diff: $diff, commits: $commits, display: $display}'
  exit 0
fi

commits_json="$(printf '%s\n' "$story_log" | jq -R -s '
  split("\n") | map(select(length > 0)) | map(split("\t")) | map({sha: .[0], subject: .[1]})
')"

# Oldest of the matched batch (last line, since git log is newest-first) —
# diff from its parent through HEAD covers everything since that story,
# which is the intended "last N stories" window.
oldest_sha="$(printf '%s\n' "$story_log" | tail -1 | cut -f1)"

if git rev-parse "${oldest_sha}^" >/dev/null 2>&1; then
  base="${oldest_sha}^"
else
  # Root commit has no parent -- diff against the empty tree instead of
  # hardcoding its well-known hash (git derives it the same way we do here).
  base="$(git hash-object -t tree /dev/null)"
fi

diff_text="$(git diff "$base" HEAD -- . 2>/dev/null || true)"

if [ -z "$diff_text" ]; then
  line_count=0
else
  line_count="$(printf '%s\n' "$diff_text" | wc -l | tr -d ' ')"
fi

truncated="false"
out_diff="$diff_text"
if [ "$line_count" -gt "$LIMIT_LINES" ]; then
  truncated="true"
  out_diff=""
fi

display="[forge] predecessor-diff: $line_count line(s) across $(echo "$commits_json" | jq 'length') commit(s), truncated=$truncated"

jq -n \
  --argjson ok true \
  --argjson truncated "$truncated" \
  --argjson line_count "$line_count" \
  --argjson limit_lines "$LIMIT_LINES" \
  --argjson limit_stories "$LIMIT_STORIES" \
  --arg diff "$out_diff" \
  --argjson commits "$commits_json" \
  --arg display "$display" \
  '{ok: $ok, truncated: $truncated, line_count: $line_count, limit_lines: $limit_lines,
    limit_stories: $limit_stories, diff: $diff, commits: $commits, display: $display}'
