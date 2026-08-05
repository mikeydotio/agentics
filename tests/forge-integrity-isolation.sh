#!/usr/bin/env bash
# tests/forge-integrity-isolation.sh — forge-integrity.bats must own exactly
# its own subtree of the shared snapshot root: it may not delete anything it
# did not create, and it may not stop deleting what it did.
#
# WHY THIS EXISTS
#
# `forge-integrity.sh` stores integrity baselines under /tmp/forge-integrity,
# keyed by a digest of the project's absolute path. That root is MACHINE-GLOBAL
# — it holds the live baselines of every project on the box at once, which is
# exactly what makes concurrent forge sessions in different repositories safe.
#
# forge-integrity.bats's teardown used to `rm -rf` that entire root. Per-test
# paths are content-hashed and unique, so the blanket rm was described in its
# own comment as merely keeping /tmp tidy. It was not: it deleted every OTHER
# project's baselines too — every concurrently running copy of the suite, and
# any real forge session running elsewhere on the machine (AGE-34).
#
# Measured, one variable. A single bats run whose only concurrent actor was a
# loop doing `rm -rf /tmp/forge-integrity` — no second suite, no second fixture
# tree, no working-tree churn — failed 14 of 19 tests and reproduced AGE-34's
# reported symptom verbatim (`jq: parse error: Invalid numeric literal at line
# 1, column 70`). Solo baseline was 19/19. After the fix, the configuration
# that had produced 37 spurious failures (4 concurrent runs x 3 rounds)
# produced 0.
#
# WHY THIS IS BIDIRECTIONAL, AND WHY THAT IS THE WHOLE POINT
#
# A one-sided "the sentinel survived" check is satisfied by deleting the
# teardown line altogether. That trades a clobber for an unbounded leak and
# would report green. So the over-delete arm is paired with an under-delete
# arm: after the run, the root must contain nothing that was not already there
# before it. Together they pin teardown to exactly its own subtree.
#
# WHY A SOURCE-LEVEL GUARD IS NOT USED INSTEAD (AGE-34 council, unanimous)
#
# A guard banning `rm -r` of a literal /tmp path cannot decide this class:
#   * plugins/greenlight/tests/greenlight.bats:295 passes the string
#     'echo $(rm -rf /tmp/foo)' to run_bash, which jq-encodes it onto the
#     classifier's stdin. It is DATA and never executes, yet it is
#     syntactically identical to an executed call. Same shape, opposite kind —
#     AGE-26's rule, not AGE-22's.
#   * The class's other live members are invisible to an rm-shaped predicate
#     anyway: deployit binds 14 hardcoded ports (AGE-56), and two fake tmux
#     shims default to a shared /tmp/issue-faketmux via a VARIABLE, not a
#     literal at the call site (AGE-57). The sweep that found them had already
#     missed them once for exactly that reason.
# So the invariant is enforced behaviorally, here, where it is decidable.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="$REPO_ROOT/plugins/forge/bin/forge-integrity.bats"
SNAPSHOT_ROOT="/tmp/forge-integrity"

# One executed test still fires setup and teardown, which is all this file
# needs — and it costs one test instead of twenty.
FILTER='snapshot: reports ok, phase, scope, head, file_count'

fail() { echo "    $*" >&2; return 1; }

# Tool availability is a FAILURE, never a skip: a gate that reports success
# having verified nothing is the defect class this repo keeps re-filing
# (AGE-18). Same reasoning as tests/gate-integrity.sh.
require_tools() {
    command -v bats >/dev/null 2>&1 || {
        echo "bats is not installed — install bats-core (brew install bats-core)" >&2
        exit 1
    }
    [ -f "$SUITE" ] || { echo "missing suite: $SUITE" >&2; exit 1; }
}

# Plant a baseline belonging to some OTHER project, under a key this run
# invents. A unique key per invocation keeps two concurrent copies of THIS
# file from reading each other's sentinel.
plant_sentinel() {
    local key="age34-sentinel-$$-${RANDOM}"
    local dir="$SNAPSHOT_ROOT/$key/default"
    mkdir -p "$dir" || return 1
    printf '{"phase":"foreign","head":"deadbeef","files":{}}\n' > "$dir/pre-gen.json" || return 1
    printf '%s' "$SNAPSHOT_ROOT/$key"
}

run_suite() {
    ( cd "$REPO_ROOT" && bats --filter "$FILTER" "$SUITE" ) >/dev/null 2>&1
}

entries() { ls -1 "$SNAPSHOT_ROOT" 2>/dev/null | sort; }

# ── Tests ──────────────────────────────────────────────────────────────────

# The over-delete arm. This is the arm that was RED before AGE-34's fix.
test_suite_does_not_delete_a_foreign_projects_snapshot() {
    local sentinel; sentinel="$(plant_sentinel)" || { fail "could not plant sentinel"; return 1; }
    local file="$sentinel/default/pre-gen.json"

    # Anti-vacuity: prove the sentinel is readable BEFORE the run. Without
    # this, a plant that silently failed would make the survival assertion
    # below pass for the wrong reason.
    [ -f "$file" ] || { fail "sentinel was not readable before the run — oracle proves nothing"; return 1; }
    local before_content; before_content="$(cat "$file")"

    run_suite
    local rc=$?

    if [ ! -f "$file" ]; then
        rm -rf "$sentinel"
        fail "the suite deleted another project's snapshot at $file"; return 1
    fi
    if [ "$(cat "$file")" != "$before_content" ]; then
        rm -rf "$sentinel"
        fail "the suite modified another project's snapshot at $file"; return 1
    fi
    rm -rf "$sentinel"
    rmdir "$SNAPSHOT_ROOT" 2>/dev/null || true

    # A suite that errored out could leave the sentinel intact for reasons
    # having nothing to do with isolation, so the verdict is only meaningful
    # alongside a clean exit.
    [ "$rc" -eq 0 ] || { fail "the filtered suite itself failed (exit $rc)"; return 1; }
}

# The under-delete arm. Deleting teardown's rm entirely satisfies the arm
# above; it does not satisfy this one.
test_suite_removes_its_own_snapshot_subtree() {
    local sentinel; sentinel="$(plant_sentinel)" || { fail "could not plant sentinel"; return 1; }
    local before; before="$(entries)"

    run_suite || true

    local after; after="$(entries)"
    local leaked
    leaked="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"

    rm -rf "$sentinel"
    rmdir "$SNAPSHOT_ROOT" 2>/dev/null || true

    [ -z "$leaked" ] || {
        fail "the suite left its own snapshot dir(s) behind: $(printf '%s' "$leaked" | tr '\n' ' ')"
        return 1
    }
}

# Proves the over-delete oracle can actually observe a deletion. An arm whose
# PASS is "the file is still there" is vacuous unless something demonstrates it
# would notice the file being gone (the AGE-22 plumbing rule).
test_over_delete_oracle_can_detect_a_deletion() {
    local sentinel; sentinel="$(plant_sentinel)" || { fail "could not plant sentinel"; return 1; }
    local file="$sentinel/default/pre-gen.json"
    [ -f "$file" ] || { fail "sentinel was not readable before the simulated clobber"; return 1; }

    # Exactly what the pre-fix teardown did.
    rm -rf "$SNAPSHOT_ROOT"

    if [ -f "$file" ]; then
        rm -rf "$sentinel"
        fail "a blanket rm of the root did NOT remove the sentinel — this oracle cannot detect the defect it exists for"
        return 1
    fi
    rmdir "$SNAPSHOT_ROOT" 2>/dev/null || true
}

# ── Runner ─────────────────────────────────────────────────────────────────

require_tools

echo "=== forge-integrity-isolation ==="
passed=0; failed=0; failures=()
for t in $(declare -F | awk '{print $3}' | /usr/bin/grep '^test_' | sort); do
    if ( set -e; "$t" ); then
        echo "  PASS  $t"; passed=$((passed + 1))
    else
        echo "  FAIL  $t"; failed=$((failed + 1)); failures+=("$t")
    fi
done

echo
echo "Results: $passed passed, $failed failed"
if [ "$failed" -gt 0 ]; then
    echo "Failures:"
    printf '  - %s\n' "${failures[@]}"
fi
exit "$failed"
