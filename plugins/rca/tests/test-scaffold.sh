#!/usr/bin/env bash
# rca-scaffold.sh: init (dirs, meta, gitignore idempotency, collision), set
# (round-trip incl. dotted key), slug (deterministic + edge cases).
source "$(dirname "$0")/lib.sh"

REPO="$(make_fixture_repo)"
cd "$REPO"

# ---- init: creates dirs + meta.json with the documented shape ----------------
out=$(bash "$SCAFFOLD" init flaky-login --description "login flakes" \
        --issue-provider gh --issue-ref 42 --tier full)
assert_json "$out" '.ok == true' "init ok"
assert_json "$out" '.gitignore_updated == true' "init created gitignore entries"
[ -d .rca/flaky-login/repro ]      || fail_test "init did not create repro/"
[ -d .rca/flaky-login/forensics ]  || fail_test "init did not create forensics/"
[ -d .rca/flaky-login/experiments ]|| fail_test "init did not create experiments/"
meta=$(cat .rca/flaky-login/meta.json)
assert_eq "$(jqf "$meta" '.slug')" "flaky-login" "meta.slug"
assert_eq "$(jqf "$meta" '.tier')" "" "meta.tier starts empty"
assert_eq "$(jqf "$meta" '.tier_directive')" "full" "meta.tier_directive from --tier"
assert_eq "$(jqf "$meta" '.issue.provider')" "gh" "meta.issue.provider"
assert_eq "$(jqf "$meta" '.issue.ref')" "42" "meta.issue.ref"
assert_eq "$(jqf "$meta" '.stack')" "null" "meta.stack null"
assert_json "$meta" '.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "meta.created_at ISO8601"

# ---- init: second (different) slug does NOT duplicate gitignore lines --------
out2=$(bash "$SCAFFOLD" init other-bug --description "d")
assert_json "$out2" '.ok == true' "second init ok"
assert_json "$out2" '.gitignore_updated == false' "second init leaves gitignore alone"
assert_eq "$(grep -cxF '.rca/' .gitignore)" "1" "exactly one .rca/ line after two inits"
assert_eq "$(grep -cxF '.claude/worktrees/' .gitignore)" "1" "exactly one .claude/worktrees/ line"

# ---- init: missing .gitignore is created -------------------------------------
REPO2="$(make_fixture_repo)"; ( cd "$REPO2" && rm -f .gitignore )
out=$(cd "$REPO2" && bash "$SCAFFOLD" init x --description d)
assert_json "$out" '.gitignore_updated == true' "creates missing .gitignore"
[ -f "$REPO2/.gitignore" ] || fail_test ".gitignore not created"
assert_eq "$(grep -cxF '.rca/' "$REPO2/.gitignore")" "1" "created .gitignore has .rca/"

# ---- init: slug collision (non-empty dir) errors -----------------------------
out=$(bash "$SCAFFOLD" init flaky-login --description "again" || true)
assert_json "$out" '.ok == false and .error == "slug_exists"' "collision → slug_exists"

# ---- init: empty existing dir is allowed -------------------------------------
mkdir -p .rca/empty-slug
out=$(bash "$SCAFFOLD" init empty-slug --description d || true)
assert_json "$out" '.ok == true' "empty existing dir re-inits"

# ---- init: outside a git repo → not_a_git_repo -------------------------------
NOGIT="$(mktmp)"
out=$(cd "$NOGIT" && bash "$SCAFFOLD" init z || true)
assert_json "$out" '.ok == false and .error == "not_a_git_repo"' "no git → not_a_git_repo"

# ---- set: round-trip incl. dotted (nested) key -------------------------------
out=$(bash "$SCAFFOLD" set flaky-login --stack.test_cmd "swift test" --tier full)
assert_json "$out" '.ok == true' "set ok"
assert_json "$out" '(.updated | index("stack.test_cmd")) != null' "set reports dotted key"
meta=$(cat .rca/flaky-login/meta.json)
assert_eq "$(jqf "$meta" '.stack.test_cmd')" "swift test" "dotted key set nested value"
assert_eq "$(jqf "$meta" '.tier')" "full" "set top-level tier"

# ---- set: missing meta → no_meta ---------------------------------------------
out=$(bash "$SCAFFOLD" set nonexistent --tier full || true)
assert_json "$out" '.ok == false and .error == "no_meta"' "set on missing → no_meta"

# ---- slug: deterministic normalization + edge cases --------------------------
assert_eq "$(jqf "$(bash "$SCAFFOLD" slug 'My Flaky Login Test Fails Sometimes On CI')" '.slug')" \
          "my-flaky-login-test-fails" "slug lowercases, hyphenates, caps 5 words"
assert_eq "$(jqf "$(bash "$SCAFFOLD" slug '  Weird!!! ___ Chars ///  ')" '.slug')" \
          "weird-chars" "slug squeezes/ trims non-alnum runs"
assert_eq "$(jqf "$(bash "$SCAFFOLD" slug 'CVE-2026-1234 Heap Overflow')" '.slug')" \
          "cve-2026-1234-heap-overflow" "slug keeps digits"
assert_eq "$(jqf "$(bash "$SCAFFOLD" slug '')" '.slug')" "" "empty text → empty slug (no crash)"

finish
