#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# greenlight-explore — launch a governed plan-mode explorer
#
# Spins up a DISPOSABLE git worktree on a `greenlight/scratch-*` branch, runs a
# headless `claude -p` explorer (Sonnet) inside it tagged GREENLIGHT_PLAN_EXPLORER=1
# so the greenlight PreToolUse hook becomes its sole safety arbiter, captures the
# explorer's findings, then tears the worktree + branch down.
#
# The explorer can read/run/experiment freely inside the worktree; the hook
# denies edits to the real tree and destructive commands. The worktree is
# throwaway — its purpose is research, and it is discarded before a plan is
# written.
#
# Usage:
#   greenlight-explore run --task "<question>" [options]
#     --task <str>     (required) the research task / prompt for the explorer
#     --repo <path>    repo root (default: git toplevel of cwd)
#     --model <name>   model (default: effective plan_explorer_model)
#     --name <slug>    human label for the worktree/branch (default: from --task)
#     --base <ref>     base commit for the worktree (default: HEAD)
#     --out <file>     write findings here (default: a temp file); path echoed in JSON
#     --keep           keep the worktree + branch afterward (default: remove)
#     --timeout <sec>  wall-clock cap for the explorer if `timeout` is available
#
# Output: a single JSON object on stdout, e.g.
#   {"ok":true,"rc":0,"findings":"/path/notes.md","worktree":"…","branch":"greenlight/scratch-…","model":"claude-sonnet-5","kept":false}
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -o pipefail

emit_error() {   # $1 = message → JSON on stdout, then exit 1
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg e "$1" '{ok:false, error:$e}'
  else
    printf '{"ok":false,"error":"%s"}\n' "$1"
  fi
  exit 1
}

usage() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
}

VERB="${1:-}"
[ "$#" -gt 0 ] && shift
case "$VERB" in
  run) ;;
  help|-h|--help|"") usage; exit 0 ;;
  *) printf 'greenlight-explore: unknown subcommand: %s\n' "$VERB" >&2; usage >&2; exit 2 ;;
esac

# ── Parse flags ──
TASK=""; REPO=""; MODEL=""; NAME=""; BASE="HEAD"; OUT=""; KEEP=false; TIMEOUT="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task)    TASK="${2:-}"; shift 2 ;;
    --repo)    REPO="${2:-}"; shift 2 ;;
    --model)   MODEL="${2:-}"; shift 2 ;;
    --name)    NAME="${2:-}"; shift 2 ;;
    --base)    BASE="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --keep)    KEEP=true; shift ;;
    --timeout) TIMEOUT="${2:-0}"; shift 2 ;;
    *) printf 'greenlight-explore: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$TASK" ] || { printf 'greenlight-explore: --task is required\n' >&2; exit 2; }
command -v git >/dev/null 2>&1    || emit_error "git not found on PATH"
command -v claude >/dev/null 2>&1 || emit_error "claude CLI not found on PATH"
command -v jq >/dev/null 2>&1     || { printf 'greenlight-explore: jq not found\n' >&2; exit 1; }

# ── Resolve repo root ──
if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
fi
[ -n "$REPO" ] || emit_error "not inside a git repository (pass --repo)"
REPO="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || emit_error "--repo is not a git repository: $REPO"

# Creation and hook enforcement must resolve the same scratch identity.
PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"
# shellcheck source=../lib/config.sh
source "$PLUGIN_ROOT/lib/config.sh" || emit_error "Greenlight configuration reader unavailable: $PLUGIN_ROOT"
gl_config_load "$PLUGIN_ROOT" || emit_error 'Greenlight configuration is invalid; no explorer started'
SCRATCH_PREFIX="$CFG_PLAN_EXPLORER_SCRATCH_PREFIX"
WORKTREE_SEG="$CFG_PLAN_EXPLORER_WORKTREE_SEGMENT"
[ -n "$MODEL" ] || MODEL="$CFG_PLAN_EXPLORER_MODEL"

# ── Slug / branch / worktree paths ──
slugify() { printf '%s' "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-' | cut -c1-40; }
base_slug="$(slugify "${NAME:-$TASK}")"
[ -n "$base_slug" ] || base_slug="explore"
SLUG="${base_slug}-$$-$(date +%s)"
BRANCH="${SCRATCH_PREFIX}${SLUG}"
WT="${REPO}/${WORKTREE_SEG}/greenlight-scratch-${SLUG}"

# ── Findings destination ──
if [ -z "$OUT" ]; then
  OUT="$(mktemp -t greenlight-explore.XXXXXX)" || emit_error "could not create a findings temp file"
else
  mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
fi

# ── Create the disposable worktree ──
mkdir -p "$(dirname "$WT")" 2>/dev/null || true
if ! git -C "$REPO" worktree add -q -b "$BRANCH" "$WT" "$BASE" >/dev/null 2>&1; then
  emit_error "git worktree add failed (branch=$BRANCH base=$BASE)"
fi

CLEANED=false
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT`
cleanup() {
  $CLEANED && return 0
  CLEANED=true
  $KEEP && return 0
  git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true
  # Safety: only ever force-delete a branch that carries our scratch prefix.
  case "$BRANCH" in
    "${SCRATCH_PREFIX}"*) git -C "$REPO" branch -D "$BRANCH" >/dev/null 2>&1 || true ;;
  esac
}
trap cleanup EXIT

# ── Explorer charter (aligns the model with the gate so denies are rare) ──
CHARTER="You are a plan-mode explorer working in a DISPOSABLE git worktree. Any \
edits you make here are throwaway and will be discarded before the plan is written, \
so experiment freely INSIDE this directory: read code, grep, run tests and builds, \
even change code to test a hypothesis. Do NOT edit files outside this worktree and \
do NOT run destructive or system-level commands — the greenlight safety gate will \
deny them, and denials waste your turn. Finish with a concise, structured findings \
report: what you learned, the concrete evidence (files, symbols, line numbers), and \
your recommendation for the plan."

# ── Run the explorer (headless, governed by greenlight in dontAsk) ──
run_explorer() (
  cd "$WT" || exit 1
  export GREENLIGHT_PLAN_EXPLORER=1
  if [ "$TIMEOUT" != "0" ] && command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT" claude -p --model "$MODEL" --permission-mode dontAsk \
      --append-system-prompt "$CHARTER" "$TASK"
  else
    claude -p --model "$MODEL" --permission-mode dontAsk \
      --append-system-prompt "$CHARTER" "$TASK"
  fi
)
run_explorer > "$OUT" 2>/dev/null
rc=$?

# ── Report ──
kept_json=false; $KEEP && kept_json=true
jq -n \
  --arg findings "$OUT" \
  --arg wt "$WT" \
  --arg br "$BRANCH" \
  --arg model "$MODEL" \
  --argjson rc "$rc" \
  --argjson kept "$kept_json" \
  '{ok: ($rc == 0), rc: $rc, findings: $findings, worktree: $wt, branch: $br, model: $model, kept: $kept}'

exit 0
