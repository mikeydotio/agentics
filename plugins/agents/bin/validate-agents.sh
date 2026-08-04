#!/usr/bin/env bash
# validate-agents.sh — Structural validation for shared agent definitions
# Runnable from anywhere: bash plugins/agents/bin/validate-agents.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd)"
ERRORS=0
AGENTS=0

red() { printf '\033[0;31m%s\033[0m\n' "$1"; }
green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }

fail() {
  red "  FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

pass() {
  green "  PASS: $1"
}

# The canonical guardrail bullets live in _guardrails.md and are copied verbatim into every
# agent. Extracting them here rather than hardcoding keeps _guardrails.md the single source of
# truth: editing it without re-syncing the agents fails this suite instead of drifting silently,
# which is what happened for as long as the block was documentation-only.
CANON_FILE="$AGENTS_DIR/_guardrails.md"
if [[ ! -f "$CANON_FILE" ]]; then
  red "FATAL: missing $CANON_FILE"
  exit 1
fi
CANON=$(sed -n '/^```markdown$/,/^```$/p' "$CANON_FILE" | grep '^- \*\*' || true)
CANON_COUNT=$(printf '%s\n' "$CANON" | grep -c '^- \*\*' || true)
if [[ "$CANON_COUNT" -lt 1 ]]; then
  red "FATAL: no canonical guardrail bullets found in $CANON_FILE"
  exit 1
fi

echo "Validating agents in $AGENTS_DIR/"
echo "========================================"

# Collect all agent names for uniqueness check.
# Newline-separated list, not an associative array — macOS ships bash 3.2.
SEEN_NAMES=""

for file in "$AGENTS_DIR"/*.md; do
  name=$(basename "$file" .md)

  # Skip template and guardrails files
  [[ "$name" == _* ]] && continue

  AGENTS=$((AGENTS + 1))
  echo ""
  echo "--- $name ---"

  # 1. Check YAML frontmatter exists (between --- markers)
  if ! head -1 "$file" | grep -q '^---$'; then
    fail "Missing YAML frontmatter opening ---"
    continue
  fi

  # Extract frontmatter (between first and second ---).
  # `sed '$d'` drops the closing marker; `head -n -1` is GNU-only.
  frontmatter=$(sed -n '2,/^---$/p' "$file" | sed '$d')

  # 2. Check required fields
  for field in name description tools color tier read_only tags; do
    if ! echo "$frontmatter" | grep -q "^${field}:"; then
      fail "Missing required field: $field"
    fi
  done

  # 3. Check name matches filename
  yaml_name=$(echo "$frontmatter" | grep '^name:' | sed 's/^name: *//')
  if [[ "$yaml_name" != "$name" ]]; then
    fail "Name mismatch: filename=$name, yaml=$yaml_name"
  else
    pass "Name matches filename"
  fi

  # 4. Check for duplicate names
  if printf '%s' "$SEEN_NAMES" | grep -qx "$yaml_name"; then
    fail "Duplicate name: $yaml_name"
  else
    SEEN_NAMES="${SEEN_NAMES}${yaml_name}
"
  fi

  # 5. Check read_only agents don't have Write/Edit tools
  read_only=$(echo "$frontmatter" | grep '^read_only:' | sed 's/^read_only: *//')
  tools=$(echo "$frontmatter" | grep '^tools:' | sed 's/^tools: *//')

  if [[ "$read_only" == "true" ]]; then
    if echo "$tools" | grep -q 'Write'; then
      fail "Read-only agent has Write tool"
    elif echo "$tools" | grep -q 'Edit'; then
      fail "Read-only agent has Edit tool"
    else
      pass "Read-only constraint consistent with tools"
    fi
  fi

  # 6. Check <role> tag exists
  if grep -q '<role>' "$file"; then
    pass "Has <role> tag"
  else
    fail "Missing <role> tag"
  fi

  # 7. Check closing </role> tag exists
  if grep -q '</role>' "$file"; then
    pass "Has closing </role> tag"
  else
    fail "Missing closing </role> tag"
  fi

  # 8. Check for Guardrails section
  if grep -q '## Guardrails' "$file"; then
    pass "Has Guardrails section"
  else
    fail "Missing ## Guardrails section"
  fi

  # 9. Check for Anti-Patterns section
  if grep -q '## Anti-Patterns' "$file"; then
    pass "Has Anti-Patterns section"
  else
    yellow "  WARN: Missing ## Anti-Patterns section"
  fi

  # 10. Check for Output Format section
  if grep -q '## Output Format' "$file"; then
    pass "Has Output Format section"
  else
    yellow "  WARN: Missing ## Output Format section"
  fi

  # 11. Canonical guardrails present verbatim (drift guard)
  missing_canon=0
  while IFS= read -r bullet; do
    [[ -z "$bullet" ]] && continue
    # -e is required: every bullet starts with "- ", which BSD grep otherwise reads as a flag.
    if ! grep -Fqx -e "$bullet" "$file"; then
      fail "Guardrail bullet drifted from _guardrails.md: ${bullet:0:60}..."
      missing_canon=$((missing_canon + 1))
    fi
  done <<< "$CANON"
  if [[ $missing_canon -eq 0 ]]; then
    pass "Canonical guardrails match _guardrails.md"
  fi

  # 12. Model pin policy: agents may only pin *down* a tier.
  # `opus`/`fable` resolve to the latest of their line, so pinning them is a no-op at best and
  # a downgrade when the session runs something more capable — omit the field to inherit.
  if echo "$frontmatter" | grep -q '^model:'; then
    agent_model=$(echo "$frontmatter" | grep '^model:' | sed 's/^model: *//')
    case "$agent_model" in
      haiku|sonnet) pass "Model pin '$agent_model' is a downward pin" ;;
      *) fail "Model pin '$agent_model' is not allowed — use haiku, sonnet, or omit to inherit" ;;
    esac
  fi

  # 13. Effort is required — the session default would otherwise apply uniformly to agents
  # whose work is anything but uniform.
  if echo "$frontmatter" | grep -q '^effort:'; then
    agent_effort=$(echo "$frontmatter" | grep '^effort:' | sed 's/^effort: *//')
    case "$agent_effort" in
      low|medium|high|xhigh|max) pass "Effort '$agent_effort' is valid" ;;
      *) fail "Invalid effort '$agent_effort' — use low, medium, high, xhigh, or max" ;;
    esac
  else
    fail "Missing required field: effort"
  fi

  # 14. Claude 5 models verify their own work; instructing them to again causes
  # over-verification. Catch the 4.x-era phrasings if they creep back in.
  if grep -qiE 'double.?check|verify your (own )?work|re-?verify before|final verification step' "$file"; then
    fail "Contains a redundant self-verification instruction"
  fi

done

echo ""
echo "========================================"
echo "Agents validated: $AGENTS"
if [[ $ERRORS -eq 0 ]]; then
  green "All checks passed!"
else
  red "Failures: $ERRORS"
  exit 1
fi
