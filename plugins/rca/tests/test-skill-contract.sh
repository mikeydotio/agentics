#!/usr/bin/env bash
# test-skill-contract.sh — docs↔CLI contract guard (F103-style). For every
# `rca-<name>.sh` invocation in plugins/rca/skills/**/SKILL.md and
# plugins/rca/references/*.md, assert:
#   1. bin/rca-<name>.sh exists.
#   2. every --flag used on that command appears in the script's usage block
#      (the leading `#` comment) — unless the script documents a generic `--<…>`
#      flag (rca-scaffold's `set` accepts arbitrary `--<key>` keys).
# Passes trivially when the skills/references dirs do not yet exist.
source "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"
REFS_DIR="$PLUGIN_ROOT/references"

# Gather doc files (skills SKILL.md + reference markdown). None → trivial pass.
docs=()
if [ -d "$SKILLS_DIR" ]; then
  while IFS= read -r -d '' f; do docs+=("$f"); done \
    < <(find "$SKILLS_DIR" -name 'SKILL.md' -print0 2>/dev/null)
fi
if [ -d "$REFS_DIR" ]; then
  while IFS= read -r -d '' f; do docs+=("$f"); done \
    < <(find "$REFS_DIR" -name '*.md' -print0 2>/dev/null)
fi
if [ "${#docs[@]}" -eq 0 ]; then
  echo "PASS (no skills/references docs yet)"; exit 0
fi

# usage_flags <script> — the set of --flags named in the leading comment block.
usage_flags() {
  awk 'NR==1 && /^#!/ {next} /^#/ {print; next} {exit}' "$1" \
    | grep -oE '\-\-[a-z][a-z0-9-]*' | sort -u
}
# usage_is_generic <script> — true if the usage documents a generic `--<…>` flag.
usage_is_generic() {
  awk 'NR==1 && /^#!/ {next} /^#/ {print; next} {exit}' "$1" | grep -q -- '--<'
}

checked=0
for doc in "${docs[@]}"; do
  # Join backslash-continued lines into one logical line each.
  logical=$(awk '
    { line = $0 }
    sub(/\\[[:space:]]*$/, "", line) { buf = buf line " "; next }
    { print buf line; buf = "" }
    END { if (buf != "") print buf }
  ' "$doc")

  while IFS= read -r lline; do
    case "$lline" in *rca-*.sh*) : ;; *) continue ;; esac
    # Walk tokens; a token naming rca-<name>.sh sets the "current script".
    cur_script=""
    cur_name=""
    for tok in $lline; do
      case "$tok" in
        *rca-[a-z]*.sh*)
          name=$(printf '%s' "$tok" | grep -oE 'rca-[a-z]+\.sh' | head -1)
          [ -n "$name" ] || continue
          cur_name="$name"
          cur_script="$BIN/$name"
          if [ ! -f "$cur_script" ]; then
            fail_test "$(basename "$doc"): references $name but $cur_script does not exist"
            cur_script=""
          fi
          ;;
        --*)
          [ -n "$cur_script" ] || continue
          flag=$(printf '%s' "$tok" | grep -oE '^\-\-[a-z][a-z0-9-]*' | head -1)
          [ -n "$flag" ] || continue
          checked=$((checked + 1))
          if usage_is_generic "$cur_script"; then
            continue
          fi
          if ! usage_flags "$cur_script" | grep -qxF -- "$flag"; then
            fail_test "$(basename "$doc"): $cur_name uses $flag, absent from its usage block"
          fi
          ;;
      esac
    done
  done <<< "$logical"
done

# Sanity: we actually inspected some flags (guards against a silently broken scan).
[ "$checked" -ge 1 ] || fail_test "skill-contract scan checked 0 flags — the scanner may be broken"

finish
