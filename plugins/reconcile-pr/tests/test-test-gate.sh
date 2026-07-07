#!/usr/bin/env bash
# The test gate on push: untested → refuse; failing → refuse; passing (matching
# HEAD) → allow; no_test_command → warn-but-allow; ALLOW_UNTESTED overrides.
# All via SKIP_PUSH so nothing hits the network.
source "$(dirname "$0")/lib.sh"
PR=7
CO="$(reconcile_fixture clean)"
rp "$CO" start "$PR" >/dev/null

# (a) No test run recorded → refuse "untested".
out=$(cd "$CO" && RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "no test → ok:false"
assert_eq "$(jqf "$out" '.reason')" "untested" "no test → reason untested"

# (b) ALLOW_UNTESTED overrides the untested refusal.
out=$(cd "$CO" && RECONCILE_PR_ALLOW_UNTESTED=1 RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "no test + override → ok:true"

# (c) Failing suite → refuse "tests_failing".
out=$(cd "$CO" && RECONCILE_PR_TEST_CMD=false bash "$SCRIPT" test "$PR")
assert_eq "$(jqf "$out" '.status')" "fail" "TEST_CMD=false → fail"
out=$(cd "$CO" && RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "failing tests → ok:false"
assert_eq "$(jqf "$out" '.reason')" "tests_failing" "failing tests → reason tests_failing"

# (d) Passing suite matching HEAD → allow, no warning.
out=$(cd "$CO" && RECONCILE_PR_TEST_CMD=true bash "$SCRIPT" test "$PR")
assert_eq "$(jqf "$out" '.status')" "pass" "TEST_CMD=true → pass"
out=$(cd "$CO" && RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "passing tests → ok:true"
assert_eq "$(jqf "$out" '.warning')" "null" "passing tests → no warning"

# (e) No test command detected → warn-but-allow (the user's chosen policy).
out=$(rp "$CO" test "$PR")
assert_eq "$(jqf "$out" '.status')" "no_test_command" "no runner → no_test_command"
out=$(cd "$CO" && RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "no_test_command → ok:true (allowed)"
assert_contains "$(jqf "$out" '.warning')" "no test command" "no_test_command → warns"

finish
