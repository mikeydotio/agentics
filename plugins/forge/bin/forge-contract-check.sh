#!/usr/bin/env bash
# forge-contract-check.sh — F103 regression guard: keeps every forge doc/skill
# that documents `story` invocations honest against the REAL storyhook CLI.
#
# This exists because forge's storyhook contract drifted silently once before
# (id-first `story HP-N is done` forms and a `precedes`/`follows` relationship
# vocabulary that never existed — see references/storyhook-contract.md's
# history). Nothing detected that drift until an audit read the CLI source by
# hand. This script is the automated version of that read: it never
# hardcodes a verb or relationship list — it asks the live `story` binary.
#
# What it checks, for every fenced ```...``` code block in
# <docs-root>/references/*.md and <docs-root>/skills/*/SKILL.md:
#   1. Every `story <word>` invocation's <word> must be a real dispatchable
#      verb — i.e. one `story --help`'s usage block actually lists. An
#      id-first form like `story HP-N is done` fails this because `HP-N`
#      is not a verb (exactly how the real CLI would reject it: "unknown
#      command `HP-N`").
#   2. Every `story relate|unrelate|link|unlink <a> <relationship> <b>`
#      invocation's <relationship> must be one of the relationship types
#      `story help relate` documents (the CLI's own enforced vocabulary —
#      see storyhook's src/domain.rs `relation_edges`).
#   3. Every `story <verb> <subcommand>` invocation whose <verb> is a
#      two-token dispatch target (`project`, `state`, `hooks`, `type`, …)
#      must name a <subcommand> that verb actually has. storyhook's
#      surface is NOT a flat verb namespace, and checking only the first
#      token is how the `project init` -> `project new` rename passed this
#      guard unseen: `project` is real, so `story project init` validated.
#
# Ground truth resolution (never hardcoded — see Ground rule 4 in the
# hardening plan: derive from the live binary so this stays correct as
# storyhook's CLI evolves):
#   1. $STORYHOOK_BIN, if set and executable (lets tests/CI pin a specific
#      build without touching PATH).
#   2. `story` on PATH (what forge actually invokes at runtime — the most
#      production-accurate ground truth).
#   If neither resolves, the check is skipped (ok:false) rather than failing
#   the gate on an environment problem — mirrors forge-dag-validate.sh.
#
# Usage: forge-contract-check.sh [docs-root]
#   docs-root defaults to the forge plugin root (one level up from bin/).
#   Tests point this at a throwaway fixture tree shaped like
#   <root>/references/*.md and <root>/skills/*/SKILL.md.
#
# Output (always exit 0 — callers branch on the JSON, not the exit code):
#   {ok, contract_ok, verb_violations, relation_violations,
#    real_verbs, real_relations, files_scanned, story_source, display}
#     ok                 - true if the check ran to completion (a `story`
#                          binary was found and its help output parsed).
#                          false means the check was skipped, not that the
#                          contract is clean.
#     contract_ok        - true if zero violations were found. Only
#                          meaningful when ok is true. THIS is the
#                          regression-guard pass/fail signal.
#     verb_violations    - array of {file, line, verb, command}. `verb` is
#                          always a SINGLE token; a bad subcommand under a
#                          real verb is reported separately (below), because
#                          "unknown verb 'project'" would be a false claim.
#     relation_violations- array of {file, line, relation, command}.
#     subcommand_violations
#                        - array of {file, line, verb, subcommand, command}.
#     real_subcommands   - object mapping each ENFORCED verb to its real
#                          subcommand list. Its key set IS the enforcement
#                          domain: a verb absent from it is never checked in
#                          position 2. Emitted so an operator debugging a
#                          misfire can read the derivation instead of
#                          reverse-engineering it.
#     story_source       - which resolution path found the CLI (env/path).
#     display            - human-readable summary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# ── Resolve the ground-truth `story` binary ──

STORY_BIN=""
STORY_SOURCE=""
if [[ -n "${STORYHOOK_BIN:-}" && -x "${STORYHOOK_BIN}" ]]; then
  STORY_BIN="$STORYHOOK_BIN"
  STORY_SOURCE="STORYHOOK_BIN"
elif command -v story >/dev/null 2>&1; then
  STORY_BIN="$(command -v story)"
  STORY_SOURCE="PATH"
fi

if [[ -z "$STORY_BIN" ]]; then
  jq -n '{ok: false, contract_ok: false, verb_violations: [], relation_violations: [],
          subcommand_violations: [],
          real_verbs: [], real_relations: [], real_subcommands: {},
          files_scanned: [], story_source: "",
          error: "story_cli_missing",
          display: "[forge] contract check skipped: `story` CLI not found (set STORYHOOK_BIN or install via the storyhook-install skill)"}'
  exit 0
fi

# ── Derive the real verb list from `story --help`'s usage block ──
#
# Every usage line looks like "  story <verb> ...". Taking the second
# whitespace-separated field of every such line, deduped, is the complete
# set of first-token dispatch targets `parse_invocation` recognizes.

real_verbs_out="$("$STORY_BIN" --help 2>&1 || true)"
REAL_VERBS_JSON="$(printf '%s\n' "$real_verbs_out" \
  | grep -E '^[[:space:]]{2}story ' \
  | awk '{print $2}' \
  | sort -u \
  | jq -R -s 'split("\n") | map(select(length > 0))')"

if [[ "$(echo "$REAL_VERBS_JSON" | jq 'length')" -eq 0 ]]; then
  jq -n --arg src "$STORY_SOURCE" \
    '{ok: false, contract_ok: false, verb_violations: [], relation_violations: [],
      subcommand_violations: [],
      real_verbs: [], real_relations: [], real_subcommands: {},
      files_scanned: [], story_source: $src,
      error: "story_help_unparseable",
      display: "[forge] contract check skipped: could not parse a verb list from `story --help`"}'
  exit 0
fi

# ── Derive the real relationship vocabulary from `story help relate` ──
#
# The command's own help text documents its enforced vocabulary as a
# "Relationship types:" block, one relation (or inverse pair joined by " / ")
# per line, description after an em dash. Strip the description, split on
# "/", and the survivors are the CLI's real relationship types — see
# storyhook's src/domain.rs `relation_edges` for where this is enforced.

real_relate_help="$("$STORY_BIN" help relate 2>&1 || true)"
REAL_RELATIONS_JSON="$(printf '%s\n' "$real_relate_help" \
  | sed -n '/Relationship types:/,/^[[:space:]]*$/p' | tail -n +2 \
  | sed 's/—.*//' \
  | tr '/' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | grep -vE '^$' \
  | sort -u \
  | jq -R -s 'split("\n") | map(select(length > 0))')"

if [[ "$(echo "$REAL_RELATIONS_JSON" | jq 'length')" -eq 0 ]]; then
  jq -n --arg src "$STORY_SOURCE" --argjson verbs "$REAL_VERBS_JSON" \
    '{ok: false, contract_ok: false, verb_violations: [], relation_violations: [],
      subcommand_violations: [],
      real_verbs: $verbs, real_relations: [], real_subcommands: {},
      files_scanned: [], story_source: $src,
      error: "story_relate_help_unparseable",
      display: "[forge] contract check skipped: could not parse a relationship vocabulary from `story help relate`"}'
  exit 0
fi

is_valid_verb() {
  echo "$REAL_VERBS_JSON" | jq -e --arg v "$1" 'index($v) != null' >/dev/null
}
is_valid_relation() {
  echo "$REAL_RELATIONS_JSON" | jq -e --arg r "$1" 'index($r) != null' >/dev/null
}

# ── Derive the real SUBCOMMAND vocabulary for every verb that has one ──
#
# storyhook's surface is not a flat verb namespace: `story project new`,
# `story state add`, `story hooks install` and friends are two-token
# dispatch targets. Validating only the first token is exactly how the
# `story project init` -> `story project new` rename passed this guard
# unseen — `project` is a real verb, so the dead form validated clean.
#
# Ground truth is the UNION of both help surfaces, because neither is
# complete alone (measured against storyhook 2.x):
#   - `story --help`'s usage block is the only source for `type add`,
#     `state add`, `member add`, `store new`, `epic *` and `plugin *`:
#     `story help <verb>` does not exist for those verbs at all.
#   - `story help <verb>`'s synopsis is the only source for `web status`,
#     which the global usage block omits.
#
# The union has a structural property worth stating, because it bounds
# how this code can fail: the global block lists every one of the eleven
# subcommand-bearing verbs, so it is an enforcement FLOOR that per-verb
# help can only add to. Any per-verb degradation — a cosmetic restyle, an
# early synopsis truncation, a removed help topic — shrinks only the
# additive contribution. That is a false negative (a missed rename). It
# can never narrow the enforced set below the global block and so cannot
# manufacture a false positive, which would red the pre-push gate
# repo-wide. Global help failing IS fatal, and already fails loud via the
# `story_help_unparseable` exit above.
#
# Two harvesting rules keep prose out of the vocabulary:
#   1. SYNOPSIS REGIONS ONLY. For per-verb help that is the leading run of
#      lines up to the first blank one. `story help hooks` line 4 is the
#      prose "story events occur (create, state change, close, etc.)" — an
#      ordinary sentence that happened to wrap onto a line starting with
#      "story ". Harvested naively it invents a verb `events`.
#   2. THE FIRST TOKEN MUST ALREADY BE A REAL VERB. Belt to rule 1's
#      braces: whatever prose still slips through can only widen a
#      vocabulary or mark a verb open — never narrow one. Every parse
#      failure therefore degrades to a false negative by construction.
#
# A verb is ENFORCED only when every documented form puts a literal word
# in position 2. One placeholder, flag, parenthetical or bare form
# (`story tui`, `story move <id> <state>`, `story summary`) marks the verb
# OPEN: it takes free-form arguments there, so position 2 is unknowable
# and is never checked.

REAL_VERBS_SPACED=" $(echo "$REAL_VERBS_JSON" | jq -r 'join(" ")') "

# Emit "<verb>\t<position-2 token>" for each usage line of $1 matching $2.
# $3 restricts the harvest to one verb ("" = any real verb).
#
# Everything right of the first " | " is discarded. That form lists
# alternative continuations whose implicit prefix is unrecoverable —
# `story project link origin [URL] | link checkout [PATH]` repeats its
# depth-2 token while `story project settings list | get <key>` omits it,
# with nothing in the text to tell the two apart — so only the first
# segment can be attributed with certainty.
harvest_usage_rows() {
  local text="$1" line_re="$2" want="$3"
  local line left
  printf '%s\n' "$text" | grep -E "$line_re" | while IFS= read -r line; do
    left="${line%% | *}"
    local tok=()
    read -ra tok <<< "$left"
    [[ "${tok[0]:-}" == "story" ]] || continue
    [[ -n "${tok[1]:-}" ]] || continue
    [[ -z "$want" || "${tok[1]}" == "$want" ]] || continue
    [[ "$REAL_VERBS_SPACED" == *" ${tok[1]} "* ]] || continue
    printf '%s\t%s\n' "${tok[1]}" "${tok[2]:-}"
  done
}

SUBCOMMAND_ROWS="$(harvest_usage_rows "$real_verbs_out" '^[[:space:]]{2}story ' '' || true)"

while IFS= read -r hv; do
  [[ -z "$hv" ]] && continue
  verb_help="$("$STORY_BIN" help "$hv" 2>/dev/null || true)"
  [[ -n "$verb_help" ]] || continue
  synopsis="$(printf '%s\n' "$verb_help" \
    | awk 'BEGIN{keep=1} /^[[:space:]]*$/{keep=0} keep{print}' || true)"
  [[ -n "$synopsis" ]] || continue
  verb_rows="$(harvest_usage_rows "$synopsis" '^story ' "$hv" || true)"
  if [[ -n "$verb_rows" ]]; then
    SUBCOMMAND_ROWS="${SUBCOMMAND_ROWS}${SUBCOMMAND_ROWS:+$'\n'}${verb_rows}"
  fi
done < <(echo "$REAL_VERBS_JSON" | jq -r '.[]')

# Classify: a verb survives only with >=1 literal and 0 open signals.
ENFORCED_ROWS="$(printf '%s\n' "$SUBCOMMAND_ROWS" | awk -F'\t' '
  function literal(s) { return s ~ /^[A-Za-z][A-Za-z0-9._-]*(\|[A-Za-z][A-Za-z0-9._-]*)*$/ }
  $1 == "" { next }
  {
    if ($2 == "" || !literal($2)) { open[$1] = 1; next }
    n = split($2, parts, "|")
    for (i = 1; i <= n; i++) pair[$1 SUBSEP parts[i]] = 1
  }
  END {
    for (k in pair) {
      split(k, a, SUBSEP)
      if (!(a[1] in open)) printf "%s\t%s\n", a[1], a[2]
    }
  }' || true)"

REAL_SUBCOMMANDS_JSON="$(printf '%s\n' "$ENFORCED_ROWS" \
  | jq -R -s 'split("\n") | map(select(length > 0)) | map(split("\t"))
              | group_by(.[0])
              | map({key: .[0][0], value: (map(.[1]) | unique)})
              | from_entries')"

if [[ "$(echo "$REAL_SUBCOMMANDS_JSON" | jq 'length')" -eq 0 ]]; then
  jq -n --arg src "$STORY_SOURCE" --argjson verbs "$REAL_VERBS_JSON" \
        --argjson relations "$REAL_RELATIONS_JSON" \
    '{ok: false, contract_ok: false, verb_violations: [], relation_violations: [],
      subcommand_violations: [],
      real_verbs: $verbs, real_relations: $relations, real_subcommands: {},
      files_scanned: [], story_source: $src,
      error: "story_subcommands_unparseable",
      display: "[forge] contract check skipped: could not derive a subcommand vocabulary from `story --help` / `story help <verb>`"}'
  exit 0
fi

# A documentation wildcard rather than a dispatch target: the docs
# legitimately write `story project <subcommand>` and
# `story relate <a> <relationship> <b>`. A placeholder, flag, quoted span or
# comment in a checked slot names nothing the live CLI could validate.
is_placeholder() {
  case "${1:-}" in
    ''|-*|'<'*|'['*|'('*|'{'*|'$'*|'"'*|"'"*|'`'*|'|'*|'#'*) return 0 ;;
    *) return 1 ;;
  esac
}

verb_is_enforced() {
  echo "$REAL_SUBCOMMANDS_JSON" | jq -e --arg v "$1" 'has($v)' >/dev/null
}
is_valid_subcommand() {
  echo "$REAL_SUBCOMMANDS_JSON" | jq -e --arg v "$1" --arg s "$2" \
    '.[$v] | index($s) != null' >/dev/null
}

# ── Locate every doc that documents storyhook commands ──
#
# Scanned by directory shape, not a hand-maintained filename list — a new
# reference or skill that starts documenting `story` invocations is covered
# automatically, which is the whole point of a drift guard.

FILES=""
if [[ -d "$DOCS_ROOT/references" ]]; then
  FILES="$(find "$DOCS_ROOT/references" -maxdepth 1 -name '*.md' -type f | sort)"
fi
if [[ -d "$DOCS_ROOT/skills" ]]; then
  skill_files="$(find "$DOCS_ROOT/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f | sort)"
  if [[ -n "$skill_files" ]]; then
    FILES="$(printf '%s\n%s' "$FILES" "$skill_files" | grep -vE '^$' || true)"
  fi
fi

# ── Extract and check every `story <verb> ...` fenced-block invocation ──
#
# A line qualifies as a story invocation only when "story" appears either
# at the start of the (trimmed, optionally "$ "-prefixed) line, or right
# after a shell separator ( ( ; & | ` ). This deliberately excludes plain
# English prose that happens to contain the word "story" inside a fenced
# pseudocode/comment block (e.g. "if story reached done:") while still
# catching real invocations embedded in an aside, e.g. "next story (story
# next --json)" correctly resolves to the verb `next`, not the prose noun.
#
# Known limitation: only the first qualifying invocation per line is
# checked (no forge doc currently chains two `story` calls on one line via
# `&&`/`;` — if that ever changes, this needs a loop over repeated matches).
START_RE='^[[:space:]]*\$?[[:space:]]*story[[:space:]]+([A-Za-z][A-Za-z0-9_.-]*)(.*)$'
MID_RE='[(;&|`][[:space:]]*story[[:space:]]+([A-Za-z][A-Za-z0-9_.-]*)(.*)$'

VERB_VIOLATIONS=""
RELATION_VIOLATIONS=""
SUBCOMMAND_VIOLATIONS=""
SCANNED_FILES_JSON="[]"

add_verb_violation() {
  local rec
  rec="$(jq -n --arg file "$1" --arg line "$2" --arg verb "$3" --arg command "$4" \
    '{file: $file, line: ($line | tonumber), verb: $verb, command: $command}')"
  VERB_VIOLATIONS="${VERB_VIOLATIONS}${VERB_VIOLATIONS:+$'\n'}${rec}"
}

add_relation_violation() {
  local rec
  rec="$(jq -n --arg file "$1" --arg line "$2" --arg relation "$3" --arg command "$4" \
    '{file: $file, line: ($line | tonumber), relation: $relation, command: $command}')"
  RELATION_VIOLATIONS="${RELATION_VIOLATIONS}${RELATION_VIOLATIONS:+$'\n'}${rec}"
}

add_subcommand_violation() {
  local rec
  rec="$(jq -n --arg file "$1" --arg line "$2" --arg verb "$3" --arg subcommand "$4" \
                --arg command "$5" \
    '{file: $file, line: ($line | tonumber), verb: $verb, subcommand: $subcommand,
      command: $command}')"
  SUBCOMMAND_VIOLATIONS="${SUBCOMMAND_VIOLATIONS}${SUBCOMMAND_VIOLATIONS:+$'\n'}${rec}"
}

if [[ -n "$FILES" ]]; then
  SCANNED_FILES_JSON="$(printf '%s\n' "$FILES" | jq -R -s 'split("\n") | map(select(length > 0))')"
fi

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ -f "$f" ]] || continue
  rel_f="${f#"$DOCS_ROOT"/}"

  while IFS=$'\t' read -r lineno content; do
    [[ -z "${content:-}" ]] && continue
    trimmed="${content#"${content%%[![:space:]]*}"}"
    [[ "$trimmed" == \#* ]] && continue

    verb=""
    rest=""
    if [[ "$content" =~ $START_RE ]]; then
      verb="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
    elif [[ "$content" =~ $MID_RE ]]; then
      verb="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
    else
      continue
    fi

    if ! is_valid_verb "$verb"; then
      add_verb_violation "$rel_f" "$lineno" "$verb" "$trimmed"
      continue
    fi

    # Two-token dispatch targets: `story project new`, `story state add`.
    # Only verbs the CLI documents as taking a literal subcommand are
    # checked here; everything else accepts free-form arguments in that
    # position (see the ENFORCED/OPEN note above the derivation).
    if verb_is_enforced "$verb"; then
      read -ra subtoks <<< "$rest"
      sub="${subtoks[0]:-}"
      sub="${sub%,}"
      if ! is_placeholder "$sub" && ! is_valid_subcommand "$verb" "$sub"; then
        add_subcommand_violation "$rel_f" "$lineno" "$verb" "$sub" "$trimmed"
        continue
      fi
    fi

    case "$verb" in
      relate|unrelate|link|unlink)
        read -ra resttoks <<< "$rest"
        relation="${resttoks[1]:-}"
        relation="${relation%,}"
        if ! is_placeholder "$relation" && ! is_valid_relation "$relation"; then
          add_relation_violation "$rel_f" "$lineno" "$relation" "$trimmed"
        fi
        ;;
    esac
  done < <(awk 'BEGIN{d=0} /^```/{d=1-d; next} d==1{printf "%d\t%s\n", NR, $0}' "$f")
done <<< "$FILES"

verb_violations_json="[]"
if [[ -n "$VERB_VIOLATIONS" ]]; then
  verb_violations_json="$(printf '%s\n' "$VERB_VIOLATIONS" | jq -s '.')"
fi
relation_violations_json="[]"
if [[ -n "$RELATION_VIOLATIONS" ]]; then
  relation_violations_json="$(printf '%s\n' "$RELATION_VIOLATIONS" | jq -s '.')"
fi
subcommand_violations_json="[]"
if [[ -n "$SUBCOMMAND_VIOLATIONS" ]]; then
  subcommand_violations_json="$(printf '%s\n' "$SUBCOMMAND_VIOLATIONS" | jq -s '.')"
fi

verb_count="$(echo "$verb_violations_json" | jq 'length')"
relation_count="$(echo "$relation_violations_json" | jq 'length')"
subcommand_count="$(echo "$subcommand_violations_json" | jq 'length')"
contract_ok="true"
if [[ "$verb_count" -gt 0 || "$relation_count" -gt 0 || "$subcommand_count" -gt 0 ]]; then
  contract_ok="false"
fi

if [[ "$contract_ok" == "true" ]]; then
  display="[forge] contract check: OK — every documented \`story\` verb and relationship matches the real CLI (source: $STORY_SOURCE)"
else
  display="[forge] contract check: FAILED — ${verb_count} bad verb(s), ${subcommand_count} bad subcommand(s), ${relation_count} bad relationship(s) found (source: $STORY_SOURCE)"
  if [[ "$subcommand_count" -gt 0 ]]; then
    while IFS= read -r s; do
      s_verb="$(echo "$s" | jq -r '.verb')"
      display="$display
  - '$s_verb' has no subcommand '$(echo "$s" | jq -r '.subcommand')' at $(echo "$s" | jq -r '.file'):$(echo "$s" | jq -r '.line'): $(echo "$s" | jq -r '.command')
      (real: $(echo "$REAL_SUBCOMMANDS_JSON" | jq -r --arg v "$s_verb" '.[$v] | join(", ")'))"
    done <<< "$(echo "$subcommand_violations_json" | jq -c '.[]')"
  fi
  if [[ "$verb_count" -gt 0 ]]; then
    while IFS= read -r v; do
      display="$display
  - unknown verb '$(echo "$v" | jq -r '.verb')' at $(echo "$v" | jq -r '.file'):$(echo "$v" | jq -r '.line'): $(echo "$v" | jq -r '.command')"
    done <<< "$(echo "$verb_violations_json" | jq -c '.[]')"
  fi
  if [[ "$relation_count" -gt 0 ]]; then
    while IFS= read -r r; do
      display="$display
  - unsupported relationship '$(echo "$r" | jq -r '.relation')' at $(echo "$r" | jq -r '.file'):$(echo "$r" | jq -r '.line'): $(echo "$r" | jq -r '.command')"
    done <<< "$(echo "$relation_violations_json" | jq -c '.[]')"
  fi
fi

jq -n \
  --argjson contract_ok "$contract_ok" \
  --argjson verb_violations "$verb_violations_json" \
  --argjson relation_violations "$relation_violations_json" \
  --argjson subcommand_violations "$subcommand_violations_json" \
  --argjson real_verbs "$REAL_VERBS_JSON" \
  --argjson real_relations "$REAL_RELATIONS_JSON" \
  --argjson real_subcommands "$REAL_SUBCOMMANDS_JSON" \
  --argjson files_scanned "$SCANNED_FILES_JSON" \
  --arg story_source "$STORY_SOURCE" \
  --arg display "$display" \
  '{ok: true, contract_ok: $contract_ok, verb_violations: $verb_violations,
    relation_violations: $relation_violations,
    subcommand_violations: $subcommand_violations, real_verbs: $real_verbs,
    real_relations: $real_relations, real_subcommands: $real_subcommands,
    files_scanned: $files_scanned,
    story_source: $story_source, display: $display}'
