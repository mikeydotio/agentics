#!/usr/bin/env bash
# Argument validation: bad subcommand / missing PR / non-integer PR → ok:false,
# before any repo or gh work.
source "$(dirname "$0")/lib.sh"

# No subcommand → router usage.
out=$(bash "$SCRIPT" 2>/dev/null)
assert_eq "$(jqf "$out" '.ok')" "false" "no subcommand → ok:false"
assert_contains "$(jqf "$out" '.display')" "usage:" "no subcommand → usage"

# Unknown subcommand.
out=$(bash "$SCRIPT" frobnicate 2>/dev/null)
assert_eq "$(jqf "$out" '.ok')" "false" "unknown subcommand → ok:false"

# Missing PR number.
out=$(bash "$SCRIPT" start 2>/dev/null)
assert_eq "$(jqf "$out" '.ok')" "false" "start (no pr) → ok:false"
assert_contains "$(jqf "$out" '.display')" "usage:" "start (no pr) → usage"

# Non-integer PR — validated before need_repo/require_gh, so cwd doesn't matter.
for sub in preflight start status continue test push abort cleanup; do
  out=$(bash "$SCRIPT" "$sub" not-a-number 2>/dev/null)
  assert_eq "$(jqf "$out" '.ok')" "false" "$sub non-integer → ok:false"
  assert_contains "$(jqf "$out" '.display')" "positive integer" "$sub non-integer → integer msg"
done

# Negative / zero-ish rejected by the ^[0-9]+$ regex.
out=$(bash "$SCRIPT" preflight -5 2>/dev/null)
assert_eq "$(jqf "$out" '.ok')" "false" "negative pr → ok:false"

finish
