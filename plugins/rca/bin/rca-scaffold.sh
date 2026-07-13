#!/usr/bin/env bash
# rca-scaffold.sh — create and mutate RCA investigation scaffolding under .rca/.
#
# Usage:
#   rca-scaffold.sh init <slug> [--description D] [--issue-provider gh|storyhook]
#                               [--issue-ref R] [--tier full|light]
#   rca-scaffold.sh set  <slug> --<key> <value> [--<key> <value> ...]
#   rca-scaffold.sh slug "<free text>"
#
# init   Create .rca/<slug>/ (+ meta.json, repro/, forensics/, experiments/) and
#        idempotently ensure the target repo .gitignore ignores .rca/ and
#        .claude/worktrees/. --tier seeds meta.tier_directive (meta.tier stays "").
# set    Merge string keys into meta.json. Dotted keys (stack.test_cmd) set nested.
# slug   Emit a deterministic slug (lowercase, non-alnum→hyphen, ≤5 words).
#
# Output: one JSON object on stdout. {ok:true,...} on success (exit 0);
#         {ok:false,"error":<snake_code>,"detail":...} on failure (exit 1).
# Errors: no_jq, no_git, not_a_git_repo, slug_exists, missing_slug, bad_args,
#         no_meta, bad_subcommand.
set -euo pipefail

emit_err() { jq -n --arg e "$1" --arg d "${2:-}" '{ok:false, error:$e, detail:$d}'; exit 1; }

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- init -------------------------------------------------------------------
cmd_init() {
  command -v git >/dev/null 2>&1 || emit_err no_git "git is required"
  local slug="" description="" issue_provider="" issue_ref="" tier_directive=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --description)    description="${2:-}"; shift 2 ;;
      --issue-provider) issue_provider="${2:-}"; shift 2 ;;
      --issue-ref)      issue_ref="${2:-}"; shift 2 ;;
      --tier)           tier_directive="${2:-}"; shift 2 ;;
      --*)              emit_err bad_args "unknown flag: $1" ;;
      *)                [ -z "$slug" ] && slug="$1" || emit_err bad_args "unexpected argument: $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || emit_err missing_slug "init requires a <slug>"

  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || emit_err not_a_git_repo "not inside a git repository"

  local dir=".rca/$slug"
  if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    emit_err slug_exists "investigation already exists: $dir"
  fi

  mkdir -p "$dir/repro" "$dir/forensics" "$dir/experiments"

  # issue → object or null
  local issue_json="null"
  if [ -n "$issue_provider" ] || [ -n "$issue_ref" ]; then
    issue_json=$(jq -n --arg p "$issue_provider" --arg r "$issue_ref" \
      '{provider:(if $p=="" then null else $p end), ref:(if $r=="" then null else $r end)}')
  fi

  jq -n --arg slug "$slug" --arg created "$(now_utc)" --arg desc "$description" \
        --arg td "$tier_directive" --argjson issue "$issue_json" '
    {slug:$slug, created_at:$created, description:$desc,
     tier:"", tier_directive:$td, issue:$issue, stack:null}' > "$dir/meta.json"

  # Idempotently ensure the target repo .gitignore ignores our artifact dirs.
  local gi="$root/.gitignore" updated=false missing=()
  local want=(".rca/" ".claude/worktrees/")
  local line
  for line in "${want[@]}"; do
    if [ -f "$gi" ] && grep -qxF "$line" "$gi" 2>/dev/null; then
      continue
    fi
    missing+=("$line")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    if [ -s "$gi" ]; then
      # terminate any unterminated final line, then a blank separator line.
      [ -n "$(tail -c1 "$gi" 2>/dev/null)" ] && printf '\n' >> "$gi"
      printf '\n' >> "$gi"
    fi
    printf '# rca plugin\n' >> "$gi"
    for line in "${missing[@]}"; do printf '%s\n' "$line" >> "$gi"; done
    updated=true
  fi

  jq -n --arg slug "$slug" --arg dir "$dir" --argjson gi "$updated" '
    {ok:true, slug:$slug, dir:$dir, gitignore_updated:$gi,
     display:("[rca] scaffolded investigation " + $slug + " at " + $dir)}'
}

# ---- set --------------------------------------------------------------------
cmd_set() {
  local slug="${1:-}"; shift || true
  [ -n "$slug" ] || emit_err missing_slug "set requires a <slug>"
  local meta=".rca/$slug/meta.json"
  [ -f "$meta" ] || emit_err no_meta "no meta.json for investigation: $slug"

  local keys=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --*)
        local key="${1#--}" value="${2:-}"
        [ $# -ge 2 ] || emit_err bad_args "flag $1 requires a value"
        local path_json
        path_json=$(printf '%s' "$key" | jq -R 'split(".")')
        local tmp; tmp=$(mktemp)
        jq --argjson p "$path_json" --arg v "$value" 'setpath($p; $v)' "$meta" > "$tmp" \
          || { rm -f "$tmp"; emit_err bad_args "failed to set key: $key"; }
        mv "$tmp" "$meta"
        keys+=("$key")
        shift 2 ;;
      *) emit_err bad_args "unexpected argument: $1" ;;
    esac
  done
  [ "${#keys[@]}" -gt 0 ] || emit_err bad_args "set requires at least one --<key> <value>"

  local keys_json; keys_json=$(printf '%s\n' "${keys[@]}" | jq -R . | jq -s .)
  jq -n --arg slug "$slug" --argjson keys "$keys_json" --slurpfile meta "$meta" '
    {ok:true, slug:$slug, updated:$keys, meta:$meta[0],
     display:("[rca] updated " + ($keys|length|tostring) + " key(s) on " + $slug)}'
}

# ---- slug -------------------------------------------------------------------
cmd_slug() {
  local text="${1:-}"
  local s
  s=$(printf '%s' "$text" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//')
  s=$(printf '%s' "$s" | awk -F- '{n=(NF>5)?5:NF; out=""; for(i=1;i<=n;i++){out=out (i>1?"-":"") $i}; print out}')
  jq -n --arg slug "$s" '{ok:true, slug:$slug}'
}

case "${1:-}" in
  init) shift; cmd_init "$@" ;;
  set)  shift; cmd_set "$@" ;;
  slug) shift; cmd_slug "$@" ;;
  *)    emit_err bad_subcommand "usage: rca-scaffold.sh <init|set|slug> ..." ;;
esac
