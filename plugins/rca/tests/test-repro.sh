#!/usr/bin/env bash
# rca-repro.sh run: always-fail (rate 1, deterministic), always-pass (rate 0),
# flaky counter (rate 0.5), cmd_not_found, and timeout. A FAILING test is a
# SUCCESSFUL harness run (ok:true) — only harness errors are ok:false.
source "$(dirname "$0")/lib.sh"

# always-fail x3 → deterministic, rate 1.0, tail captured
out=$(bash "$REPRO" run --cmd 'echo boom >&2; exit 1' --runs 3)
assert_json "$out" '.ok == true' "always-fail is a successful harness run"
assert_json "$out" '.failures == 3 and .runs == 3' "3/3 failures"
assert_json "$out" '.failure_rate == 1' "rate 1.0"
assert_json "$out" '.deterministic == true' "all-fail is deterministic"
assert_json "$out" '.exit_codes == [1,1,1]' "exit codes recorded"
assert_json "$out" '.last_failure_tail | length > 0' "failure tail captured"

# always-pass → rate 0, deterministic, empty tail
out=$(bash "$REPRO" run --cmd 'echo ok; exit 0' --runs 4)
assert_json "$out" '.ok == true and .failures == 0 and .failure_rate == 0' "0/4 failures"
assert_json "$out" '.deterministic == true' "all-pass is deterministic"
assert_json "$out" '.last_failure_tail == ""' "no failure → empty tail"

# flaky counter (fails every 2nd run) → 2/4, rate 0.5, NOT deterministic
FD="$(flaky_cmd_dir)"
out=$(bash "$REPRO" run --cmd 'bash flaky.sh' --runs 4 --dir "$FD")
assert_json "$out" '.ok == true' "flaky harness run ok"
assert_json "$out" '.failures == 2 and .runs == 4' "flaky → 2/4 failures"
assert_json "$out" '.failure_rate == 0.5' "flaky rate 0.5"
assert_json "$out" '.deterministic == false' "flaky is non-deterministic"

# cmd_not_found on the first run → harness error
out=$(bash "$REPRO" run --cmd 'definitely-not-a-real-cmd-xyz' --runs 2 || true)
assert_json "$out" '.ok == false and .error == "cmd_not_found"' "missing cmd → cmd_not_found"

# timeout: a sleeper bounded by --timeout 1 → harness error
out=$(bash "$REPRO" run --cmd 'sleep 5' --runs 1 --timeout 1 || true)
assert_json "$out" '.ok == false and .error == "timeout"' "over-timeout → timeout error"

# missing --cmd → bad_args
out=$(bash "$REPRO" run --runs 2 || true)
assert_json "$out" '.ok == false and .error == "bad_args"' "no --cmd → bad_args"

finish
