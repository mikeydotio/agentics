#!/usr/bin/env bash
# THE safety test. push must: (1) refuse a protected destination; (2) emit a
# leased, non---force planned command; (3) really rewrite origin on the happy
# path; (4) refuse (never --force) when the lease is stale.
source "$(dirname "$0")/lib.sh"
PR=7

# ---- (1) protected destination → refuse "protected" --------------------------
CO="$(reconcile_fixture clean)"
rp "$CO" start "$PR" >/dev/null
out=$(cd "$CO" && RECONCILE_PR_PROTECTED_GLOBS="pr-branch" RECONCILE_PR_ALLOW_UNTESTED=1 \
      RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "protected dest → ok:false"
assert_eq "$(jqf "$out" '.reason')" "protected" "protected dest → reason protected"

# ---- (2) planned command is leased + explicit + never a bare --force ----------
out=$(cd "$CO" && RECONCILE_PR_ALLOW_UNTESTED=1 RECONCILE_PR_SKIP_PUSH=1 bash "$SCRIPT" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "skip-push → ok:true"
assert_eq "$(jqf "$out" '.pushed')" "false" "skip-push → pushed:false"
planned=$(jqf "$out" '.planned_command')
assert_contains "$planned" "--force-with-lease=refs/heads/pr-branch:" "planned uses explicit-OID lease"
assert_contains "$planned" "HEAD:refs/heads/pr-branch" "planned pushes HEAD:refs/heads/<dest>"
assert_contains "$planned" 'insteadOf="git@github.com:"' "planned uses HTTPS override"
assert_not_contains "$planned" "--force " "planned NEVER uses a bare --force"
assert_not_contains "$planned" "push -f" "planned NEVER uses push -f"

# ---- (3) happy path really rewrites origin/pr-branch --------------------------
CO2="$(reconcile_fixture clean)"
ORIGIN2="$(fixture_origin "$CO2")"
orig_tip=$(git -C "$ORIGIN2" rev-parse pr-branch)
rp "$CO2" start "$PR" >/dev/null
rp "$CO2" test "$PR" >/dev/null            # → no_test_command (warn+allow)
out=$(rp "$CO2" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "happy push → ok:true"
assert_eq "$(jqf "$out" '.pushed')" "true" "happy push → pushed:true"
new_oid=$(jqf "$out" '.new_oid')
assert_contains "$(jqf "$out" '.warning')" "no test command" "happy push (no tests) → warns"
pushed_tip=$(git -C "$ORIGIN2" rev-parse pr-branch)
assert_eq "$pushed_tip" "$new_oid" "origin/pr-branch now equals the reconciled HEAD"
assert_ne "$pushed_tip" "$orig_tip" "origin/pr-branch history was rewritten"

# ---- (4) stale lease → refuse "stale", NEVER falling back to --force ----------
CO3="$(reconcile_fixture clean)"
ORIGIN3="$(fixture_origin "$CO3")"
SEED3="$(fixture_seed "$CO3")"
rp "$CO3" start "$PR" >/dev/null           # records remote_oid = current origin/pr-branch
rp "$CO3" test "$PR" >/dev/null
# Out-of-band: someone else advances origin/pr-branch after we started.
( cd "$SEED3" && _git switch -q pr-branch && printf 'sneaky\n' >> other.txt \
    && _git add -A && _git commit -qm "out-of-band" && _git push -q origin pr-branch ) >/dev/null 2>&1
before=$(git -C "$ORIGIN3" rev-parse pr-branch)
out=$(rp "$CO3" push "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "stale lease → ok:false"
assert_eq "$(jqf "$out" '.reason')" "stale" "stale lease → reason stale"
after=$(git -C "$ORIGIN3" rev-parse pr-branch)
assert_eq "$after" "$before" "stale refusal did NOT clobber origin (no --force fallback)"

finish
