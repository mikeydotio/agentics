#!/usr/bin/env bash
# Edge-case sweep (plan §Phase 7): degenerate repos, corrupted maps, hostile
# config. Each test pins the behavior an orchestrator depends on — clean JSON
# refusals and sane zero-cases, never tracebacks. Angles already pinned
# elsewhere (empty-repo scan/partition, single-binary sniff, non-git scan,
# over-budget refusal code) are not repeated here.

# ── Empty repo (git init, zero commits) ─────────────────────────────────────

test_empty_repo_status_and_diff_are_sane() {
    local repo
    repo=$(create_fixture_repo)

    run_atlas "$repo" status
    assert_exit_code 0 "$EXIT_CODE" "status works with no commits" || return 1
    assert_json_field "$OUTPUT" '.mapped' "false" "unmapped" || return 1
    assert_json_field "$OUTPUT" '.tier' "0" "tier 0 — hook stays silent" || return 1

    run_atlas "$repo" ledger diff
    assert_exit_code 0 "$EXIT_CODE" "ledger diff works with no commits" || return 1
    assert_json_field "$OUTPUT" '.summary.total_docs' "0" "no docs" || return 1

    cleanup_fixture_repo "$repo"
}

# ── Zero mappable files (commits exist, config excludes everything) ─────────

test_zero_mappable_files() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/real.txt"
    write_config "$repo" <<'EOF'
exclude:
  - "**"
EOF
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_exit_code 0 "$EXIT_CODE" "scan exits 0" || return 1
    assert_json_field "$OUTPUT" '.total_files' "0" "nothing mappable" || return 1

    run_atlas "$repo" partition
    assert_exit_code 0 "$EXIT_CODE" "partition exits 0" || return 1
    assert_json_field "$OUTPUT" '.module_count' "0" "no modules" || return 1

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.mapped' "false" "still unmapped, no crash" || return 1

    cleanup_fixture_repo "$repo"
}

# ── Single-file repo: smallest possible map, end to end ─────────────────────

test_single_file_repo_full_map_flow() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    printf 'class OnlyOne {}\n' > "$repo/src/only.swift"
    commit_all "$repo"

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "1" "one module" || return 1
    assert_json_contains "$OUTPUT" '.modules[0].paths' "src/only.swift" \
        "the file landed in it" || return 1
    local mod_id
    mod_id=$(echo "$OUTPUT" | jq -r '.modules[0].id')

    run_atlas "$repo" ground "$mod_id"
    assert_exit_code 0 "$EXIT_CODE" "ground works on a one-file module" || return 1
    assert_json_contains "$OUTPUT" '[.symbols[].name]' "OnlyOne" \
        "symbol candidate found" || return 1

    write_full_module_doc "$repo" "$mod_id" "src" "OnlyOne" "src/only.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    assert_exit_code 0 "$EXIT_CODE" "finalize ok" || return 1
    run_atlas "$repo" index rebuild
    assert_exit_code 0 "$EXIT_CODE" "index ok" || return 1

    run_atlas "$repo" lint
    assert_exit_code 0 "$EXIT_CODE" "smallest possible map lints green" || return 1
    assert_json_field "$OUTPUT" '.error_count' "0" "no errors" || return 1

    cleanup_fixture_repo "$repo"
}

# ── Binary-heavy repo: sniff excludes them all, scan survives ───────────────

test_binary_heavy_repo() {
    local repo i
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/code.txt"
    seed_file "$repo" "src/more.txt"
    mkdir -p "$repo/assets"
    for i in $(seq 1 12); do
        printf 'BIN\0DATA%s\0\0' "$i" > "$repo/assets/blob$i.dat"
    done
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_exit_code 0 "$EXIT_CODE" "scan exits 0" || return 1
    assert_json_field "$OUTPUT" '.total_files' "2" \
        "only the text files are mappable" || return 1
    assert_json_not_contains "$OUTPUT" '[.files[].path]' "assets/blob1.dat" \
        "binaries excluded" || return 1

    cleanup_fixture_repo "$repo"
}

# ── Hand-corrupted docs/atlas: lint ERROR, tier 3, diff refusal ─────────────

_corrupted_map_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    printf 'class OnlyOne {}\n' > "$repo/src/only.swift"
    write_full_module_doc "$repo" "src" "src" "OnlyOne" "src/only.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    # Hand-corruption: the closing frontmatter fence vanishes (botched edit).
    python3 - "$repo/docs/atlas/modules/src.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
open(path, "w").write(text.replace("---\n\n# Module", "\n# Module", 1))
PY
    echo "$repo"
}

test_corrupted_doc_fails_lint_and_suppresses_trust() {
    local repo
    repo=$(_corrupted_map_fixture)

    run_atlas "$repo" lint
    assert_exit_code 1 "$EXIT_CODE" "corrupted map fails lint" || return 1
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L1" "L1 fired" || return 1

    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "3" "tier 3" || return 1
    assert_json_field "$OUTPUT" '.message | contains("Disregard the imported INDEX")' \
        "true" "trust suppression message" || return 1

    run_atlas "$repo" ledger diff
    assert_exit_code 1 "$EXIT_CODE" "diff refuses corrupted docs" || return 1
    assert_json_field "$OUTPUT" '.error' "invalid_frontmatter" "error code" || return 1
    assert_json_field "$OUTPUT" '.docs | has("modules/src.md")' "true" \
        "names the corrupted doc" || return 1

    cleanup_fixture_repo "$repo"
}

# ── Impossible globs ────────────────────────────────────────────────────────

test_impossible_globs_scan_and_partition() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "src/real.txt"
    write_config "$repo" <<'EOF'
include:
  - "no-such-dir/**"
EOF
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_exit_code 0 "$EXIT_CODE" "scan exits 0" || return 1
    assert_json_field "$OUTPUT" '.total_files' "0" "no matches, no crash" || return 1

    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.module_count' "0" "no modules, no crash" || return 1

    cleanup_fixture_repo "$repo"
}

test_glob_typo_cannot_orphan_a_mapped_repo() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    printf 'class OnlyOne {}\n' > "$repo/src/only.swift"
    write_full_module_doc "$repo" "src" "src" "OnlyOne" "src/only.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    # A config edit that excludes every mapped source...
    write_config "$repo" <<'EOF'
include:
  - "no-such-dir/**"
EOF

    run_atlas "$repo" ledger diff
    assert_exit_code 0 "$EXIT_CODE" "diff exits 0" || return 1
    # ...must NOT orphan the docs: orphaning keys on deleted sources, not on
    # config reach. A typo can shrink scan coverage but never mass-delete a map.
    assert_json_field "$OUTPUT" '.orphaned_docs | length' "0" \
        "no docs orphaned by config reach" || return 1
    assert_json_field "$OUTPUT" '.summary.affected_docs' "0" \
        "map untouched by glob typo" || return 1

    cleanup_fixture_repo "$repo"
}

# ── INDEX budget overflow: refusal carries actionable guidance ──────────────

test_index_over_budget_message_has_guidance() {
    local repo i
    repo=$(create_fixture_repo)
    local long_read_when
    long_read_when=$(python3 -c "print('Touching anything that resembles this very long area. ' * 8)")
    for i in $(seq -w 1 25); do
        seed_file "$repo" "src/m$i/f.txt"
        ATLAS_TEST_READ_WHEN="$long_read_when" \
            write_module_doc "$repo" "src-m$i" "src/m$i" "" "src/m$i/f.txt"
    done
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes

    run_atlas "$repo" index rebuild
    assert_exit_code 1 "$EXIT_CODE" "over-budget rebuild refused" || return 1
    assert_json_field "$OUTPUT" '.message | contains("Trim")' "true" \
        "refusal tells the user what to trim" || return 1

    cleanup_fixture_repo "$repo"
}

# ── Non-git refusal: every subcommand, same JSON contract ───────────────────

test_nongit_refusal_everywhere() {
    local dir
    dir=$(mktemp -d /tmp/atlas-tests-nongit-XXXXXX)
    local -a cmds=(
        "status" "lint" "partition" "ground mod" "ledger diff"
        "ledger finalize" "index rebuild" "commit --message m"
        "doc remove x" "diffpack x" "lock acquire --holder t"
    )
    local cmd
    for cmd in "${cmds[@]}"; do
        # shellcheck disable=SC2086 — word-splitting is the point
        run_atlas "$dir" $cmd
        assert_exit_code 1 "$EXIT_CODE" "non-git: '$cmd' exits 1" || return 1
        assert_json_field "$OUTPUT" '.error' "not_a_git_repo" \
            "non-git: '$cmd' refuses with the JSON contract" || return 1
    done

    cleanup_fixture_repo "$dir"
}
