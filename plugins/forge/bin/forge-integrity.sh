#!/usr/bin/env bash
# forge-integrity.sh — content-hash integrity snapshot/check around
# generator/evaluator subagent spawns (WS4/F029, F058, F064, F091, F092,
# F096). Replaces execution-loop.md's ad-hoc md5sum-of-two-files +
# `git diff --name-only` prose in Steps 3a/5a with one deterministic pair of
# calls.
#
# Usage:
#   forge-integrity.sh snapshot --phase <name> --forge-dir <dir> [--scope forge-only|full-tree] [--session-id <id>]
#   forge-integrity.sh check    --phase <name> --forge-dir <dir> [--scope forge-only|full-tree] [--session-id <id>]
#
# --phase       a label identifying which snapshot to read/write, e.g.
#               "pre-gen" or "pre-eval" — lets a story's post-generator and
#               post-evaluator checks (and consecutive stories) never collide.
# --session-id  optional (F100). Further scopes the snapshot path by the
#               caller's forge-lock.sh session id so two CONCURRENT runs
#               against the SAME project (two tmux panes, a race between a
#               resumed and a still-running session) never share one
#               snapshot per phase. `snapshot` and the matching `check` for
#               one phase must pass the same value. Omit for the prior,
#               project-only-scoped behavior.
# --scope   forge-only (default): only .forge/config.json + .forge/state.json.
#           Matches the post-generator check's actual concern — the
#           generator is EXPECTED to touch source files; only forge's own
#           bookkeeping files must be untouched.
#           full-tree: the above PLUS .forge/lock.json + .forge/verdicts.jsonl
#           PLUS every tracked file (`git ls-files`) PLUS every untracked,
#           non-ignored file (`git ls-files --others --exclude-standard`).
#           Matches the post-evaluator check's actual concern — the
#           evaluator must touch NOTHING (agents:evaluator has no Write/Edit,
#           but the general-purpose fallback path has no platform-enforced
#           restriction, so this is the real backstop there — see
#           references/execution-loop.md Step 5a).
#
# Why content hashes, not just a filename list (F092/F058): a filename-set
# diff is blind to (a) an edit to a file the generator ALREADDY modified
# before the evaluator ran (same filename in both before/after lists), and
# (b) is blind to nothing at all for brand-new untracked files, which DO show
# up here because the file list itself is diffed too, not just re-hashed
# members of a stale list. Both gaps are closed by hashing full file content
# on both sides and diffing the (path -> hash) maps.
#
# Why `git hash-object -w` (not `md5sum`/`shasum`): it is content-addressed,
# gitignore-blind (works identically for a gitignored path like
# .forge/state.json, closing F096 — `git checkout` cannot restore an ignored
# file because it was never in a tree/ref to check out FROM, but a loose blob
# object has no such requirement), portable (git is a hard dependency of
# every forge script already; no BSD/GNU md5sum-vs-md5 split to shim), and
# restorable byte-for-byte via `git cat-file -p <hash>` regardless of the
# file's tracked/ignored status. The `-w` flag writes a loose object into
# .git/objects; these are small, harmless, and eventually swept by ordinary
# `git gc` — the same tradeoff `git stash create` (WS3's interim mechanism,
# which this script supersedes) already makes.
#
# Why snapshots live under /tmp, not `.forge/` (F096, F100): storing them
# inside the git working tree risks a later `git add -A`/`git add .forge/`
# (both used elsewhere in the loop) sweeping ephemeral integrity bookkeeping
# into a story's commit — a new footgun this script must not introduce. A
# literal `/tmp` prefix (not `$TMPDIR`) is used deliberately: on macOS,
# `$TMPDIR` is Spotlight-indexed and projects that create many small files
# there rapidly can eventually stall on `mds_stores` indexing backlog,
# whereas `/private/tmp` (what `/tmp` symlinks to) is never indexed. The
# snapshot path is keyed by a hash of the project's absolute directory (not
# a fixed shared literal, unlike the prose this replaces) so concurrent runs
# against DIFFERENT projects on the same machine can never collide.
#
# F100 (remaining gap): the project-key alone does not protect two
# CONCURRENT runs against the SAME project (e.g. two tmux panes both
# running `/forge execute` in the same repo, or a resumed session racing a
# still-running one) — they'd share one snapshot file per phase and
# clobber each other's baseline. `--session-id` (optional, threaded through
# from the caller's `$SESSION_ID` — see execution-loop.md's Step 3/Step 5
# `forge-lock.sh acquire/heartbeat --session-id` calls, which already
# generate one per loop) further scopes the snapshot directory per session,
# closing that gap. Omitting it preserves the exact prior (project-only)
# behavior for any caller/test that hasn't been updated to pass it yet.
#
# Output: always one JSON object with `ok` + `display`. Always exits 0 for
# `snapshot`/`check` (callers branch on the JSON); argument errors exit 1
# with a plain stderr message (see forge-step-exit.sh's convention).
#
#   snapshot -> {ok, phase, scope, head, file_count, display}
#   check    -> {ok, tampered, changed, head_moved, head_before, head_after,
#                action, display}
#     changed  - array of {file, status: "modified"|"added"|"removed"}
#     action   - "none" (not tampered) | "restored" (tampered, files-only,
#                auto-restore succeeded) | "restore_failed" (tampered,
#                files-only, a restore step failed) | "manual_review_required"
#                (HEAD moved — never auto-reverted; see F064's own note in
#                execution-loop.md about not destroying a commit's forensic
#                trail with an automated `git reset`)
set -euo pipefail

SUBCOMMAND="${1:-}"
[ $# -gt 0 ] && shift || true

FORGE_DIR=".forge"
PHASE=""
SCOPE="forge-only"
SESSION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)   FORGE_DIR="$2"; shift 2 ;;
    --forge-dir=*) FORGE_DIR="${1#*=}"; shift ;;
    --phase)       PHASE="$2"; shift 2 ;;
    --phase=*)     PHASE="${1#*=}"; shift ;;
    --scope)       SCOPE="$2"; shift 2 ;;
    --scope=*)     SCOPE="${1#*=}"; shift ;;
    --session-id)   SESSION_ID="$2"; shift 2 ;;
    --session-id=*) SESSION_ID="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$PHASE" ] || { echo "Error: --phase is required" >&2; exit 1; }
case "$SCOPE" in
  forge-only|full-tree) ;;
  *) echo "Error: --scope must be 'forge-only' or 'full-tree' (got '$SCOPE')" >&2; exit 1 ;;
esac

emit_skip() {
  jq -n --arg reason "$1" --arg display "[forge] integrity: skipped — $1" \
    '{ok: false, error: $reason, display: $display}'
  exit 0
}

command -v git >/dev/null 2>&1 || emit_skip "git_missing"
git rev-parse --git-dir >/dev/null 2>&1 || emit_skip "not_a_git_repo"

# --- Snapshot storage location (see header comment for the /tmp rationale) ---

project_key() {
  local abs
  abs="$(pwd)"
  # No python3/shasum dependency: `git hash-object --stdin` gives a stable,
  # content-addressed digest of the path string using the same tool this
  # script already requires.
  printf '%s' "$abs" | git hash-object --stdin | cut -c1-16
}

# F100: scope the snapshot directory by session (in addition to project) so
# two concurrent runs against the SAME project never share one snapshot
# file per phase. Sanitize to a safe path segment (the session id is
# caller-supplied) rather than trusting it verbatim as a directory name;
# fall back to "default" when no session id is given (single-session
# callers and existing tests keep the prior, project-only-scoped path).
session_key() {
  if [ -z "$SESSION_ID" ]; then
    echo "default"
  else
    printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_.-' '_' | cut -c1-64
  fi
}

SNAPSHOT_DIR="/tmp/forge-integrity/$(project_key)/$(session_key)"
SNAPSHOT_FILE="$SNAPSHOT_DIR/${PHASE}.json"

# --- File list for a given scope ---

forge_only_files() {
  local f
  for f in "$FORGE_DIR/config.json" "$FORGE_DIR/state.json"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

full_tree_files() {
  forge_only_files
  local f
  for f in "$FORGE_DIR/lock.json" "$FORGE_DIR/verdicts.jsonl"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  git ls-files
  git ls-files --others --exclude-standard
}

list_files() {
  if [ "$SCOPE" = "full-tree" ]; then
    full_tree_files
  else
    forge_only_files
  fi | sort -u
}

# --- Build a {path: blob_hash} JSON map for the current working tree ---

build_hash_map() {
  local files
  files="$(list_files)"
  local pairs="{}"
  local f hash
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    hash="$(git hash-object -w -- "$f")"
    pairs="$(echo "$pairs" | jq --arg f "$f" --arg h "$hash" '.[$f] = $h')"
  done <<< "$files"
  echo "$pairs"
}

case "$SUBCOMMAND" in
  snapshot)
    mkdir -p "$SNAPSHOT_DIR"
    head_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
    files_map="$(build_hash_map)"
    file_count="$(echo "$files_map" | jq 'length')"
    jq -n \
      --arg phase "$PHASE" \
      --arg scope "$SCOPE" \
      --arg head "$head_sha" \
      --argjson files "$files_map" \
      '{phase: $phase, scope: $scope, head: $head, files: $files}' \
      > "${SNAPSHOT_FILE}.tmp" && mv "${SNAPSHOT_FILE}.tmp" "$SNAPSHOT_FILE"

    jq -n \
      --argjson ok true \
      --arg phase "$PHASE" \
      --arg scope "$SCOPE" \
      --arg head "$head_sha" \
      --argjson file_count "$file_count" \
      --arg display "[forge] integrity: snapshot '$PHASE' ($SCOPE) — $file_count file(s), HEAD=$head_sha" \
      '{ok: $ok, phase: $phase, scope: $scope, head: $head, file_count: $file_count, display: $display}'
    ;;

  check)
    [ -f "$SNAPSHOT_FILE" ] || emit_skip "no_snapshot_for_phase_${PHASE}"

    snapshot="$(cat "$SNAPSHOT_FILE")"
    head_before="$(echo "$snapshot" | jq -r '.head')"
    head_after="$(git rev-parse HEAD 2>/dev/null || echo "")"
    head_moved="false"
    [ -n "$head_before" ] && [ "$head_before" != "$head_after" ] && head_moved="true"

    current_map="$(build_hash_map)"
    snapshot_map="$(echo "$snapshot" | jq '.files')"

    # Union of paths on both sides, each tagged with its status.
    changed="$(jq -n --argjson before "$snapshot_map" --argjson after "$current_map" '
      ([$before, $after] | map(keys) | add | unique) as $all
      | [ $all[] | . as $f
          | ($before[$f] // null) as $b
          | ($after[$f] // null) as $a
          | if $b == $a then empty
            elif $b == null then {file: $f, status: "added"}
            elif $a == null then {file: $f, status: "removed"}
            else {file: $f, status: "modified"}
            end
        ]
    ')"
    changed_count="$(echo "$changed" | jq 'length')"

    tampered="false"
    [ "$changed_count" -gt 0 ] && tampered="true"
    [ "$head_moved" = "true" ] && tampered="true"

    action="none"
    if [ "$tampered" = "true" ]; then
      if [ "$head_moved" = "true" ]; then
        action="manual_review_required"
      else
        action="restored"
        while IFS= read -r entry; do
          [ -z "$entry" ] && continue
          f="$(echo "$entry" | jq -r '.file')"
          st="$(echo "$entry" | jq -r '.status')"
          if [ "$st" = "added" ]; then
            rm -f -- "$f" || action="restore_failed"
          else
            hash="$(echo "$snapshot_map" | jq -r --arg f "$f" '.[$f]')"
            mkdir -p -- "$(dirname -- "$f")"
            if ! git cat-file -p "$hash" > "$f" 2>/dev/null; then
              action="restore_failed"
            fi
          fi
        done <<< "$(echo "$changed" | jq -c '.[]')"
      fi
    fi

    display="[forge] integrity: check '$PHASE' ($SCOPE) — tampered=$tampered"
    if [ "$tampered" = "true" ]; then
      display="$display, action=$action, $changed_count file(s) changed"
      [ "$head_moved" = "true" ] && display="$display, HEAD moved $head_before -> $head_after"
    fi

    jq -n \
      --argjson ok true \
      --argjson tampered "$tampered" \
      --argjson changed "$changed" \
      --argjson head_moved "$head_moved" \
      --arg head_before "$head_before" \
      --arg head_after "$head_after" \
      --arg action "$action" \
      --arg display "$display" \
      '{ok: $ok, tampered: $tampered, changed: $changed, head_moved: $head_moved,
        head_before: $head_before, head_after: $head_after, action: $action, display: $display}'
    ;;

  *)
    echo "Unknown subcommand: $SUBCOMMAND (expected snapshot|check)" >&2
    exit 1
    ;;
esac
