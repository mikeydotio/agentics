#!/usr/bin/env bash
# rca-hotspots.sh — rank files by change risk and surface co-change couplings.
#
# Usage:
#   rca-hotspots.sh [--since 12.months] [--top 20] [--paths P ...]
#
# Hotspots: per file, commit count and churn (added+deleted lines) over --since,
# LOC (wc -l for still-existing files), score = commits * log(churn+1) * loc,
# sorted descending, top --top. Couplings: among commits touching <=20 files,
# file pairs that co-changed >=3 times, with confidence = co_changes /
# min(commits_a, commits_b), top 20 by co_changes.
#
# Output: {ok, hotspots:[{file,commits,churn,loc,score}], couplings:[{a,b,
#          co_changes,confidence}]}
# Errors: no_jq, no_git, not_a_git_repo, bad_args.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }
emit_err() { jq -n --arg e "$1" --arg d "${2:-}" '{ok:false, error:$e, detail:$d}'; exit 1; }
command -v git >/dev/null 2>&1 || emit_err no_git "git is required"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || emit_err not_a_git_repo "not inside a git repository"

SINCE="12.months"
TOP=20
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-12.months}"; shift 2 ;;
    --top)   TOP="${2:-20}"; shift 2 ;;
    --paths) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do PATHS+=("$1"); shift; done ;;
    *)       emit_err bad_args "unexpected argument: $1" ;;
  esac
done
case "$TOP" in ''|*[!0-9]*) emit_err bad_args "--top must be a positive integer" ;; esac

# ---- churn per file (adds+dels, commit count) -------------------------------
# `C <sha>` marks each commit; numstat rows are "<adds>\t<dels>\t<file>".
churn_tsv=$(git log --since="$SINCE" --numstat --format='C %H' -- "${PATHS[@]:-.}" 2>/dev/null | awk '
  /^C /   { commit=$2; next }
  NF==3 {
    add=$1; del=$2; file=$3;
    if (add=="-") add=0; if (del=="-") del=0;
    churn[file]+=add+del;
    key=file SUBSEP commit;
    if (!(key in seen)) { seen[key]=1; commits[file]++ }
  }
  END { for (f in churn) printf "%s\t%d\t%d\n", f, commits[f], churn[f] }
' || true)

# Add LOC (existing files only) + score, then sort by score desc and take top N.
hotspots_tsv=""
if [ -n "$churn_tsv" ]; then
  hotspots_tsv=$(
    while IFS=$'\t' read -r file commits churn; do
      [ -n "$file" ] || continue
      local_loc=0
      [ -f "$file" ] && local_loc=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || printf '0')
      score=$(awk -v c="$commits" -v ch="$churn" -v l="$local_loc" 'BEGIN{printf "%.4f", c*log(ch+1)*l}')
      printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$commits" "$churn" "$local_loc" "$score"
    done <<< "$churn_tsv" | sort -t"$(printf '\t')" -k5 -gr | head -n "$TOP"
  )
fi

hotspots_json=$(printf '%s' "$hotspots_tsv" | jq -R -s '
  split("\n") | map(select(length>0)) | map(split("\t")) |
  map({file:.[0], commits:(.[1]|tonumber), churn:(.[2]|tonumber),
       loc:(.[3]|tonumber), score:(.[4]|tonumber)})')

# ---- co-change couplings ----------------------------------------------------
# Among commits touching <=20 files, count unordered file-pair co-occurrences;
# also count commits-per-file (denominator for confidence).
coup_tsv=$(git log --since="$SINCE" --format='C %H' --name-only -- "${PATHS[@]:-.}" 2>/dev/null | awk '
  function process(   i,j,a,b,t) {
    for (i=1;i<=nf;i++) fcount[files[i]]++
    if (nf>=2 && nf<=20) {
      for (i=1;i<=nf;i++) for (j=i+1;j<=nf;j++) {
        a=files[i]; b=files[j];
        if (a>b) { t=a; a=b; b=t }
        pair[a SUBSEP b]++
      }
    }
    nf=0
  }
  /^C / { process(); next }
  /^$/  { next }
  { files[++nf]=$0 }
  END {
    process();
    for (p in pair) {
      cc=pair[p];
      if (cc>=3) {
        split(p, ab, SUBSEP); a=ab[1]; b=ab[2];
        m=fcount[a]; if (fcount[b]<m) m=fcount[b];
        conf=(m>0)?cc/m:0;
        printf "%d\t%s\t%s\t%.2f\n", cc, a, b, conf
      }
    }
  }
' | sort -t"$(printf '\t')" -k1 -nr | head -n 20 || true)

couplings_json=$(printf '%s' "$coup_tsv" | jq -R -s '
  split("\n") | map(select(length>0)) | map(split("\t")) |
  map({a:.[1], b:.[2], co_changes:(.[0]|tonumber), confidence:(.[3]|tonumber)})')

jq -n --argjson hotspots "$hotspots_json" --argjson couplings "$couplings_json" '
  {ok:true, hotspots:$hotspots, couplings:$couplings,
   display:("[rca] " + (($hotspots|length)|tostring) + " hotspot(s), "
            + (($couplings|length)|tostring) + " coupling(s)")}'
