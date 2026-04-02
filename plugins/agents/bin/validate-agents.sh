#!/usr/bin/env bash
# validate-agents.sh — Structural validation for shared agent definitions
# Run from repo root: bash plugins/agents/bin/validate-agents.sh

set -euo pipefail

AGENTS_DIR="plugins/agents/agents"
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

echo "Validating agents in $AGENTS_DIR/"
echo "========================================"

# Collect all agent names for uniqueness check
declare -A SEEN_NAMES

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

  # Extract frontmatter (between first and second ---)
  frontmatter=$(sed -n '2,/^---$/p' "$file" | head -n -1)

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
  if [[ -n "${SEEN_NAMES[$yaml_name]+x}" ]]; then
    fail "Duplicate name: $yaml_name (also in ${SEEN_NAMES[$yaml_name]})"
  else
    SEEN_NAMES[$yaml_name]="$file"
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

  # 11. Check for Mandatory Initial Read protocol
  if grep -q 'Mandatory Initial Read' "$file"; then
    pass "Has Mandatory Initial Read protocol"
  else
    fail "Missing Mandatory Initial Read protocol"
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
