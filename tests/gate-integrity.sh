#!/usr/bin/env bash
# tests/gate-integrity.sh — the gate must mean what it reports.
#
# WHY: `make test` is the SOLE pre-push gate (~/.claude/hooks/pre-push-tests.sh
# runs it and blocks the push on a non-zero exit; there is no CI, per CLAUDE.md).
# Until AGE-18 the five bats targets were written as
#
#     @if command -v bats >/dev/null 2>&1; then <run the suite>; \
#      else echo "bats not installed — skipping ..."; fi
#
# so on any machine without bats the gate exited 0 having verified nothing. That
# is worse than a red gate: it reports success. Its cost is already paid — ~60
# tests were red on main for an unknown period (AGE-15) and the gate never said
# so, because a missing tool was modelled as "not applicable" rather than
# "cannot verify".
#
# The fix was deletion, not a new guard: all five runners (tests/run-tests.sh
# plus four plugins/*/tests/run-tests.sh) ALREADY hard-fail with an actionable
# message, so the Makefile conditional was a second, wrong copy of a policy that
# already had an owner one layer down. Deleting it also covers the direct
# `bash plugins/forge/tests/run-tests.sh` entry path, which a Make-level
# prerequisite target could never reach.
#
# WHAT THIS PINS:
#   1. Each of the five bats targets exits NON-ZERO when bats is absent.
#   2. Each of them still actually RUNS its suite when bats is present — an
#      effect oracle, not a status reading. Without it, `test-root-bats: false`
#      would satisfy (1) perfectly while verifying nothing at all.
#   3. No Makefile recipe reintroduces the swallow (the class killer).
#   4. No plugin test skips because an in-repo path is missing — absence of a
#      path this repository ships means a broken checkout, never "not
#      applicable". That is the class of plugins/deployit/tests/test-cli-bump.sh,
#      whose exit-0 skip was counted as PASS by its own runner.
#
# It never recurses into a real suite: in (1) bats is absent by construction so
# every target dies at its runner's check, and in (2) the `bats` on PATH is a
# stub that records its invocation and exits 0 immediately. A full `make test`
# costs minutes (see the distribution in CLAUDE.md's "Gate cost" section — median
# ~630s as of 2026-08-05, tail censored at the hook's 900s timeout); this runs in
# about a second.
#
# ⚠ This line used to read "takes ~15 minutes", which is 900s — numerically equal to
# the pre-push hook's entire budget, and stated as a bare scalar. Two consecutive
# stories read past it to OPPOSITE wrong conclusions (AGE-32 "the hook is not
# firing", AGE-35 "comfortably inside budget"). Quote the distribution, never a
# scalar: every scalar this repo has written about this suite has been misread.
#
# Deliberately NOT here: `make test` itself is never invoked (that would recurse
# into this very suite), and the ~10 deployit skips predicated on
# hdiutil/ditto/PlistBuddy stay legal — a platform genuinely lacking a macOS
# tool IS "not applicable", which is a different predicate from "cannot verify".
#
# Self-contained plain-bash harness (NO bats — a bats test asserting bats is
# missing would be self-defeating), mirroring tests/plugin-versions.sh and
# tests/store-isolation.sh: define test_* functions, run each in an isolated
# subshell, print "  PASS|FAIL  fn", exit with the failure count.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolved BEFORE any PATH filtering, so the assertions below still have a `make`
# to run even on a machine whose only `make` lives in a directory that also ships
# `bats` (filtering by directory is necessarily coarse).
MAKE_BIN="$(command -v make || true)"

# The targets whose recipes used to swallow a missing bats. Named explicitly and
# individually: these are the user-facing targets the gate actually runs. Never
# assert against a helper/prerequisite target instead — a target that does not
# exist also exits non-zero, which would make this file pass vacuously.
BATS_TARGETS=(test-root-bats test-forge test-hook-guard test-greenlight test-freshen)

fail() { echo "$1" >&2; return 1; }

# --- Environment construction ----------------------------------------------

# PATH with every directory that provides a `bats` removed.
#
# Filtering by "does this dir contain bats" rather than hardcoding a minimal
# PATH like /usr/bin:/bin is what keeps this test honest across machines: bats
# installs to /opt/homebrew/bin under Homebrew but to /usr/bin under apt, and a
# hardcoded /usr/bin:/bin would silently become a no-op assertion there —
# reproducing nothing while still reporting PASS.
bats_free_path() {
    local out="" d
    local IFS=:
    for d in $PATH; do
        [ -n "$d" ] || continue
        [ -x "$d/bats" ] && continue
        out="${out:+$out:}$d"
    done
    printf '%s' "$out"
}

# A `bats` that records that it was invoked and exits 0 immediately, so the
# positive assertions can prove the suite was REACHED without paying the real
# suite's cost (minutes — see CLAUDE.md's "Gate cost") to run it for real.
#
# Built once per file at a stable path and warmed below: macOS assesses a freshly
# written executable on its first exec (XProtect/syspolicyd), which cost AGE-16's
# suite ~107s in per-test shims. Nothing here is timed, so this is purely to keep
# the suite fast.
STUB_DIR="$(mktemp -d /private/tmp/agentics-batsstub.XXXXXX)"
STUB_LOG="$STUB_DIR/invocations"
: > "$STUB_LOG"
cat > "$STUB_DIR/bats" <<'STUB'
#!/bin/bash
printf 'invoked\n' >> "${BATS_STUB_LOG:?BATS_STUB_LOG unset}"
exit 0
STUB
chmod +x "$STUB_DIR/bats"
BATS_STUB_LOG="$STUB_LOG" "$STUB_DIR/bats" >/dev/null 2>&1 || true   # warm first-exec
: > "$STUB_LOG"
trap 'rm -rf "$STUB_DIR"' EXIT

# --- The environment itself must be valid, or everything below is vacuous ---

test_bats_free_path_actually_hides_bats() {
    local p; p="$(bats_free_path)"
    [ -n "$p" ] || fail "bats_free_path produced an empty PATH — cannot construct the scenario" || return 1
    if ( export PATH="$p"; command -v bats >/dev/null 2>&1 ); then
        fail "bats is STILL reachable under the bats-free PATH — every 'fails without bats'
        assertion below would be testing nothing. PATH was: $p"
        return 1
    fi
    # ...and the tools the assertions themselves need must survive the filtering,
    # or a target would exit non-zero merely because `make`/`bash` vanished.
    [ -n "$MAKE_BIN" ] && [ -x "$MAKE_BIN" ] \
        || fail "no usable make binary resolved before filtering" || return 1
    ( export PATH="$p"; command -v bash >/dev/null 2>&1 ) \
        || fail "bash disappeared with the bats directory; cannot run recipes" || return 1
}

# --- 1. A missing tool must fail the gate, never skip it --------------------

test_every_bats_target_fails_when_bats_is_absent() {
    local p offenders=() t rc
    p="$(bats_free_path)"
    for t in "${BATS_TARGETS[@]}"; do
        # `|| rc=$?` (not a bare call then `rc=$?`) because the harness runs each
        # test under `set -e`: an unchecked subshell that exits non-zero aborts
        # the function before the status can even be read — so a CORRECTLY
        # failing target would report this assertion red against a working fix.
        rc=0
        ( export PATH="$p"; "$MAKE_BIN" -C "$REPO_ROOT" "$t" ) >/dev/null 2>&1 || rc=$?
        # Likewise an `if`, not `[ ... ] && arr+=(...)`: a trailing `&&` list that
        # evaluates false is itself a non-zero command under `set -e`.
        if [ "$rc" -eq 0 ]; then offenders+=("$t"); fi
    done
    if [ "${#offenders[@]}" -gt 0 ]; then
        fail "these targets exited 0 with bats absent — the gate reports success having verified nothing:
$(printf '          - %s\n' "${offenders[@]}")
        A missing tool must FAIL the gate (\`make test\` is the only pre-push guard).
        Bypass belongs at the policy edge (SKIP_PREPUSH_TESTS=1), never inside the verification unit."
        return 1
    fi
}

# --- 2. ...and the suite must still actually run when the tool IS present ---
#
# The effect oracle. Guards against the degenerate "fix" of making the targets
# unconditionally fail, which would satisfy every assertion above.

test_every_bats_target_runs_the_suite_when_bats_is_present() {
    local p never_ran=() nonzero=() t rc before after
    p="$STUB_DIR:$(bats_free_path)"
    for t in "${BATS_TARGETS[@]}"; do
        before="$(wc -l < "$STUB_LOG")"
        rc=0
        ( export PATH="$p" BATS_STUB_LOG="$STUB_LOG"; "$MAKE_BIN" -C "$REPO_ROOT" "$t" ) >/dev/null 2>&1 || rc=$?
        after="$(wc -l < "$STUB_LOG")"
        [ "$rc" -eq 0 ] || nonzero+=("$t")
        [ "$after" -gt "$before" ] || never_ran+=("$t")
    done
    if [ "${#nonzero[@]}" -gt 0 ]; then
        fail "these targets failed even with bats available:
$(printf '          - %s\n' "${nonzero[@]}")"
        return 1
    fi
    if [ "${#never_ran[@]}" -gt 0 ]; then
        fail "these targets exited 0 without ever invoking bats — they are not running their suite:
$(printf '          - %s\n' "${never_ran[@]}")"
        return 1
    fi
}

# --- 3. Class killer: no recipe may swallow a missing tool ------------------

test_makefile_never_swallows_a_missing_tool() {
    local hits
    # Recipe lines only (leading tab). Prose in a comment explaining WHY the
    # swallow is banned must not itself trip the ban.
    hits="$(grep -nE '^\t.*(command -v bats|echo[^|]*skipping)' "$REPO_ROOT/Makefile" || true)"
    if [ -n "$hits" ]; then
        fail "the Makefile is branching on tool availability or echoing a skip again:
$(echo "$hits" | sed 's/^/          /')
        Tool-availability policy belongs in the suite runners (they already exit 1
        with an actionable message, and they cover direct \`bash <runner>\` invocation
        too). A Makefile recipe that echoes and succeeds is exactly AGE-18."
    fi
}

# --- 4. Class killer: no test may skip because an in-repo path is missing ---

test_plugin_tests_never_skip_on_a_filesystem_path_predicate() {
    local hits=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        # A filesystem-existence predicate whose body exits 0 within two lines.
        # `command -v <tool>` skips are deliberately NOT matched: a platform that
        # genuinely lacks hdiutil/ditto/PlistBuddy is "not applicable", which is a
        # different claim from "this repo is missing its own file". Assertions
        # that exit 1 on a missing path are the correct shape and stay green.
        #
        # Known limit: the `exit 0` must appear within 2 lines of the predicate.
        # A skip spread wider than that evades this check. Widening the window
        # trades that false negative for false positives on an assertion that
        # merely happens to precede an unrelated `exit 0`; 2 covers every shape
        # in the repo today (verified against all four variants).
        hits+="$(awk -v F="$f" '
            /\[\[?[[:space:]]+! -[fdx][[:space:]]/ { ln=NR; line=$0; n=0; found=0
                if (line ~ /exit 0/) found=1
                while (n < 2 && (getline nx) > 0) { n++; if (nx ~ /exit 0/) found=1 }
                if (found) printf "%s:%d: %s\n", F, ln, line
            }' "$f")"
    done <<< "$(find "$REPO_ROOT/plugins" -path '*/tests/test-*.sh' -type f | sort)"
    hits="$(printf '%s' "$hits" | grep -vE '^$' || true)"
    if [ -n "$hits" ]; then
        fail "these tests SKIP (exit 0) because a filesystem path is missing:
$(echo "$hits" | sed 's/^/          /')
        These paths live in this repository — absence means a broken checkout, never
        'not applicable'. Fail loudly instead, so the suite cannot report PASS for a
        test it never ran (plugins/*/tests/run-tests.sh counts exit 0 as PASS)."
    fi
}

PASS=0
FAIL=0
FAILURES=()

echo "=== gate-integrity ==="
for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    set +e
    out="$( set -e; "$fn" 2>&1 )"
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        echo "  PASS  $fn"
        [ -n "$out" ] && echo "$out" | sed 's/^/        /'
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $fn"
        [ -n "$out" ] && echo "$out" | sed 's/^/        /'
        FAIL=$((FAIL + 1))
        FAILURES+=("$fn")
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    printf 'Failures:\n'
    printf '  - %s\n' "${FAILURES[@]}"
fi
exit "$FAIL"
