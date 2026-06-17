#!/usr/bin/env bash
# Tests for `atlas-cli lint` — mechanical map integrity checks (L1–L11).

# Single fully-valid module fixture: complete skeleton, real symbol, ledger
# finalized, INDEX rebuilt. Lint must come back completely clean.
_lint_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth"
    printf 'class AuthService {\n  func login() {}\n}\n' > "$repo/src/auth/auth.swift"
    write_full_module_doc "$repo" "src-auth" "src/auth" "AuthService" "src/auth/auth.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "map"
    echo "$repo"
}

test_lint_clean_map_passes() {
    local repo
    repo=$(_lint_fixture)

    run_atlas "$repo" lint
    assert_exit_code 0 "$EXIT_CODE" "clean map lints green" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok" || return 1
    assert_json_field "$OUTPUT" '.error_count' "0" "no errors" || return 1
    assert_json_field "$OUTPUT" '.warning_count' "0" "no warnings" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_missing_index_is_error() {
    local repo
    repo=$(_lint_fixture)
    rm "$repo/docs/atlas/INDEX.md"

    run_atlas "$repo" lint
    assert_exit_code 1 "$EXIT_CODE" "missing INDEX fails lint" || return 1
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L9" "L9 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_detects_conflict_markers() {
    local repo
    repo=$(_lint_fixture)
    printf '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n' \
        >> "$repo/docs/atlas/modules/src-auth.md"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L2" "L2 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_detects_missing_source() {
    local repo
    repo=$(_lint_fixture)
    git -C "$repo" rm -q src/auth/auth.swift
    git -C "$repo" commit -q -m "delete source"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L3" "L3 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_warns_on_ledger_drift() {
    local repo
    repo=$(_lint_fixture)
    echo "// changed" >> "$repo/src/auth/auth.swift"

    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '.ok' "true" "drift is a warning, not an error" || return 1
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L4" "L4 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_warns_uncovered_files() {
    local repo
    repo=$(_lint_fixture)
    seed_file "$repo" "src/uncovered.swift"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L5" "L5 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_warns_dead_backtick_path() {
    local repo
    repo=$(_lint_fixture)
    printf '\nSee `src/auth/missing.swift` for details.\n' \
        >> "$repo/docs/atlas/modules/src-auth.md"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L6" "L6 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_l6_skips_non_citation_paths() {
    local repo
    repo=$(_lint_fixture)
    # None of these are repo-root citations: cwd-relative command idiom,
    # parent-relative paths, absolute machine paths, and a line-numberless
    # path whose first segment is not a repo directory (server-side artifact).
    {
        printf '\nRun `./project.yml` or `../scratch/app.yml` by hand.\n'
        printf 'The daemon writes `/var/www/app/index.html` and `index/builds.json`.\n'
    } >> "$repo/docs/atlas/modules/src-auth.md"

    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '[.warnings[] | select(.check == "L6")] | length' "0" \
        "non-citation paths are not L6 findings" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_l6_still_flags_shorthand_citation() {
    local repo
    repo=$(_lint_fixture)
    # A :line suffix claims a repo code location — module-relative shorthand
    # stays flagged even though `hooks/` is not a repo top-level directory.
    printf '\nRegistered in `hooks/on-stop.sh:34`.\n' \
        >> "$repo/docs/atlas/modules/src-auth.md"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L6" \
        "shorthand citation with line number flagged" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_warns_missing_symbol() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth"
    printf 'class AuthService {}\n' > "$repo/src/auth/auth.swift"
    write_full_module_doc "$repo" "src-auth" "src/auth" "GhostType" "src/auth/auth.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L7" \
        "claimed symbol absent from claimed file" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_detects_broken_link() {
    local repo
    repo=$(_lint_fixture)
    printf '\n[details](nonexistent.md)\n' \
        >> "$repo/docs/atlas/modules/src-auth.md"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L8" "L8 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_detects_index_drift() {
    local repo
    repo=$(_lint_fixture)
    echo "manual edit" >> "$repo/docs/atlas/INDEX.md"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L10" "L10 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_detects_index_over_budget() {
    local repo
    repo=$(_lint_fixture)
    python3 -c "print('x' * 8000)" > "$repo/docs/atlas/INDEX.md"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L9" "L9 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_detects_missing_section() {
    local repo
    repo=$(_lint_fixture)
    local doc="$repo/docs/atlas/modules/src-auth.md"
    grep -v '^## Relationships$' "$doc" > "$doc.tmp" && mv "$doc.tmp" "$doc"

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L1" "L1 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_fast_skips_body_checks() {
    local repo
    repo=$(_lint_fixture)
    # L6 condition (slow check) plus L2 condition (fast check)
    printf '\nSee `src/auth/missing.swift` for details.\n' \
        >> "$repo/docs/atlas/modules/src-auth.md"
    printf '<<<<<<< HEAD\nours\n>>>>>>> branch\n' \
        >> "$repo/docs/atlas/modules/src-auth.md"

    run_atlas "$repo" lint --fast
    assert_json_field "$OUTPUT" '.fast' "true" "fast mode" || return 1
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L2" \
        "fast still catches markers" || return 1
    assert_json_field "$OUTPUT" '[.warnings[] | select(.check == "L6")] | length' "0" \
        "fast skips body checks" || return 1

    cleanup_fixture_repo "$repo"
}

# --- L12: references_modules must resolve to real module docs ---

test_lint_l12_flags_dangling_reference() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth"
    printf 'class AuthService {}\n' > "$repo/src/auth/auth.swift"
    write_full_module_doc "$repo" "src-auth" "src/auth" "AuthService" \
        "src/auth/auth.swift" "ghost-module"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint
    assert_exit_code 1 "$EXIT_CODE" "dangling reference fails lint" || return 1
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L12" "L12 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_l12_accepts_valid_reference() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth" "$repo/src/db"
    printf 'class AuthService {}\n' > "$repo/src/auth/auth.swift"
    printf 'class Database {}\n' > "$repo/src/db/db.swift"
    write_full_module_doc "$repo" "src-auth" "src/auth" "AuthService" \
        "src/auth/auth.swift" "src-db"
    write_full_module_doc "$repo" "src-db" "src/db" "Database" \
        "src/db/db.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '[.errors[] | select(.check == "L12")] | length' "0" \
        "valid cross-reference is not an L12 finding" || return 1

    cleanup_fixture_repo "$repo"
}

# --- L13: relationship edge verbs must be in the allowed grammar set ---

test_lint_l13_flags_bad_verb() {
    local repo
    repo=$(_lint_fixture)
    local doc="$repo/docs/atlas/modules/src-auth.md"
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
open(p, "w").write(t.replace("(calls)", "(builds)"))
PY

    run_atlas "$repo" lint
    assert_exit_code 1 "$EXIT_CODE" "out-of-grammar verb fails lint" || return 1
    assert_json_contains "$OUTPUT" '[.errors[].check]' "L13" "L13 fired" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_l13_allows_known_verb_with_trailing_citation() {
    local repo
    repo=$(_lint_fixture)
    local doc="$repo/docs/atlas/modules/src-auth.md"
    # Valid verb, then a `path:line` citation after the closing backtick: the
    # verb is captured inside the backtick span, so the citation is ignored.
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace(
    "-> external.none (calls)`",
    "-> external.none (reads)` — `src/auth/auth.swift:1`")
open(p, "w").write(t)
PY

    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '[.errors[] | select(.check == "L13")] | length' "0" \
        "known verb with trailing citation is not an L13 finding" || return 1

    cleanup_fixture_repo "$repo"
}

# --- L7: qualified Type.member / arg-labelled symbols ---

test_lint_l7_accepts_qualified_symbol() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/log"
    printf 'class RollingLog {\n  func stream() {}\n}\n' > "$repo/src/log/log.swift"
    write_full_module_doc "$repo" "src-log" "src/log" "RollingLog.stream" \
        "src/log/log.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '[.warnings[] | select(.check == "L7")] | length' "0" \
        "qualified Type.member resolves via the bare identifier" || return 1

    cleanup_fixture_repo "$repo"
}

test_lint_l7_still_flags_truly_missing_symbol() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/log"
    printf 'class Real {}\n' > "$repo/src/log/log.swift"
    write_full_module_doc "$repo" "src-log" "src/log" "Ghost.missing" \
        "src/log/log.swift"
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L7" \
        "genuinely missing qualified symbol still flagged" || return 1

    cleanup_fixture_repo "$repo"
}

# --- L14: over-length read_when / summary (WARN, never gates) ---

test_lint_l14_warns_overlong_read_when() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth"
    printf 'class AuthService {}\n' > "$repo/src/auth/auth.swift"
    write_full_module_doc "$repo" "src-auth" "src/auth" "AuthService" \
        "src/auth/auth.swift"
    local doc="$repo/docs/atlas/modules/src-auth.md"
    # Force read_when over 90 chars BEFORE finalize/rebuild so the INDEX is
    # built from the long line (keeps L10 reconciliation clean).
    python3 - "$doc" <<'PY'
import re, sys
p = sys.argv[1]
long_rw = "Touching " + "x" * 100
t = re.sub(r'^read_when:.*$', 'read_when: "%s"' % long_rw,
           open(p).read(), count=1, flags=re.M)
open(p, "w").write(t)
PY
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '.ok' "true" "over-length read_when is a warning" || return 1
    assert_json_contains "$OUTPUT" '[.warnings[].check]' "L14" "L14 fired" || return 1

    cleanup_fixture_repo "$repo"
}

# --- fast mode excludes the new body/frontmatter checks ---

test_lint_fast_skips_new_checks() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth"
    printf 'class AuthService {}\n' > "$repo/src/auth/auth.swift"
    write_full_module_doc "$repo" "src-auth" "src/auth" "AuthService" \
        "src/auth/auth.swift" "ghost-module"
    local doc="$repo/docs/atlas/modules/src-auth.md"
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
open(p, "w").write(t.replace("(calls)", "(builds)"))
PY
    commit_all "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes
    run_atlas "$repo" index rebuild

    run_atlas "$repo" lint --fast
    assert_json_field "$OUTPUT" '.fast' "true" "fast mode" || return 1
    assert_json_field "$OUTPUT" '[.errors[] | select(.check == "L12")] | length' "0" \
        "fast skips L12" || return 1
    assert_json_field "$OUTPUT" '[.errors[] | select(.check == "L13")] | length' "0" \
        "fast skips L13" || return 1

    cleanup_fixture_repo "$repo"
}
