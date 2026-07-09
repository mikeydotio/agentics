#!/usr/bin/env bash
# `create --title <t> [--body-file <p>|--body <t>] [--label <csv>]` files a new
# issue via gh and recovers the assigned number from the printed URL. Guards on a
# missing title / missing body-file / gh failure; ISSUE_DRY_RUN previews only.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

# requires --title
out=$(cd "$repo" && bash "$SCRIPT" create 2>&1); rc=$?
assert_eq "$(jqf "$out" .ok)" "false" "create no-title ok:false"
assert_eq "$rc" "1" "create no-title exits 1"
assert_contains "$(jqf "$out" .display)" "--title is required" "create no-title message"

# happy path: parses number from the default URL (.../issues/123)
out=$(cd "$repo" && bash "$SCRIPT" create --title "Add dark mode" 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "create ok:true"
assert_eq "$(jqf "$out" .number)" "123" "create parsed number"
assert_eq "$(jqf "$out" .url)" "https://github.com/fake/repo/issues/123" "create url"
assert_contains "$(jqf "$out" .display)" "#123" "create display has number"
assert_contains "$(jqf "$out" .display)" "Add dark mode" "create display has title"

# custom URL → number recovered from its trailing segment
out=$(cd "$repo" && FAKE_GH_CREATE_URL="https://github.com/fake/repo/issues/456" \
      bash "$SCRIPT" create --title "X" 2>&1)
assert_eq "$(jqf "$out" .number)" "456" "create custom-url number"

# body-file: passes --body-file to gh (asserted via the gh log)
log=$(mktemp /tmp/issue-create-log.XXXXXX)
bf=$(mktemp /tmp/issue-body.XXXXXX); printf '## Details\nmulti\nline\n' > "$bf"
out=$(cd "$repo" && FAKE_GH_LOG="$log" bash "$SCRIPT" create --title "Y" --body-file "$bf" 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "create body-file ok:true"
assert_contains "$(cat "$log")" "issue create" "gh issue create was invoked"
assert_contains "$(cat "$log")" "--body-file" "gh got --body-file"
rm -f "$log" "$bf"

# missing body-file → ok:false
out=$(cd "$repo" && bash "$SCRIPT" create --title "Z" --body-file /nonexistent/body.md 2>&1); rc=$?
assert_eq "$(jqf "$out" .ok)" "false" "create missing-body-file ok:false"
assert_eq "$rc" "1" "create missing-body-file exits 1"

# gh failure → ok:false
out=$(cd "$repo" && FAKE_GH_CREATE_FAIL=1 bash "$SCRIPT" create --title "W" 2>&1); rc=$?
assert_eq "$(jqf "$out" .ok)" "false" "create gh-fail ok:false"
assert_eq "$rc" "1" "create gh-fail exits 1"

# dry-run: previews the command, files nothing
log=$(mktemp /tmp/issue-create-log.XXXXXX)
out=$(cd "$repo" && ISSUE_DRY_RUN=1 FAKE_GH_LOG="$log" bash "$SCRIPT" create --title "Dry" 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "create dry-run ok:true"
assert_eq "$(jqf "$out" .dry_run)" "true" "create dry-run flag"
assert_contains "$(jqf "$out" .command)" "gh issue create" "create dry-run command"
assert_not_contains "$(cat "$log")" "issue create" "create dry-run filed nothing"
rm -f "$log"

finish
