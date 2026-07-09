#!/usr/bin/env bash
# Precondition failures emit a single {ok:false, display} object (never crash):
# gh missing, gh unauthenticated, not a git repo, no origin remote.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

# gh binary not found
out=$(cd "$repo" && ISSUE_GH_BIN=/nonexistent/gh bash "$SCRIPT" list 2>&1); rc=$?
assert_eq "$rc" "1" "missing gh exits 1"
assert_eq "$(jqf "$out" .ok)" "false" "missing gh ok:false"
assert_contains "$(jqf "$out" .display)" "gh CLI not found" "missing gh display"

# gh unauthenticated
out=$(cd "$repo" && FAKE_GH_AUTH_FAIL=1 bash "$SCRIPT" list 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "unauth ok:false"
assert_contains "$(jqf "$out" .display)" "not authenticated" "unauth display"

# not a git repo
nongit=$(mktemp -d /tmp/issue-nongit.XXXXXX)
out=$(cd "$nongit" && bash "$SCRIPT" list 2>&1)
rm -rf "$nongit"
assert_eq "$(jqf "$out" .ok)" "false" "non-git ok:false"
assert_contains "$(jqf "$out" .display)" "git repository" "non-git display"

# git repo but no origin remote
noorigin=$(mk_repo "-")
out=$(cd "$noorigin" && bash "$SCRIPT" list 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "no-origin ok:false"
assert_contains "$(jqf "$out" .display)" "origin" "no-origin display"

finish
