#!/usr/bin/env bash
set -euo pipefail

# forge-prechecks.sh — deterministic pre-checks for the forge execute loop
# Runs test suite, linter, stub grep, and scope check. Outputs JSON to stdout.

PROJECT_DIR="."
STORY_ID=""
MAPPING=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)  PROJECT_DIR="$2"; shift 2 ;;
    --story-id)     STORY_ID="$2"; shift 2 ;;
    --mapping)      MAPPING="$2"; shift 2 ;;
    *)              echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

cd "$PROJECT_DIR"

# Accumulate check results as newline-delimited JSON objects
CHECKS=""
add_check() {
  if [[ -n "$CHECKS" ]]; then
    CHECKS="${CHECKS}
$1"
  else
    CHECKS="$1"
  fi
}

# ── Check 1: Test Suite ──

detect_test_cmd() {
  if [[ -f "package.json" ]] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    echo "npm test"
  elif [[ -f "pytest.ini" ]]; then
    echo "pytest"
  elif [[ -f "pyproject.toml" ]] && grep -q '\[tool\.pytest' pyproject.toml 2>/dev/null; then
    echo "pytest"
  elif [[ -f "Cargo.toml" ]]; then
    echo "cargo test"
  elif [[ -f "Makefile" ]] && grep -qE '^test:' Makefile 2>/dev/null; then
    echo "make test"
  elif [[ -f "tests/run-tests.sh" ]]; then
    echo "bash tests/run-tests.sh"
  else
    echo ""
  fi
}

run_test_check() {
  local test_cmd
  test_cmd="$(detect_test_cmd)"

  if [[ -z "$test_cmd" ]]; then
    add_check "$(jq -n \
      --arg check "tests" \
      --arg command "" \
      --arg details "No test tool detected — skip" \
      '{check: $check, passed: true, command: $command, details: $details, flaky_tests: [], skipped: true}')"
    return
  fi

  local test_output
  if test_output="$(eval "$test_cmd" 2>&1)"; then
    add_check "$(jq -n \
      --arg check "tests" \
      --arg command "$test_cmd" \
      '{check: $check, passed: true, command: $command, details: "", flaky_tests: []}')"
    return
  fi

  # First failure — retry once for flaky test handling
  if test_output="$(eval "$test_cmd" 2>&1)"; then
    add_check "$(jq -n \
      --arg check "tests" \
      --arg command "$test_cmd" \
      --arg details "Passed on retry — potentially flaky" \
      '{check: $check, passed: true, command: $command, details: $details, flaky_tests: ["(full suite — rerun passed)"]}')"
    return
  fi

  add_check "$(jq -n \
    --arg check "tests" \
    --arg command "$test_cmd" \
    --arg details "$test_output" \
    '{check: $check, passed: false, command: $command, details: $details, flaky_tests: []}')"
}

# ── Check 2: Linter / Type Checker ──

detect_lint_cmd() {
  local has_eslintrc=false
  for f in .eslintrc .eslintrc.json .eslintrc.js .eslintrc.yml .eslintrc.yaml .eslintrc.cjs; do
    if [[ -f "$f" ]]; then has_eslintrc=true; break; fi
  done
  # Also check eslint.config.* (flat config)
  if ! $has_eslintrc; then
    for f in eslint.config.*; do
      if [[ -f "$f" ]]; then has_eslintrc=true; break; fi
    done
  fi

  if $has_eslintrc; then
    echo "npx eslint --no-warn ."
  elif [[ -f "tsconfig.json" ]]; then
    echo "npx tsc --noEmit"
  elif [[ -f "ruff.toml" ]]; then
    echo "ruff check ."
  elif [[ -f "pyproject.toml" ]] && grep -q '\[tool\.ruff' pyproject.toml 2>/dev/null; then
    echo "ruff check ."
  elif [[ -f "Cargo.toml" ]]; then
    echo "cargo clippy"
  else
    echo ""
  fi
}

run_lint_check() {
  local lint_cmd
  lint_cmd="$(detect_lint_cmd)"

  if [[ -z "$lint_cmd" ]]; then
    add_check "$(jq -n \
      --arg check "linter" \
      --arg command "" \
      --arg details "No linter detected — skip" \
      '{check: $check, passed: true, command: $command, details: $details, skipped: true}')"
    return
  fi

  local lint_output
  if lint_output="$(eval "$lint_cmd" 2>&1)"; then
    add_check "$(jq -n \
      --arg check "linter" \
      --arg command "$lint_cmd" \
      '{check: $check, passed: true, command: $command, details: ""}')"
  else
    add_check "$(jq -n \
      --arg check "linter" \
      --arg command "$lint_cmd" \
      --arg details "$lint_output" \
      '{check: $check, passed: false, command: $command, details: $details}')"
  fi
}

# ── Check 3: Stub Grep ──

run_stub_check() {
  local modified_files
  modified_files="$(git diff --name-only HEAD 2>/dev/null || true)"
  # Also include staged but not yet committed files
  local staged_files
  staged_files="$(git diff --cached --name-only 2>/dev/null || true)"
  # Merge both lists, deduplicate
  local all_files
  all_files="$(printf '%s\n%s' "$modified_files" "$staged_files" | sort -u | grep -v '^$' || true)"

  if [[ -z "$all_files" ]]; then
    add_check "$(jq -n \
      --arg check "stub_grep" \
      '{check: $check, passed: true, details: "", matches: []}')"
    return
  fi

  local matches_raw=""
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    local file_matches
    # F105: word-boundary TODO/FIXME/HACK markers plus a handful of
    # language-specific "this is intentionally unimplemented" idioms —
    # NOT bare 'stub'/'placeholder'/'XXX' substrings. Those false-positived
    # on entirely legitimate code (a form field's `placeholder` text/prop, a
    # function or type legitimately named `*stub*` for a real domain reason,
    # an `XXX` used as a coordinate/template name) and hard-blocked the loop
    # with no way for the generator to "fix" a false positive. Every pattern
    # below is either a whole-word marker (`\bTODO\b` can't match inside
    # "TODOLIST") or a specific, high-signal stub idiom that essentially
    # never appears outside an actual unimplemented code path.
    file_matches="$(grep -nE \
      -e '\bTODO\b' -e '\bFIXME\b' -e '\bHACK\b' \
      -e 'NotImplementedError' \
      -e 'unimplemented!' \
      -e 'throw new Error\([^)]*[Nn]ot [Ii]mplemented' \
      -e 'fatalError\([^)]*[Nn]ot [Ii]mplemented' \
      -e 'preconditionFailure\([^)]*[Nn]ot [Ii]mplemented' \
      "$file" 2>/dev/null || true)"
    if [[ -n "$file_matches" ]]; then
      while IFS= read -r line; do
        matches_raw="${matches_raw}${file}:${line}
"
      done <<< "$file_matches"
    fi
  done <<< "$all_files"

  # Trim trailing newline
  matches_raw="$(echo "$matches_raw" | sed '/^$/d')"

  if [[ -z "$matches_raw" ]]; then
    add_check "$(jq -n \
      --arg check "stub_grep" \
      '{check: $check, passed: true, details: "", matches: []}')"
  else
    local file_count
    file_count="$(echo "$matches_raw" | cut -d: -f1 | sort -u | wc -l | tr -d ' ')"
    local matches_json
    matches_json="$(echo "$matches_raw" | jq -R -s 'split("\n") | map(select(length > 0))')"
    add_check "$(jq -n \
      --arg check "stub_grep" \
      --arg details "Found stubs in ${file_count} file(s)" \
      --argjson matches "$matches_json" \
      '{check: $check, passed: false, details: $details, matches: $matches}')"
  fi
}

# ── Check 4: Scope Check ──

run_scope_check() {
  if [[ -z "$STORY_ID" ]] || [[ -z "$MAPPING" ]]; then
    add_check "$(jq -n \
      --arg check "scope" \
      --arg details "No story-id or mapping — skip" \
      '{check: $check, passed: true, details: $details, expected_modified: [], unexpected_modified: [], skipped: true}')"
    return
  fi

  if [[ ! -f "$MAPPING" ]]; then
    add_check "$(jq -n \
      --arg check "scope" \
      --arg details "Mapping file not found — skip" \
      '{check: $check, passed: true, details: $details, expected_modified: [], unexpected_modified: [], skipped: true}')"
    return
  fi

  local expected_files_json
  expected_files_json="$(jq -r --arg sid "$STORY_ID" '.stories[$sid].files_expected // []' "$MAPPING" 2>/dev/null || echo '[]')"

  local modified_files
  modified_files="$(git diff --name-only HEAD 2>/dev/null || true)"
  local staged_files
  staged_files="$(git diff --cached --name-only 2>/dev/null || true)"
  local all_files
  all_files="$(printf '%s\n%s' "$modified_files" "$staged_files" | sort -u | grep -v '^$' || true)"

  local expected_modified=()
  local unexpected_modified=()

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if echo "$expected_files_json" | jq -e --arg f "$file" 'index($f) != null' >/dev/null 2>&1; then
      expected_modified+=("$file")
    else
      unexpected_modified+=("$file")
    fi
  done <<< "$all_files"

  local expected_json
  expected_json="$(printf '%s\n' "${expected_modified[@]+"${expected_modified[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))')"
  local unexpected_json
  unexpected_json="$(printf '%s\n' "${unexpected_modified[@]+"${unexpected_modified[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))')"

  local details=""
  local unexpected_count
  unexpected_count="$(echo "$unexpected_json" | jq 'length')"
  if [[ "$unexpected_count" -gt 0 ]]; then
    details="$unexpected_count unexpected file(s) modified"
  fi

  # Scope check is warning-only: always passes
  add_check "$(jq -n \
    --arg check "scope" \
    --arg details "$details" \
    --argjson expected "$expected_json" \
    --argjson unexpected "$unexpected_json" \
    '{check: $check, passed: true, details: $details, expected_modified: $expected, unexpected_modified: $unexpected}')"
}

# ── Run all checks ──

run_test_check
run_lint_check
run_stub_check
run_scope_check

# ── Build output ──

checks_json="$(echo "$CHECKS" | jq -s '.')"

# Count passes/fails/skips
total="$(echo "$checks_json" | jq 'length')"
passed_count="$(echo "$checks_json" | jq '[.[] | select(.passed == true and (.skipped // false) == false)] | length')"
skipped_count="$(echo "$checks_json" | jq '[.[] | select(.skipped // false)] | length')"
all_passed="$(echo "$checks_json" | jq '[.[] | select(.passed == false)] | length == 0')"

# Build display string
display="[forge] Pre-checks: $((passed_count + skipped_count))/$total passed"
while IFS= read -r check_json; do
  name="$(echo "$check_json" | jq -r '.check')"
  is_passed="$(echo "$check_json" | jq -r '.passed')"
  is_skipped="$(echo "$check_json" | jq -r '.skipped // false')"
  cmd="$(echo "$check_json" | jq -r '.command // ""')"
  details="$(echo "$check_json" | jq -r '.details // ""')"

  if [[ "$is_skipped" == "true" ]]; then
    status="SKIP"
  elif [[ "$is_passed" == "true" ]]; then
    status="PASS"
  else
    status="FAIL"
  fi

  line="  [$status] $name"
  if [[ -n "$cmd" ]]; then
    line="$line ($cmd)"
  fi
  if [[ "$status" == "FAIL" && -n "$details" ]]; then
    line="$line: $details"
  fi
  display="$display
$line"
done <<< "$(echo "$checks_json" | jq -c '.[]')"

# Remove .skipped from output (internal field)
clean_checks="$(echo "$checks_json" | jq '[.[] | del(.skipped)]')"

jq -n \
  --argjson all_passed "$all_passed" \
  --argjson checks "$clean_checks" \
  --arg display "$display" \
  '{ok: true, all_passed: $all_passed, checks: $checks, display: $display}'
