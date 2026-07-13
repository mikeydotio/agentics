#!/usr/bin/env bash
# rca-forensics.sh — read-only git archaeology for an RCA investigation.
#
# Usage:
#   rca-forensics.sh blame    --file F --lines A,B [--rev R]
#   rca-forensics.sh pickaxe  --term T [--regex] [--since D] [--paths P ...]
#   rca-forensics.sh intro    --file F --lines A,B
#   rca-forensics.sh timeline [--since D] [--limit 50] [--paths P ...]
#
# blame     Unique commits owning lines A..B of F (each with the `lines` it owns).
# pickaxe   Commits that added/removed the string T (--regex ⇒ -G regex search).
# intro     SZZ-lite: commits that last touched lines A..B (candidates, newest
#           first) plus each one's parent for context.
# timeline  Commits touching --paths in chronological (oldest-first) order.
#
# All modes run against the current repo (cwd) and never write. Output shape:
#   {ok, mode, commits:[{sha,short,date,author,subject,files_touched,...}], ...}
#   (intro uses `candidates` instead of `commits`).
# Errors: no_jq, no_git, not_a_git_repo, bad_args, bad_subcommand.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }
emit_err() { jq -n --arg e "$1" --arg d "${2:-}" '{ok:false, error:$e, detail:$d}'; exit 1; }
command -v git >/dev/null 2>&1 || emit_err no_git "git is required"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || emit_err not_a_git_repo "not inside a git repository"

# commit_json <sha> [lines] — the shared commit object. `lines` (optional) is a
# raw string tacked on as an extra field for blame/intro.
commit_json() {
  local sha="$1" lines="${2:-}"
  local short date author subj files
  short=$(git log -1 --format=%h "$sha" 2>/dev/null || true)
  date=$(git log -1 --format=%aI "$sha" 2>/dev/null || true)
  author=$(git log -1 --format=%an "$sha" 2>/dev/null || true)
  subj=$(git log -1 --format=%s "$sha" 2>/dev/null || true)
  files=$(git diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null | jq -R . | jq -s . 2>/dev/null || printf '[]')
  if [ -n "$lines" ]; then
    jq -n --arg sha "$sha" --arg short "$short" --arg date "$date" --arg author "$author" \
          --arg subj "$subj" --argjson files "$files" --arg lines "$lines" \
      '{sha:$sha, short:$short, date:$date, author:$author, subject:$subj, files_touched:$files, lines:$lines}'
  else
    jq -n --arg sha "$sha" --arg short "$short" --arg date "$date" --arg author "$author" \
          --arg subj "$subj" --argjson files "$files" \
      '{sha:$sha, short:$short, date:$date, author:$author, subject:$subj, files_touched:$files}'
  fi
}

# ranges_of <space-separated line numbers> — compress into "a-b,c,d-e".
ranges_of() {
  printf '%s\n' "$1" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq | awk '
    NR==1 { start=$1; prev=$1; next }
    { if ($1==prev+1) { prev=$1 } else { printf "%s%s", (out?",":""), (start==prev?start:start"-"prev); out=1; start=$1; prev=$1 } }
    END { if (NR>0) printf "%s%s", (out?",":""), (start==prev?start:start"-"prev) }'
}

cmd_blame() {
  local file="" lines="" rev=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file)  file="${2:-}"; shift 2 ;;
      --lines) lines="${2:-}"; shift 2 ;;
      --rev)   rev="${2:-}"; shift 2 ;;
      *)       emit_err bad_args "unexpected argument: $1" ;;
    esac
  done
  [ -n "$file" ] || emit_err bad_args "blame requires --file"
  [ -n "$lines" ] || emit_err bad_args "blame requires --lines A,B"

  local porcelain
  porcelain=$(git blame -L "$lines" ${rev:+"$rev"} --line-porcelain -- "$file" 2>/dev/null) \
    || emit_err bad_args "git blame failed for $file:$lines${rev:+@$rev}"

  # Collect, per sha, the final-file line numbers it owns.
  local shas="" cur_sha="" cur_final=""
  local shalines_file; shalines_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$shalines_file'" EXIT
  while IFS= read -r ln; do
    case "$ln" in
      [0-9a-f]*' '*)
        # header: "<sha> <orig> <final> [<num>]"
        cur_sha=$(printf '%s' "$ln" | awk '{print $1}')
        cur_final=$(printf '%s' "$ln" | awk '{print $3}')
        if [ "${#cur_sha}" -eq 40 ]; then
          printf '%s %s\n' "$cur_sha" "$cur_final" >> "$shalines_file"
        fi ;;
    esac
  done <<< "$porcelain"

  # Unique shas in first-seen order.
  local uniq_shas; uniq_shas=$(awk '{print $1}' "$shalines_file" | awk '!seen[$0]++')
  local commits="[]" sha
  for sha in $uniq_shas; do
    local ls; ls=$(awk -v s="$sha" '$1==s{printf "%s ", $2}' "$shalines_file")
    local rng; rng=$(ranges_of "$ls")
    commits=$(printf '%s' "$commits" | jq --argjson c "$(commit_json "$sha" "$rng")" '. + [$c]')
  done

  jq -n --argjson commits "$commits" --arg file "$file" --arg lines "$lines" '
    {ok:true, mode:"blame", file:$file, lines:$lines, commits:$commits,
     display:("[rca] blame " + $file + ":" + $lines + " → " + (($commits|length)|tostring) + " commit(s)")}'
}

cmd_pickaxe() {
  local term="" regex="" since="" paths=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --term)  term="${2:-}"; shift 2 ;;
      --regex) regex=1; shift ;;
      --since) since="${2:-}"; shift 2 ;;
      --paths) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do paths+=("$1"); shift; done ;;
      *)       emit_err bad_args "unexpected argument: $1" ;;
    esac
  done
  [ -n "$term" ] || emit_err bad_args "pickaxe requires --term"

  local shas
  if [ -n "$regex" ]; then
    shas=$(git log -G"$term" --format=%H ${since:+--since="$since"} -- "${paths[@]:-.}" 2>/dev/null || true)
  else
    shas=$(git log -S"$term" --format=%H ${since:+--since="$since"} -- "${paths[@]:-.}" 2>/dev/null || true)
  fi

  local commits="[]" sha
  for sha in $shas; do
    commits=$(printf '%s' "$commits" | jq --argjson c "$(commit_json "$sha")" '. + [$c]')
  done
  jq -n --argjson commits "$commits" --arg term "$term" '
    {ok:true, mode:"pickaxe", term:$term, commits:$commits,
     display:("[rca] pickaxe \"" + $term + "\" → " + (($commits|length)|tostring) + " commit(s)")}'
}

cmd_intro() {
  local file="" lines=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file)  file="${2:-}"; shift 2 ;;
      --lines) lines="${2:-}"; shift 2 ;;
      *)       emit_err bad_args "unexpected argument: $1" ;;
    esac
  done
  [ -n "$file" ] || emit_err bad_args "intro requires --file"
  [ -n "$lines" ] || emit_err bad_args "intro requires --lines A,B"

  local porcelain
  porcelain=$(git blame -L "$lines" --line-porcelain -- "$file" 2>/dev/null) \
    || emit_err bad_args "git blame failed for $file:$lines"

  local shalines_file; shalines_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$shalines_file'" EXIT
  local ln cur_sha cur_final
  while IFS= read -r ln; do
    case "$ln" in
      [0-9a-f]*' '*)
        cur_sha=$(printf '%s' "$ln" | awk '{print $1}')
        cur_final=$(printf '%s' "$ln" | awk '{print $3}')
        [ "${#cur_sha}" -eq 40 ] && printf '%s %s\n' "$cur_sha" "$cur_final" >> "$shalines_file" ;;
    esac
  done <<< "$porcelain"

  # Candidates newest-first (by commit date). Each carries its parent for context.
  local uniq_shas; uniq_shas=$(awk '{print $1}' "$shalines_file" | awk '!seen[$0]++')
  local candidates="[]" sha
  for sha in $uniq_shas; do
    local ls rng parent ctime
    ls=$(awk -v s="$sha" '$1==s{printf "%s ", $2}' "$shalines_file")
    rng=$(ranges_of "$ls")
    parent=$(git rev-parse --verify "${sha}^" 2>/dev/null || printf '')
    ctime=$(git log -1 --format=%ct "$sha" 2>/dev/null || printf '0')
    local subj author date
    subj=$(git log -1 --format=%s "$sha" 2>/dev/null || true)
    author=$(git log -1 --format=%an "$sha" 2>/dev/null || true)
    date=$(git log -1 --format=%aI "$sha" 2>/dev/null || true)
    candidates=$(printf '%s' "$candidates" | jq \
      --arg sha "$sha" --arg subj "$subj" --arg date "$date" --arg author "$author" \
      --arg lines "$rng" --arg parent "$parent" --argjson ctime "$ctime" '
      . + [{sha:$sha, subject:$subj, date:$date, author:$author, lines:$lines,
            parent:(if $parent=="" then null else $parent end), _ct:$ctime}]')
  done
  candidates=$(printf '%s' "$candidates" | jq 'sort_by(._ct) | reverse | map(del(._ct))')

  jq -n --argjson candidates "$candidates" --arg file "$file" --arg lines "$lines" '
    {ok:true, mode:"intro", file:$file, lines:$lines, candidates:$candidates,
     display:("[rca] intro " + $file + ":" + $lines + " → " + (($candidates|length)|tostring) + " candidate(s)")}'
}

cmd_timeline() {
  local since="" limit=50 paths=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --limit) limit="${2:-50}"; shift 2 ;;
      --paths) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do paths+=("$1"); shift; done ;;
      *)       emit_err bad_args "unexpected argument: $1" ;;
    esac
  done

  local shas
  shas=$(git log --format=%H -n "$limit" --reverse ${since:+--since="$since"} -- "${paths[@]:-.}" 2>/dev/null || true)
  local commits="[]" sha
  for sha in $shas; do
    commits=$(printf '%s' "$commits" | jq --argjson c "$(commit_json "$sha")" '. + [$c]')
  done
  jq -n --argjson commits "$commits" '
    {ok:true, mode:"timeline", commits:$commits,
     display:("[rca] timeline → " + (($commits|length)|tostring) + " commit(s), oldest first")}'
}

case "${1:-}" in
  blame)    shift; cmd_blame "$@" ;;
  pickaxe)  shift; cmd_pickaxe "$@" ;;
  intro)    shift; cmd_intro "$@" ;;
  timeline) shift; cmd_timeline "$@" ;;
  *)        emit_err bad_subcommand "usage: rca-forensics.sh <blame|pickaxe|intro|timeline> ..." ;;
esac
