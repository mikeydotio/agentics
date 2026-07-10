#!/usr/bin/env bash
# `view <n>` renders an issue's content (native gh plaintext incl. comments) into
# `display` and emits structured {issue,title,state,url}. Read-only; guards on a
# bad/missing number and a not-found issue.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

# happy path: renders body + metadata
out=$(cd "$repo" && FAKE_GH_VIEW_TITLE="Login race" FAKE_GH_STATE=OPEN \
      FAKE_GH_VIEW_BODY="Users hit a 500 on concurrent login." \
      bash "$SCRIPT" view 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "view ok:true"
assert_eq "$(jqf "$out" .issue)" "42" "view issue number"
assert_eq "$(jqf "$out" .title)" "Login race" "view title"
assert_eq "$(jqf "$out" .state)" "OPEN" "view state"
assert_eq "$(jqf "$out" .url)" "https://github.com/fake/repo/issues/42" "view url"
assert_contains "$(jqf "$out" .display)" "Users hit a 500" "view display carries the body"

# not-found: ok:false + non-zero exit
out=$(cd "$repo" && FAKE_GH_VIEW_FAIL=1 bash "$SCRIPT" view 999 2>&1); rc=$?
assert_eq "$(jqf "$out" .ok)" "false" "view not-found ok:false"
assert_eq "$rc" "1" "view not-found exits 1"
assert_contains "$(jqf "$out" .display)" "not found" "view not-found display"

# bad arg: non-integer number
out=$(cd "$repo" && bash "$SCRIPT" view abc 2>&1); rc=$?
assert_eq "$(jqf "$out" .ok)" "false" "view non-integer ok:false"
assert_eq "$rc" "1" "view non-integer exits 1"

# missing number
out=$(cd "$repo" && bash "$SCRIPT" view 2>&1); rc=$?
assert_eq "$(jqf "$out" .ok)" "false" "view missing-number ok:false"
assert_eq "$rc" "1" "view missing-number exits 1"

finish
