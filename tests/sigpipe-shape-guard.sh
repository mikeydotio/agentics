#!/usr/bin/env bash
# tests/sigpipe-shape-guard.sh — an early-exit consumer must not drain a
# producer that is still writing, in a file that arms `pipefail`.
#
# THE MECHANISM. `grep -q` (and `grep -m N`, and `head`) exit on their first
# match. A producer that interleaves computation with writes — `git log` walking
# history, `find` walking a tree — is then killed by SIGPIPE mid-write, and
# `set -o pipefail` propagates 141 as the PIPELINE's status. The match succeeded;
# the status says it failed. An assertion built this way reports failure when the
# thing it asserts is TRUE.
#
# HOW LOUD IT IS, measured against log size (the variable nobody varied for two
# months, and the reason five harnesses disagreed):
#
#     commits   `log --oneline`   failures
#         2          130 B          13/60      <- unstable region
#        50          3.3 KB         60/60
#       500           33 KB         60/60
#      2000          134 KB         60/60
#
# The rate saturates at 100% once the output exceeds the pipe buffer, because
# the producer then provably CANNOT have finished writing. Every disputed
# measurement (0, 9, 11, 21, 22, 37, 46, 65 percent) was taken in the 2-commit
# region, the only place the outcome is a coin flip. This guard therefore sizes
# its fixture PAST the buffer and asserts that size, so it tests a certainty
# rather than a race.
#
# ⚠ WHAT THIS CLASS HAS AND HAS NOT DONE HERE. It has never caused a confirmed
# failure in this repo. AGE-21 was filed on the theory that a live backend daemon
# caused its flake; that was measured false. The chair's replacement theory (this
# SIGPIPE class caused it) was RETRACTED — a 50-iteration poll over a 2-commit
# log cannot exhaust. A third theory (DEPLOYIT_SKIP_GC_PUSH leaking in) was also
# refuted, because that variable suppresses the backend-refresh warning which is
# present in the recorded output. AGE-21's observed 2026-08-04 failure remains
# formally UNEXPLAINED. This file is PREVENTION for an unsound shape, not a cure
# for that incident, and it must never be re-justified by resurrecting one of
# those three retracted stories — restating a falsified cause in a guard header
# is how the previous wrong theory survived two months of readers.
#
# ⚠ KNOWN LIMIT OF THE SCAN, recorded because the dissenting council seat is
# right about it. The invariant is "the producer interleaves computation with
# writes". The scan implements that as an ENUMERATION of walkers (git
# log/rev-list/shortlog/grep/blame, find, locate). A python3 generator, a
# streaming curl, a `jq --stream`, or an awk over a large file all have the
# property and are NOT matched. The bounded-to-one exemption is mechanism-tied
# and principled; the walker list is calibration. Treat a green scan as "none of
# the known walkers", not "none possible".

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RM_TEST="$REPO_ROOT/plugins/deployit/tests/test-cli-rm.sh"

PASS=0
FAIL=0
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A bare repo whose `log --oneline` exceeds the pipe buffer, with the needle on
# the TIP so an early-exit consumer matches line 1 and leaves immediately while
# ~2000 lines remain unwritten.
NEEDLE='rm build app-ios-local1 via web from demo.tail.ts.net'
BIG="$WORK/big.git"

build_big_fixture() {
    git init --bare --quiet --initial-branch=main "$BIG"
    python3 - "$NEEDLE" <<'PY' | git -C "$BIG" fast-import --quiet
import sys
needle = sys.argv[1]
N = 2000
out = sys.stdout
for i in range(1, N + 1):
    msg = ("chore(deploy): " + needle) if i == N else \
          f"chore(deploy): filler commit {i} padding the log past the pipe buffer"
    out.write("commit refs/heads/main\n")
    out.write(f"mark :{i}\n")
    out.write("committer test <t@e.invalid> 0 +0000\n")
    data = msg.encode()
    out.write(f"data {len(data)}\n")
    out.write(msg + "\n")
    if i > 1:
        out.write(f"from :{i - 1}\n")
    out.write("\n")
PY
}

# A state dir shaped like the test's own: $1/remote.git is a bare repo whose
# main tip carries $2 as its subject and $3 as builds.json. The helper resolves
# "$ROOT/remote.git", so the fixture must sit at that exact path.
make_index_fixture() {
    local root="$1" subject="$2" json="$3" dir w
    mkdir -p "$root"
    dir="$root/remote.git"
    w=$(mktemp -d "$WORK/w.XXXXXX")
    git init --bare --quiet --initial-branch=main "$dir"
    git init --quiet --initial-branch=main "$w"
    git -C "$w" config user.email t@e.invalid
    git -C "$w" config user.name test
    printf '%s\n' "$json" > "$w/builds.json"
    git -C "$w" add builds.json
    git -C "$w" commit --quiet -m "$subject"
    git -C "$w" remote add origin "$dir"
    git -C "$w" push --quiet --set-upstream origin main
}

# The SHIPPED helper, lifted verbatim out of test-cli-rm.sh. Binding to the real
# file rather than a copy is the point: a copy silently stops agreeing with the
# thing it claims to protect.
extract_origin_published() {
    awk '/^origin_published\(\) \{/ {f=1} f {print} f && /^\}/ {exit}' "$RM_TEST"
}

# ---------------------------------------------------------------------------
# The class is real, on real git, with no synthetic producer anywhere
# ---------------------------------------------------------------------------

test_fixture_log_exceeds_the_pipe_buffer() {
    local bytes
    bytes=$(git -C "$BIG" log --oneline | wc -c | tr -d ' ')
    if [ "$bytes" -le 65536 ]; then
        echo "fixture log is ${bytes}B, needs >65536 — below the pipe buffer the"
        echo "mechanism is a race and every arm below becomes a coin flip"
        return 1
    fi
}

test_early_exit_consumer_reports_141_on_a_successful_match() {
    local rc=0
    ( set -o pipefail; git -C "$BIG" log --oneline | grep -q "$NEEDLE" ) || rc=$?
    if [ "$rc" -ne 141 ]; then
        echo "expected 141 (SIGPIPE), got $rc"
        echo "if this is 0, the defect class this guard exists for is no longer"
        echo "reproducible on this git/bash/OS — re-derive it before deleting the"
        echo "guard, do not simply assume the risk is gone"
        return 1
    fi
}

test_the_match_actually_succeeded_while_the_status_said_it_failed() {
    # The falsehood is not "the pipeline failed" — it is "the pipeline failed
    # WHILE MATCHING". Without this, arm above is satisfied by a missing needle.
    local out
    out=$( set -o pipefail; git -C "$BIG" log --oneline | grep -m1 "$NEEDLE" ) || true
    if [[ "$out" != *"$NEEDLE"* ]]; then
        echo "expected the consumer to have matched the needle; got: '$out'"
        return 1
    fi
}

test_full_consumption_is_safe_on_the_same_fixture() {
    local log rc=0
    log=$( set -o pipefail; git -C "$BIG" log --oneline ) || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "full consumption should exit 0, got $rc"
        return 1
    fi
    if [[ "$log" != *"$NEEDLE"* ]]; then
        echo "sanctioned form did not find the needle"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# The shipped helper discriminates four outcomes, not two
# ---------------------------------------------------------------------------

run_shipped_helper() {  # <repo-dir> <subject-substring> <build-id> -> exit code
    local root="$1" subj="$2" id="$3" body rc=0
    body=$(extract_origin_published)
    ( set -euo pipefail
      ROOT="$root"
      eval "$body"
      origin_published "$subj" "$id" ) >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

test_helper_extraction_is_not_empty() {
    local body
    body=$(extract_origin_published)
    if [ -z "$body" ]; then
        echo "could not extract origin_published() from $RM_TEST"
        echo "a rename or reformat must fail loudly here rather than silently"
        echo "leaving the arms below verifying a function that no longer exists"
        return 1
    fi
    if [[ "$body" != *"origin_published()"* || "$body" != *"}"* ]]; then
        echo "extracted text does not look like the helper: $body"
        return 1
    fi
}

test_helper_passes_when_the_rm_was_published() {
    local d="$WORK/case-ok" rc
    make_index_fixture "$d" "chore(deploy): rm build app-ios-local1 via web" \
        '{"builds": [{"id": "app-ios-local2"}]}'
    rc=$(run_shipped_helper "$d" "rm build app-ios-local1" app-ios-local1)
    [ "$rc" = "0" ] || { echo "expected 0, got $rc"; return 1; }
}

test_helper_fails_when_origin_still_lists_the_build() {
    # The content arm. A publisher that commits the right MESSAGE with nothing
    # staged satisfies a subject-only check; this is what makes the oracle an
    # effect oracle rather than a decoration.
    local d="$WORK/case-content" rc
    make_index_fixture "$d" "chore(deploy): rm build app-ios-local1 via web" \
        '{"builds": [{"id": "app-ios-local1"}, {"id": "app-ios-local2"}]}'
    rc=$(run_shipped_helper "$d" "rm build app-ios-local1" app-ios-local1)
    [ "$rc" = "1" ] || { echo "expected 1 (content still listed), got $rc"; return 1; }
}

test_helper_fails_on_a_wrong_subject() {
    local d="$WORK/case-subject" rc
    make_index_fixture "$d" "chore(deploy): tidy the index" \
        '{"builds": [{"id": "app-ios-local2"}]}'
    rc=$(run_shipped_helper "$d" "rm build app-ios-local1" app-ios-local1)
    [ "$rc" = "1" ] || { echo "expected 1 (wrong subject), got $rc"; return 1; }
}

test_helper_exits_2_when_the_repo_cannot_be_read() {
    # "I could not verify this" is not "the rm was not pushed". Reporting a
    # broken read as a negative assertion is the same lie the old pipeline told.
    local rc
    rc=$(run_shipped_helper "$WORK/definitely-not-a-repo" "rm build x" x)
    [ "$rc" = "2" ] || { echo "expected 2 (unreadable), got $rc"; return 1; }
}

# ---------------------------------------------------------------------------
# The shape scan
# ---------------------------------------------------------------------------

WALKER='git([[:space:]]+-[cC][[:space:]]+[^[:space:]|]+)*[[:space:]]+(log|rev-list|shortlog|grep|blame)|(^|[[:space:];(`$&])(find|locate)[[:space:]]'
EARLY='grep[[:space:]][^|]*-[a-zA-Z]*q|grep[[:space:]][^|]*-m[[:space:]]*[0-9]|head([[:space:]]|$)'
# A bound of exactly ONE record is exempt on mechanism: one record is one write,
# it fits inside the pipe buffer, so the producer has nothing left to write when
# the consumer exits. Measured: `git log -1 --pretty=%s | grep -q` fails 0/1000.
BOUNDED='[^|]*(-1|-n[[:space:]]*1|--max-count[=[:space:]]*1)([[:space:]]|$)[^|]*\|'

# Lines whose first non-space character is `#` are prose, not invocations. This
# matters: test-cli-rm.sh deliberately QUOTES the banned form in a comment that
# tells the next reader never to reintroduce it. A guard you can satisfy by
# deleting a true sentence is the wrong guard.
scan_repo() {
    git -C "$REPO_ROOT" grep -nIE "(${WALKER})[^|]*\|[[:space:]]*(${EARLY})" \
        -- '*.sh' '*.bash' '*.bats' 'Makefile' \
        ':(exclude)tests/sigpipe-shape-guard.sh' 2>/dev/null \
        | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' \
        | grep -vE "$BOUNDED" || true
}

test_no_early_exit_consumer_drains_a_stream_walker() {
    local hits
    hits=$(scan_repo)
    if [ -n "$hits" ]; then
        echo "early-exit consumer over an unbounded stream walker:"
        echo "$hits" | sed 's/^/    /'
        echo "bound the PRODUCER instead (git log -5, not | head -5), or consume"
        echo "the output whole into a variable and match in-shell"
        return 1
    fi
}

test_scan_self_exclusion_is_exactly_one_pinned_file() {
    # The guard necessarily contains the patterns it bans (its own regexes and
    # fixtures). That exemption is pinned so it cannot quietly grow to cover a
    # real site.
    local body excl
    body=$(awk '/^scan_repo\(\) \{/ {f=1} f {print} f && /^\}/ {exit}' "${BASH_SOURCE[0]}")
    excl=$(printf '%s\n' "$body" | grep -c ":(exclude)")
    [ "$excl" = "1" ] || { echo "expected exactly 1 exclusion in scan_repo, found $excl"; return 1; }
    printf '%s\n' "$body" | grep -q ":(exclude)tests/sigpipe-shape-guard.sh" \
        || { echo "the one exclusion is not this file"; return 1; }
}

# --- detector accuracy, as an executable arm rather than a one-time measurement

DANGEROUS=(
    'git log --oneline | grep -q needle'
    'git -C "$d" log --format=%s | grep -q needle'
    'git -c core.pager=cat log | grep -qx needle'
    'git rev-list HEAD | grep -q deadbeef'
    'git shortlog | grep -q author'
    'git grep foo | grep -q bar'
    'git blame f | grep -q needle'
    'find . -name x | grep -q y'
    'git log --oneline | head -5'
)
BENIGN=(
    'echo "$out" | grep -q needle'
    'printf "%s" "$x" | grep -q needle'
    'cat file.txt | grep -q needle'
    'python3 -c "print(1)" | grep -q needle'
    'git log -1 --pretty=%s | grep -q needle'
    'git log --max-count=1 | grep -q needle'
    'git log -n 1 --oneline | grep -q needle'
    'git show --name-only --pretty=format: HEAD | grep -qx app.txt'
    'git log --oneline | grep needle'
    'git status --porcelain | grep -q M'
    'ls -l | grep -q needle'
    'git log --oneline -5'
    'jq -r .x f.json | grep -q needle'
)

matches_detector() {  # <line> -> 0 if flagged
    local line="$1"
    printf '%s\n' "$line" \
        | grep -E "(${WALKER})[^|]*\|[[:space:]]*(${EARLY})" \
        | grep -vE "$BOUNDED" >/dev/null 2>&1
}

test_detector_flags_every_dangerous_shape() {
    local bad=()
    for line in "${DANGEROUS[@]}"; do
        matches_detector "$line" || bad+=("$line")
    done
    if [ ${#bad[@]} -gt 0 ]; then
        echo "detector MISSED dangerous shapes:"
        printf '    %s\n' "${bad[@]}"
        return 1
    fi
}

test_detector_ignores_every_benign_shape() {
    local bad=()
    for line in "${BENIGN[@]}"; do
        if matches_detector "$line"; then bad+=("$line"); fi
    done
    if [ ${#bad[@]} -gt 0 ]; then
        echo "detector FALSE-POSITIVED on benign shapes:"
        printf '    %s\n' "${bad[@]}"
        return 1
    fi
}

test_bounded_exemption_admits_only_a_single_record() {
    # The exemption is the detector's soft underbelly: widened to any integer it
    # silently exempts every large bound.
    local bad=()
    for line in 'git log -5000 --oneline | grep -q x' \
                'git log -15 --oneline | grep -q x' \
                'git log -n 5000 --oneline | grep -q x'; do
        matches_detector "$line" || bad+=("MISSED: $line")
    done
    for line in 'git log -1 --oneline | grep -q x' \
                'git log -n 1 --oneline | grep -q x' \
                'git log --max-count=1 --oneline | grep -q x'; do
        if matches_detector "$line"; then bad+=("WRONGLY FLAGGED: $line"); fi
    done
    if [ ${#bad[@]} -gt 0 ]; then
        printf '    %s\n' "${bad[@]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------

build_big_fixture

echo "=== sigpipe-shape-guard ==="
for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    set +e
    out="$( set -e; "$fn" 2>&1 )"
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        echo "  PASS  $fn"
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
