#!/usr/bin/env bash
# Tests for `atlas-cli lock` — mkdir-atomic heartbeat lock.

test_lock_acquire() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" lock acquire --holder alice
    assert_exit_code 0 "$EXIT_CODE" "acquire succeeds" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok" || return 1
    assert_file_exists "$repo/.atlas/lock/lock.json" "lock file written" || return 1

    cleanup_fixture_repo "$repo"
}

test_lock_blocks_second_acquire() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" lock acquire --holder alice
    run_atlas "$repo" lock acquire --holder bob
    assert_exit_code 1 "$EXIT_CODE" "second acquire blocked" || return 1
    assert_json_field "$OUTPUT" '.error' "lock_held" "error code" || return 1
    assert_json_field "$OUTPUT" '.holder' "alice" "reports current holder" || return 1

    cleanup_fixture_repo "$repo"
}

test_lock_takeover_when_stale() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" lock acquire --holder alice
    backdate_lock "$repo" 1200   # heartbeat 20 min ago, ttl is 10 min

    run_atlas "$repo" lock acquire --holder bob
    assert_exit_code 0 "$EXIT_CODE" "stale lock taken over" || return 1
    assert_json_field "$OUTPUT" '.took_over' "true" "takeover flagged" || return 1
    assert_json_field "$OUTPUT" '.holder' "bob" "new holder" || return 1

    cleanup_fixture_repo "$repo"
}

test_lock_heartbeat_advances() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" lock acquire --holder alice
    backdate_lock "$repo" 60
    local before after
    before=$(jq -r '.heartbeat_at' "$repo/.atlas/lock/lock.json")

    run_atlas "$repo" lock heartbeat
    assert_exit_code 0 "$EXIT_CODE" "heartbeat succeeds" || return 1
    after=$(jq -r '.heartbeat_at' "$repo/.atlas/lock/lock.json")
    if ! python3 -c "import sys; sys.exit(0 if float('$after') > float('$before') else 1)"; then
        echo "    FAIL: heartbeat did not advance ($before -> $after)"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_lock_release_idempotent() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    run_atlas "$repo" lock acquire --holder alice
    run_atlas "$repo" lock release
    assert_exit_code 0 "$EXIT_CODE" "release succeeds" || return 1
    run_atlas "$repo" lock release
    assert_exit_code 0 "$EXIT_CODE" "second release is a no-op success" || return 1

    cleanup_fixture_repo "$repo"
}

test_lock_concurrent_single_winner() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "a.txt"
    commit_all "$repo"

    local wins=0 i ec
    local pids=()
    local results
    results=$(mktemp -d "/tmp/atlas-tests-XXXXXX")
    for i in 1 2 3 4; do
        (
            # The harness runs tests with set -e; racers must be allowed to
            # lose (exit 1) without aborting anything.
            set +e
            cd "$repo" && python3 "$CLI" lock acquire --holder "racer$i" \
                > /dev/null 2>&1
            echo $? > "$results/$i"
        ) &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || true; done
    for i in 1 2 3 4; do
        ec=$(cat "$results/$i" 2>/dev/null || echo 99)
        [ "$ec" = "0" ] && wins=$((wins + 1))
    done
    rm -rf "$results"

    assert_eq "1" "$wins" "exactly one concurrent acquire wins" || return 1

    cleanup_fixture_repo "$repo"
}
