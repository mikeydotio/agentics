#!/usr/bin/env bash
# rca-worktree.sh — manage the isolated git worktree an RCA investigation uses
# for bisection and experiments. Adapted from reconcile-pr's worktree lifecycle.
#
# Usage:
#   rca-worktree.sh create  <slug> [--ref HEAD] [--setup-cmd "<cmd>"] [--copy <path>]...
#   rca-worktree.sh destroy <slug>
#   rca-worktree.sh status  <slug>
#
# create   Add a worktree at <root>/.claude/worktrees/rca/<slug>/worktree on a
#          fresh branch rca/<slug> at <ref>. Each --copy <path> (relative to the
#          repo root) is copied into the same relative path inside the worktree —
#          this is how UNTRACKED repro tests travel (linked worktrees don't share
#          untracked files). --setup-cmd runs inside the worktree; on failure the
#          worktree is LEFT in place (error:setup_failed) for inspection. Writes
#          worktree.json to the state dir and, when .rca/<slug>/ exists, there too.
# destroy  Remove the worktree, prune, delete branch rca/<slug>, drop state +
#          .rca/<slug>/worktree.json. Tolerates an already-removed worktree.
# status   {ok,exists,path,branch,dirty}. dirty = worktree porcelain non-empty.
#
# The repo root is resolved via `git worktree list` (its first entry is always
# the MAIN working tree), so create works from the main tree OR another worktree.
#
# Output: one JSON object on stdout. Errors: no_jq, no_git, not_a_git_repo,
#   missing_slug, bad_args, bad_ref, worktree_add_failed, setup_failed,
#   bad_subcommand.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }
emit_err() { jq -n --arg e "$1" --arg d "${2:-}" '{ok:false, error:$e, detail:$d}'; exit 1; }
command -v git >/dev/null 2>&1 || emit_err no_git "git is required"

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# main_root — the MAIN working-tree root, resolved even from inside a linked
# worktree (git lists the main tree first in `git worktree list --porcelain`).
ROOT=""
need_root() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || emit_err not_a_git_repo "not inside a git repository"
  ROOT=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
  [ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || emit_err not_a_git_repo "not inside a git repository"
}

state_dir() { printf '%s/.claude/worktrees/rca/%s' "$ROOT" "$1"; }
wt_dir()    { printf '%s/worktree' "$(state_dir "$1")"; }
wt_branch() { printf 'rca/%s' "$1"; }

cmd_create() {
  local slug="" ref="HEAD" setup_cmd="" copies=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref)       ref="${2:-HEAD}"; shift 2 ;;
      --setup-cmd) setup_cmd="${2:-}"; shift 2 ;;
      --copy)      copies+=("${2:-}"); shift 2 ;;
      --*)         emit_err bad_args "unknown flag: $1" ;;
      *)           [ -z "$slug" ] && slug="$1" || emit_err bad_args "unexpected argument: $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || emit_err missing_slug "create requires a <slug>"
  need_root

  # Resolve the ref to a concrete commit in the CALLER's context (so HEAD means
  # the caller's HEAD, not $ROOT's) before handing it to the worktree add.
  local ref_oid
  ref_oid=$(git rev-parse --verify "${ref}^{commit}" 2>/dev/null) || emit_err bad_ref "cannot resolve ref: $ref"

  local sd wt br; sd=$(state_dir "$slug"); wt=$(wt_dir "$slug"); br=$(wt_branch "$slug")
  mkdir -p "$sd"
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$ROOT" branch -D "$br" >/dev/null 2>&1 || true

  local cap rc=0
  cap=$(git -C "$ROOT" worktree add "$wt" -B "$br" --no-track "$ref_oid" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || emit_err worktree_add_failed "$(printf '%s' "$cap" | tail -n 3)"

  # Copy untracked paths (relative to root) into the worktree.
  local copied=() p
  for p in "${copies[@]:-}"; do
    [ -n "$p" ] || continue
    if [ -e "$ROOT/$p" ]; then
      mkdir -p "$(dirname "$wt/$p")"
      cp -R "$ROOT/$p" "$wt/$p"
      copied+=("$p")
    fi
  done

  # Setup command runs inside the worktree. On failure, LEAVE the worktree.
  local setup_ran=false
  if [ -n "$setup_cmd" ]; then
    local sout src=0
    sout=$( ( cd "$wt" && bash -c "$setup_cmd" ) 2>&1 ) || src=$?
    if [ "$src" -ne 0 ]; then
      jq -n --arg slug "$slug" --arg path "$wt" --arg tail "$(printf '%s' "$sout" | tail -n 30)" '
        {ok:false, error:"setup_failed", detail:("setup-cmd exited non-zero for " + $slug),
         path:$path, tail:$tail}'
      exit 1
    fi
    setup_ran=true
  fi

  # worktree.json — state dir always; .rca/<slug>/ when it exists (relative to cwd).
  local wt_json
  wt_json=$(jq -n --arg slug "$slug" --arg path "$wt" --arg branch "$br" --arg ref "$ref_oid" --arg ts "$(now_utc)" \
    '{slug:$slug, path:$path, branch:$branch, ref:$ref, created_at:$ts}')
  printf '%s\n' "$wt_json" > "$sd/worktree.json"
  [ -d ".rca/$slug" ] && printf '%s\n' "$wt_json" > ".rca/$slug/worktree.json"

  local copied_json='[]'
  [ "${#copied[@]}" -gt 0 ] && copied_json=$(printf '%s\n' "${copied[@]}" | jq -R . | jq -s .)
  jq -n --arg path "$wt" --arg branch "$br" --arg ref "$ref_oid" --argjson setup "$setup_ran" --argjson copied "$copied_json" '
    {ok:true, path:$path, branch:$branch, ref:$ref, setup_ran:$setup, copied:$copied,
     display:("[rca] worktree ready at " + $path + " (branch " + $branch + ")")}'
}

cmd_destroy() {
  local slug="${1:-}"
  [ -n "$slug" ] || emit_err missing_slug "destroy requires a <slug>"
  need_root
  local sd wt br; sd=$(state_dir "$slug"); wt=$(wt_dir "$slug"); br=$(wt_branch "$slug")
  [ -d "$wt" ] && git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$ROOT" branch -D "$br" >/dev/null 2>&1 || true
  rm -rf "$sd"
  rm -f ".rca/$slug/worktree.json"
  jq -n --arg slug "$slug" '{ok:true, removed:true, display:("[rca] worktree for " + $slug + " removed")}'
}

cmd_status() {
  local slug="${1:-}"
  [ -n "$slug" ] || emit_err missing_slug "status requires a <slug>"
  need_root
  local wt br exists=false dirty=false; wt=$(wt_dir "$slug"); br=$(wt_branch "$slug")
  if [ -d "$wt" ]; then
    exists=true
    [ -n "$(git -C "$wt" status --porcelain 2>/dev/null || true)" ] && dirty=true
  fi
  jq -n --arg path "$wt" --arg branch "$br" --argjson exists "$exists" --argjson dirty "$dirty" '
    {ok:true, exists:$exists, path:$path, branch:$branch, dirty:$dirty,
     display:("[rca] worktree " + (if $exists then "present" else "absent" end) + " for branch " + $branch)}'
}

case "${1:-}" in
  create)  shift; cmd_create "$@" ;;
  destroy) shift; cmd_destroy "$@" ;;
  status)  shift; cmd_status "$@" ;;
  *)       emit_err bad_subcommand "usage: rca-worktree.sh <create|destroy|status> <slug> ..." ;;
esac
