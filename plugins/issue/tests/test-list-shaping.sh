#!/usr/bin/env bash
# `list` shapes gh's --json output into issues[] with pre-built AskUserQuestion
# {label,description} options, and reports count + a display. Zero-issue case too.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

issues='[{"number":42,"title":"Login race","url":"u1"},{"number":7,"title":"Flaky test","url":"u2"}]'
out=$(cd "$repo" && FAKE_GH_ISSUES_JSON="$issues" bash "$SCRIPT" list 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "list ok:true"
assert_eq "$(jqf "$out" .count)" "2" "list count 2"
assert_eq "$(jqf "$out" .repo)" "fake/repo" "list repo"
assert_eq "$(jqf "$out" '.issues[0].option.label')" "#42" "issue0 label"
assert_eq "$(jqf "$out" '.issues[0].option.description')" "Login race" "issue0 description"
assert_eq "$(jqf "$out" '.issues[1].option.label')" "#7" "issue1 label"

# zero open issues
out=$(cd "$repo" && bash "$SCRIPT" list 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "empty ok:true"
assert_eq "$(jqf "$out" .count)" "0" "empty count 0"
assert_eq "$(jqf "$out" '.issues | length')" "0" "empty issues array"
assert_contains "$(jqf "$out" .display)" "No open issues" "empty display"

finish
