#!/usr/bin/env bash
# Tests for the restricted-YAML config parser (docs/atlas/config.yaml),
# focused on inline-comment handling. Only whole-line `#` comments were
# stripped before; a trailing `# …` after a list item used to become part of
# the value and silently break excludes.

# An exclude glob carrying a trailing inline comment must still apply.
test_config_inline_comment_on_list_applies_exclude() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "vendor/lib.txt"
    seed_file "$repo" "src/keep.txt"
    write_config "$repo" <<'YAML'
exclude:
  - "vendor/**"   # third-party, not mapped
YAML
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_field "$OUTPUT" \
        '[.files[].path | select(. == "vendor/lib.txt")] | length' "0" \
        "vendor file excluded despite trailing comment" || return 1
    assert_json_contains "$OUTPUT" '[.files[].path]' "src/keep.txt" \
        "non-excluded file still scanned" || return 1

    cleanup_fixture_repo "$repo"
}

# A whole-line comment is still skipped (regression guard on prior behavior).
test_config_comment_only_line_skipped() {
    local repo
    repo=$(create_fixture_repo)
    seed_file "$repo" "vendor/lib.txt"
    seed_file "$repo" "src/keep.txt"
    write_config "$repo" <<'YAML'
# this whole line is a comment
exclude:
  - "vendor/**"
YAML
    commit_all "$repo"

    run_atlas "$repo" scan
    assert_json_field "$OUTPUT" \
        '[.files[].path | select(. == "vendor/lib.txt")] | length' "0" \
        "comment-only line ignored; exclude still applies" || return 1

    cleanup_fixture_repo "$repo"
}

# A quoted value that legitimately contains ` # ` must survive byte-for-byte:
# the inline-comment strip must be quote-aware. Exercised at the parser level.
test_config_quoted_hash_preserved() {
    local result
    result=$(python3 - "$CLI" <<'PY'
import sys
ns = {"__name__": "atlas_cli_under_test"}
exec(open(sys.argv[1]).read(), ns)
cfg = ns["parse_yaml_subset"]('include:\n  - "src/a # b/**"\n')
print(cfg["include"][0])
PY
)
    assert_eq "src/a # b/**" "$result" "quoted ' # ' preserved verbatim" || return 1
}

# A bracketed inline list with a trailing comment parses as a real list.
test_config_inline_comment_on_bracket_list() {
    local result
    result=$(python3 - "$CLI" <<'PY'
import sys
ns = {"__name__": "atlas_cli_under_test"}
exec(open(sys.argv[1]).read(), ns)
cfg = ns["parse_yaml_subset"]('references_modules: [src-api, src-models] # ripple\n')
v = cfg["references_modules"]
print("%s|%s" % (type(v).__name__, len(v) if isinstance(v, list) else v))
PY
)
    assert_eq "list|2" "$result" "bracket list parses despite trailing comment" || return 1
}
