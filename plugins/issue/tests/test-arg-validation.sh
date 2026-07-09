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

finish
