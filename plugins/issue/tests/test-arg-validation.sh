#!/usr/bin/env bash
# Argument validation: bad subcommand and non-integer/missing dispatch args all
# fail fast with ok:false + exit 1, before any tmux/gh side effect.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

out=$(cd "$repo" && bash "$SCRIPT" bogus 2>&1); rc=$?
assert_eq "$rc" "1" "bad subcommand exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "bad subcommand ok:false"

out=$(cd "$repo" && bash "$SCRIPT" dispatch abc 2>&1); rc=$?
assert_eq "$rc" "1" "non-integer exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "non-integer ok:false"
assert_contains "$(jqf "$out" .display)" "positive integer" "non-integer display"

out=$(cd "$repo" && bash "$SCRIPT" dispatch 2>&1); rc=$?
assert_eq "$rc" "1" "missing number exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "missing number ok:false"

# the bogus-verb usage lists the full verb grammar
out=$(cd "$repo" && bash "$SCRIPT" bogus 2>&1)
assert_contains "$(jqf "$out" .display)" "view" "usage lists view"
assert_contains "$(jqf "$out" .display)" "complete" "usage lists complete"

# view/complete validate the issue number like dispatch does
out=$(cd "$repo" && bash "$SCRIPT" view abc 2>&1); rc=$?
assert_eq "$rc" "1" "view non-integer exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "view non-integer ok:false"

out=$(cd "$repo" && bash "$SCRIPT" complete plan abc 2>&1); rc=$?
assert_eq "$rc" "1" "complete plan non-integer exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "complete plan non-integer ok:false"

# complete requires a valid sub-verb (plan|execute)
out=$(cd "$repo" && bash "$SCRIPT" complete bogus 77 2>&1); rc=$?
assert_eq "$rc" "1" "complete bad-subverb exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "complete bad-subverb ok:false"
assert_contains "$(jqf "$out" .display)" "plan|execute" "complete usage lists sub-verbs"

finish
