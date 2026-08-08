#!/usr/bin/env bash
# Behavioural pin for hooks/pre-push-tests.sh — the self-bounding pre-push gate.
#
# WHAT THIS PINS
#
# The gate's whole claim is "a push cannot go out unverified". Before AGE-62 that
# claim was false in a way nothing could see: past the hook's declared timeout the
# platform CANCELS the hook and ALLOWS the tool call — measured 18 times across
# 1 906 transcripts, seventeen of them followed by the gated command executing,
# including two tag pushes and a PR. So the arms here are about the BOUND and the
# refusals, not about whether tests pass:
#
#   CEILING    a suite that overruns is BLOCKED, in wall-clock time under the
#              declared timeout — reds on a missing or late bound
#   FLOOR      a suite that passes is allowed, with no budget banner — reds on a
#              bound that always fires
#   BOUNDARY   just under the bound passes, just over blocks
#   VOCABULARY a breach and a red suite print different sentences (AGE-48)
#   FAIL-CLOSED an underivable budget, an absent bound tool and a non-positive
#              bound each block WITHOUT STARTING THE SUITE
#   PASS-THROUGH the two bypasses and a non-push command still cost nothing
#   LOG        every matched invocation is attributable, with the right verdict
#   DIFFERENTIAL this resolver and tests/gate-deadline.sh's agree, fixture for
#              fixture — the drift class killed rather than documented
#   CARRIED    the GIT_* scrub and the matcher behave exactly as before AGE-62
#
# ⚠ AN ALL-GREEN FIXTURE ASSERTS NOTHING. The pass-through arms are satisfied by a
# hook replaced with `exit 0`, so this file also runs the CEILING driver against
# exactly that stub and pins that it comes back 0 — the positive control that says
# the ceiling arm can fail at all. Nine arms assert exit 2.
#
# ⚠ THE TRAP THIS SUITE IS DESIGNED AGAINST: the gate resolves its repo root from
# the hook's cwd and then runs that repo's `make test`. A misconfigured fixture
# therefore resolves the AGENTICS root and runs the real suite — recursively,
# inside the pre-push gate. Every fixture is its own git repository under
# /private/tmp, `make_fixture` ABORTS THE WHOLE RUN if `rev-parse` from the
# fixture does not land inside it, and the arms additionally assert the `repo=`
# field the hook itself recorded. Two independent checks because the harness-side
# one cannot see a hook that resolves its root differently.
#
# ⚠ /private/tmp, never $TMPDIR: the latter is Spotlight-indexed on macOS and
# suites that create many small files there stall as `mds_stores` backlogs.
#
# ⚠ Fixture timings carry slack on purpose, and the DECLARED TIMEOUT is deliberately
# far larger than the bound. Declared 10s, margin 7s, bound 3s: the "just under"
# case sleeps 1s and the "just over" case sleeps 6s, and the ceiling arm's "blocked
# inside the declared timeout" assertion has 7s of headroom rather than 2s. Measured
# at declared 6s the arm passed at 4s — fine on an idle box, and one 3.5x load
# multiplier (which this repo has measured, twice) from a flake in the suite that
# gates every push. Slack in the ASSERTION, not just in the fixture.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
readonly REPO="$PWD"
readonly HOOK="$REPO/hooks/pre-push-tests.sh"
readonly INSTALLER="$REPO/hooks/install-pre-push-hook.sh"
readonly CHECKER="$REPO/tests/gate-deadline.sh"

passed=0
failed=0
failures=()

ok()  { echo "  PASS  $1"; passed=$((passed + 1)); }
bad() { echo "  FAIL  $1"; echo "        $2" >&2; failed=$((failed + 1)); failures+=("$1"); }

[ -f "$HOOK" ] || { echo "prepush-gate: no gate at $HOOK" >&2; exit 1; }

WORK="$(mktemp -d /private/tmp/agentics-prepush-gate.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A settings file in the REAL two-entry shape: the first declared timeout in the
# file is 5 and belongs to a different hook. A resolver reading position rather
# than command path bounds every suite at five seconds and blocks every push.
write_settings() {  # <path> <declared-seconds> [command-for-the-second-entry]
    local path="$1" declared="$2" command="${3:-bash $HOOK}"
    cat >"$path" <<JSON
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "python3 git-readonly-allow.py", "timeout": 5 } ] },
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "$command", "timeout": $declared } ] }
    ]
  }
}
JSON
}

# <name> <recipe> [--no-makefile] -> echoes the fixture path.
#
# The recipe's FIRST action is always the sentinel write, so "the suite never
# started" is observable as the sentinel's absence. Without that, "fail closed"
# is satisfied by a gate that runs the entire suite and only then refuses.
make_fixture() {
    # ⚠ `dir` gets its own `local`. All words of a `local` command are expanded
    # BEFORE the builtin assigns any of them, so `local name="$1" dir="$WORK/$name"`
    # reads an unset `name` — fatal under `set -u`, inside a command substitution,
    # which means every fixture path came back EMPTY and every arm then drove the
    # hook against the enclosing agentics checkout. Measured here, first run.
    local name="$1" recipe="${2:-true}" flag="${3:-}"
    local dir="$WORK/$name" resolved
    mkdir -p "$dir"
    git -C "$dir" init -q >/dev/null 2>&1
    if [ "$flag" != "--no-makefile" ]; then
        printf 'test:\n\t@pwd > sentinel\n\t@%s\n' "$recipe" >"$dir/Makefile"
    fi
    write_settings "$dir/settings.json" 10

    # THE ISOLATION GUARD. If a fixture is not its own repository, the gate
    # resolves the enclosing checkout and runs the real `make test` inside the
    # pre-push gate. Abort the run rather than let one arm discover it.
    resolved="$(cd "$dir" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
                    git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ "$resolved" != "$dir" ]; then
        echo "prepush-gate: FIXTURE NOT ISOLATED — '$dir' resolves to '${resolved:-<none>}'." >&2
        echo "  Refusing to run: the gate would execute that repository's suite." >&2
        exit 1
    fi
    printf '%s' "$dir"
}

# <command> -> the PreToolUse stdin JSON. jq rather than python3 purely for cost:
# measured on this machine, 100ms per python3 start against 10ms per jq, and this
# runs once per arm. jq is already the gate's own hard dependency.
payload_for() {
    printf '%s' "$1" | jq -Rs '{tool_input: {command: .}}'
}

# run_hook <fixture> <command> [VAR=VAL ...] -> sets RC, OUT, DUR
#
# Defaults come first so a caller's VAR=VAL overrides them: `env` keeps the last
# assignment of a repeated name.
run_hook() {
    local fixture="$1" command="$2"; shift 2
    local payload started

    # ⚠ THE SECOND ISOLATION GUARD, and it is not redundant. make_fixture's guard
    # cannot fire if make_fixture never returned a path: its first draft died in a
    # command substitution and handed every arm an EMPTY fixture, `cd ""` left the
    # cwd at the agentics checkout, and the gate resolved THIS repository. It was
    # saved only by an unresolvable budget refusing before `make test` started.
    # A caller that cannot name a fixture inside $WORK does not get to run the gate.
    case "$fixture" in
        "$WORK"/?*) [ -d "$fixture" ] || { echo "prepush-gate: fixture '$fixture' does not exist" >&2; exit 1; } ;;
        *) echo "prepush-gate: REFUSING to run the gate outside the fixture root." >&2
           echo "  fixture='$fixture' is not under $WORK — the gate would resolve, and run," >&2
           echo "  the enclosing repository's own suite." >&2
           exit 1 ;;
    esac

    payload="$(payload_for "$command")"
    started="$(date +%s)"
    OUT="$(cd "$fixture" && env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL \
            CLAUDE_SETTINGS_OVERRIDE="$fixture/settings.json" \
            PREPUSH_BOUND_MARGIN=7 \
            PREPUSH_VERDICT_LOG="$fixture/verdicts.log" \
            "$@" \
            bash "$HOOK" 2>&1 <<<"$payload")"
    RC=$?
    DUR=$(( $(date +%s) - started ))
}

verdicts() { awk '{print $2}' "$1/verdicts.log" 2>/dev/null; }
log_repo() { awk '{for (i = 1; i <= NF; i++) if ($i ~ /^repo=/) print substr($i, 6)}' "$1/verdicts.log" 2>/dev/null; }

readonly PUSH_CMD='git push origin main'

# ---------------------------------------------------------------------------
# CEILING — an overrunning suite is blocked, and blocked EARLY
# ---------------------------------------------------------------------------

ceiling="$(make_fixture ceiling 'sleep 60')"
run_hook "$ceiling" "$PUSH_CMD"

if [ "$RC" -eq 2 ]; then
    ok "CEILING: a suite that overruns the bound BLOCKS the push (exit 2)"
else
    bad "CEILING blocks" "expected rc=2, got rc=$RC in ${DUR}s: $OUT"
fi

if [ "$DUR" -lt 10 ]; then
    ok "CEILING: blocked in ${DUR}s — inside the 10s declared timeout, so the platform never cancels"
else
    bad "CEILING blocks early" "took ${DUR}s against a 3s bound and a 10s declared timeout; the bound is missing or late"
fi

case "$OUT" in
    *"PRE-PUSH BUDGET EXCEEDED"*) ok "CEILING: the block names itself a budget event" ;;
    *) bad "CEILING banner" "no budget banner in: $OUT" ;;
esac

case "$OUT" in
    *"against a 3s bound"*) ok "CEILING: the banner names the elapsed time and the bound" ;;
    *) bad "CEILING names elapsed and bound" "missing 'against a 3s bound' in: $OUT" ;;
esac

case "$OUT" in
    *"$ceiling/settings.json"*) ok "CEILING: the banner names the settings file the budget came from" ;;
    *) bad "CEILING names its source" "missing $ceiling/settings.json in: $OUT" ;;
esac

# The sibling refusal in tests/gate-deadline.sh is pinned not to advertise the
# bypass, for a reason that applies identically here: this message fires on
# ordinary machine load (3.5x wall clock measured from concurrent suites in other
# repos), and naming a bypass in a message that fires on load is how a bypass
# becomes habitual. The configuration refusals below DO name it, because those
# fire on a broken setup that re-running will never clear.
#
# ⚠ Scoped to the BANNER, not to the whole of stderr, and the difference is a real
# one rather than a convenience: the carried-across `running …` line advertises
# the variable on every single run, which is precisely why gate-deadline.sh's
# refusal does not repeat it. Asserting over all output tests that line instead.
CEILING_OUT="$OUT"
banner="$(printf '%s\n' "$CEILING_OUT" | awk '/PRE-PUSH BUDGET EXCEEDED/ {f = 1} f')"
if [ -z "$banner" ]; then
    bad "CEILING banner is extractable" "no banner to inspect — the arm below would be vacuous"
else
    case "$banner" in
        *SKIP_PREPUSH_TESTS=1*)
            bad "CEILING does not advertise the bypass" "the budget banner names SKIP_PREPUSH_TESTS, which normalises it" ;;
        *) ok "CEILING: the budget banner does not advertise the bypass" ;;
    esac
fi

if [ "$(log_repo "$ceiling")" = "$ceiling" ]; then
    ok "CEILING: the gate resolved the FIXTURE as its repo, not the enclosing checkout"
else
    bad "gate resolves the fixture root" "the hook recorded repo=$(log_repo "$ceiling"), expected $ceiling"
fi

# ---------------------------------------------------------------------------
# Positive control — the ceiling arm must be able to fail
# ---------------------------------------------------------------------------
#
# Every pass-through arm below is satisfied by a hook that is literally `exit 0`.
# Run the ceiling driver against exactly that and pin that it comes back 0: if
# this ever reports 2, the ceiling arms are passing on something other than the
# bound and every green in this file is suspect.

stub_hook="$WORK/stub-pre-push-tests.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$stub_hook"
stub_out="$(cd "$ceiling" && bash "$stub_hook" <<<"$(payload_for "$PUSH_CMD")" 2>&1)"
stub_rc=$?
if [ "$stub_rc" -eq 0 ]; then
    ok "control: a hook that only exits 0 passes the push through — so exit 2 above is load-bearing"
else
    bad "positive control" "the exit-0 stub returned rc=$stub_rc: $stub_out"
fi

# ---------------------------------------------------------------------------
# FLOOR — a passing suite is allowed, with no budget banner
# ---------------------------------------------------------------------------

floor="$(make_fixture floor 'true')"
run_hook "$floor" "$PUSH_CMD"

if [ "$RC" -eq 0 ]; then
    ok "FLOOR: a passing suite allows the push (exit 0)"
else
    bad "FLOOR allows" "expected rc=0, got rc=$RC: $OUT"
fi

case "$OUT" in
    *"PRE-PUSH BUDGET EXCEEDED"*) bad "FLOOR has no budget banner" "a passing run printed the budget banner: $OUT" ;;
    *) ok "FLOOR: no budget banner on a passing run — the bound does not always fire" ;;
esac

if [ -f "$floor/sentinel" ]; then
    ok "FLOOR: the suite actually ran (sentinel written)"
else
    bad "FLOOR runs the suite" "no sentinel at $floor/sentinel — the gate reported a pass without running anything"
fi

# ---------------------------------------------------------------------------
# BOUNDARY — just under the bound passes, just over blocks
# ---------------------------------------------------------------------------

under="$(make_fixture boundary-under 'sleep 1')"
run_hook "$under" "$PUSH_CMD"
if [ "$RC" -eq 0 ]; then
    ok "BOUNDARY: 1s under a 3s bound -> allowed"
else
    bad "BOUNDARY under passes" "expected rc=0, got rc=$RC in ${DUR}s: $OUT"
fi

over="$(make_fixture boundary-over 'sleep 6')"
run_hook "$over" "$PUSH_CMD"
if [ "$RC" -eq 2 ]; then
    ok "BOUNDARY: 6s over a 3s bound -> blocked"
else
    bad "BOUNDARY over blocks" "expected rc=2, got rc=$RC in ${DUR}s: $OUT"
fi

# The bound must track the DERIVED value, not a constant. ONE fixture, two
# margins, opposite verdicts: a 2s suite passes at margin 5 (bound 5s) and blocks
# at margin 9 (bound 1s). A hardcoded bound cannot produce both.
margin_fixture="$(make_fixture boundary-derived 'sleep 2')"
run_hook "$margin_fixture" "$PUSH_CMD" PREPUSH_BOUND_MARGIN=5
if [ "$RC" -eq 0 ]; then
    ok "BOUNDARY: the bound tracks the declared timeout less the margin (10-5=5s allows a 2s suite)"
else
    bad "bound is derived arithmetic" "expected rc=0 with margin=5 (bound 5s) on a 2s suite, got rc=$RC: $OUT"
fi

run_hook "$margin_fixture" "$PUSH_CMD" PREPUSH_BOUND_MARGIN=9
if [ "$RC" -eq 2 ]; then
    ok "BOUNDARY: the same 2s suite blocks at margin=9 (bound 1s) — the margin is read, not ignored"
else
    bad "margin is read" "expected rc=2 with margin=9 (bound 1s) on a 2s suite, got rc=$RC: $OUT"
fi

# ---------------------------------------------------------------------------
# VOCABULARY — a breach must not borrow a failure's words, or the reverse
# ---------------------------------------------------------------------------

redsuite="$(make_fixture red-suite 'exit 1')"
run_hook "$redsuite" "$PUSH_CMD"

if [ "$RC" -eq 2 ]; then
    ok "VOCABULARY: a genuinely failing suite blocks the push (exit 2)"
else
    bad "failing suite blocks" "expected rc=2, got rc=$RC: $OUT"
fi

case "$OUT" in
    *"TESTS FAILED"*) ok "VOCABULARY: a red suite says TESTS FAILED" ;;
    *) bad "red suite says TESTS FAILED" "missing in: $OUT" ;;
esac

case "$OUT" in
    *"PRE-PUSH BUDGET EXCEEDED"*)
        bad "a red suite is not a budget event" "a genuine failure printed the budget banner: $OUT" ;;
    *) ok "VOCABULARY: a red suite does NOT print the budget banner" ;;
esac

case "$OUT" in
    *"last 40 lines"*) ok "VOCABULARY: a red suite carries the tail of the run" ;;
    *) bad "red suite shows the tail" "missing the tail header in: $OUT" ;;
esac

# And the other direction, which is the one AGE-48 is about: the breach must not
# wear the failure's sentence.
case "$CEILING_OUT" in
    *"TESTS FAILED"*)
        bad "a breach is not a test failure" "the budget banner claimed TESTS FAILED: $CEILING_OUT" ;;
    *) ok "VOCABULARY: a budget breach never says TESTS FAILED" ;;
esac

# ---------------------------------------------------------------------------
# FAIL-CLOSED — and "fail closed" means the suite never started
# ---------------------------------------------------------------------------

unres="$(make_fixture unresolvable 'true')"
write_settings "$unres/settings.json" 900 "python3 some-other-hook.py"
run_hook "$unres" "$PUSH_CMD"

if [ "$RC" -eq 2 ]; then
    ok "FAIL-CLOSED: an underivable budget BLOCKS the push (exit 2), never guesses one"
else
    bad "underivable budget blocks" "expected rc=2, got rc=$RC: $OUT"
fi

if [ ! -f "$unres/sentinel" ]; then
    ok "FAIL-CLOSED: the suite was never started — the refusal precedes the run"
else
    bad "refusal precedes the run" "the sentinel exists: the gate ran the whole suite and only then refused, which is a gate that verified nothing"
fi

case "$OUT" in
    *"$unres/settings.json"*) ok "FAIL-CLOSED: the diagnosis names every settings path searched" ;;
    *) bad "diagnosis names paths" "no path list in: $OUT" ;;
esac

case "$OUT" in
    *SKIP_PREPUSH_TESTS=1*) ok "FAIL-CLOSED: a CONFIGURATION refusal does name the deliberate bypass" ;;
    *) bad "config refusal names the bypass" "a broken registration is not cleared by re-running; the operator needs the escape named: $OUT" ;;
esac

notool="$(make_fixture no-bound-tool 'true')"
run_hook "$notool" "$PUSH_CMD" PREPUSH_BOUND_SEARCH_PATH="$WORK/definitely-not-a-bin-dir"
if [ "$RC" -eq 2 ]; then
    ok "FAIL-CLOSED: no bounding tool BLOCKS the push rather than running unbounded"
else
    bad "no bound tool blocks" "expected rc=2, got rc=$RC: $OUT"
fi
if [ ! -f "$notool/sentinel" ]; then
    ok "FAIL-CLOSED: no bounding tool -> the suite was never started"
else
    bad "no-tool refusal precedes the run" "the sentinel exists; the gate ran unbounded and then refused"
fi
case "$OUT" in
    *"brew install coreutils"*) ok "FAIL-CLOSED: the no-tool refusal says how to fix it" ;;
    *) bad "no-tool refusal is actionable" "missing the install instruction in: $OUT" ;;
esac

# A zero or negative duration means NO TIMEOUT to GNU coreutils, so a margin that
# swallows the whole budget is a silent return to the fail-open. It must refuse.
zerobound="$(make_fixture zero-bound 'true')"
run_hook "$zerobound" "$PUSH_CMD" PREPUSH_BOUND_MARGIN=10
if [ "$RC" -eq 2 ]; then
    ok "FAIL-CLOSED: a non-positive bound BLOCKS — 'timeout 0' means no timeout at all"
else
    bad "non-positive bound blocks" "expected rc=2, got rc=$RC: $OUT"
fi
if [ ! -f "$zerobound/sentinel" ]; then
    ok "FAIL-CLOSED: a non-positive bound -> the suite was never started"
else
    bad "zero-bound refusal precedes the run" "the sentinel exists; the gate ran unbounded"
fi

# ---------------------------------------------------------------------------
# PASS-THROUGH — the bypasses and non-push commands still cost nothing
# ---------------------------------------------------------------------------

bypass="$(make_fixture bypass-skip 'sleep 60')"
run_hook "$bypass" "SKIP_PREPUSH_TESTS=1 $PUSH_CMD"
if [ "$RC" -eq 0 ] && [ ! -f "$bypass/sentinel" ]; then
    ok "PASS-THROUGH: SKIP_PREPUSH_TESTS=1 allows the push without running the suite"
else
    bad "SKIP_PREPUSH_TESTS bypass" "rc=$RC, sentinel present=$([ -f "$bypass/sentinel" ] && echo yes || echo no): $OUT"
fi

nover="$(make_fixture bypass-noverify 'sleep 60')"
run_hook "$nover" "$PUSH_CMD --no-verify"
if [ "$RC" -eq 0 ] && [ ! -f "$nover/sentinel" ]; then
    ok "PASS-THROUGH: --no-verify allows the push without running the suite"
else
    bad "--no-verify bypass" "rc=$RC, sentinel present=$([ -f "$nover/sentinel" ] && echo yes || echo no): $OUT"
fi

nonpush="$(make_fixture non-push 'sleep 60')"
run_hook "$nonpush" 'ls -la && git status --short'
if [ "$RC" -eq 0 ] && [ ! -f "$nonpush/sentinel" ]; then
    ok "PASS-THROUGH: a non-push command runs no suite"
else
    bad "non-push passes through" "rc=$RC, sentinel present=$([ -f "$nonpush/sentinel" ] && echo yes || echo no): $OUT"
fi

if [ ! -f "$nonpush/verdicts.log" ]; then
    ok "PASS-THROUGH: a non-push command logs NOTHING — the log stays readable"
else
    bad "non-push logs nothing" "a verdict was recorded for a non-push command: $(cat "$nonpush/verdicts.log")"
fi

notests="$(make_fixture no-test-command '' --no-makefile)"
run_hook "$notests" "$PUSH_CMD"
if [ "$RC" -eq 0 ]; then
    ok "PASS-THROUGH: a repo with no detectable test command is not gated"
else
    bad "no test command passes" "expected rc=0, got rc=$RC: $OUT"
fi

# ---------------------------------------------------------------------------
# LOG — every matched invocation is attributable
# ---------------------------------------------------------------------------

expect_verdict() {  # <fixture> <token> <label>
    local got
    got="$(verdicts "$1" | tr '\n' ' ' | sed 's/ *$//')"
    if [ "$got" = "$2" ]; then
        ok "LOG: $3 -> '$2'"
    else
        bad "LOG: $3 -> '$2'" "recorded '${got:-<nothing>}'"
    fi
}

expect_verdict "$floor"     "pass"              "a passing run"
expect_verdict "$redsuite"  "fail"              "a failing run"
expect_verdict "$unres"     "unresolved-budget" "an underivable budget"
expect_verdict "$notool"    "no-bound-tool"     "an absent bounding tool"
expect_verdict "$zerobound" "invalid-bound"     "a non-positive bound"
expect_verdict "$bypass"    "bypass"            "a deliberate bypass"
expect_verdict "$nover"     "bypass"            "a --no-verify bypass"
expect_verdict "$notests"   "no-test-command"   "a repo with no test command"

expect_verdict "$ceiling" "refused-budget" "a budget breach"

# A matched push from outside any repository. This is exactly the shape AGE-63
# predicts — prose or a heredoc body quoting a push — and logging it rather than
# exiting silently is what turns this log into evidence for that story.
norepo="$WORK/not-a-repo"
mkdir -p "$norepo"
norepo_out="$(cd "$norepo" && env CLAUDE_SETTINGS_OVERRIDE="$floor/settings.json" \
        PREPUSH_VERDICT_LOG="$norepo/verdicts.log" \
        bash "$HOOK" <<<"$(payload_for "$PUSH_CMD")" 2>&1)"
norepo_rc=$?
if [ "$norepo_rc" -eq 0 ] && [ "$(verdicts "$norepo")" = "no-repo" ]; then
    ok "LOG: a matched push outside any repository is recorded, not silently dropped"
else
    bad "LOG: no-repo" "rc=$norepo_rc, recorded '$(verdicts "$norepo")': $norepo_out"
fi

# One line per invocation is the log's entire contract, so a multi-line command —
# a heredoc body, a commit message quoting a push — must not become many lines.
multi="$(make_fixture multiline 'true')"
run_hook "$multi" "$(printf 'cat <<EOF\ngit push origin main\nEOF\n')"
if [ "$(wc -l <"$multi/verdicts.log" | tr -d ' ')" = "1" ]; then
    ok "LOG: a multi-line command is flattened to exactly one line"
else
    bad "LOG line count" "a multi-line command produced $(wc -l <"$multi/verdicts.log" | tr -d ' ') lines"
fi

# ---------------------------------------------------------------------------
# DIFFERENTIAL — this resolver and tests/gate-deadline.sh's must agree
# ---------------------------------------------------------------------------
#
# The two are logically the same function in two files, and the duplication is
# forced: the gate is installed standalone under ~/.claude/hooks/ and cannot
# source a repo file. Documenting that invites drift; running them side by side
# over the same fixtures kills the class.

diff_dir="$WORK/differential"; mkdir -p "$diff_dir"
write_settings "$diff_dir/real.json" 900
write_settings "$diff_dir/lowered.json" 600
write_settings "$diff_dir/absent.json" 900 "python3 some-other-hook.py"
printf '{ "hooks": { "PreToolUse": [ ' >"$diff_dir/malformed.json"

resolvers_agree() {  # <fixture-json> <label>
    local f="$1" label="$2" a b ra rb
    a="$(CLAUDE_SETTINGS_OVERRIDE="$f" bash "$HOOK" resolve 2>/dev/null)"; ra=$?
    b="$(CLAUDE_SETTINGS_OVERRIDE="$f" GATE_HOOK_MARKER=pre-push-tests.sh \
         bash "$CHECKER" resolve 2>/dev/null)"; rb=$?
    if [ "$a" = "$b" ] && [ "$ra" = "$rb" ]; then
        ok "DIFFERENTIAL: $label — both resolvers say '${a:-<unresolved>}' (rc $ra)"
    else
        bad "DIFFERENTIAL: $label" "gate said '$a' (rc $ra); gate-deadline said '$b' (rc $rb)"
    fi
}

resolvers_agree "$diff_dir/real.json"      "the real two-entry shape"
resolvers_agree "$diff_dir/lowered.json"   "a lowered declared timeout"
resolvers_agree "$diff_dir/absent.json"    "no matching registration"
resolvers_agree "$diff_dir/malformed.json" "a malformed settings file"

# Agreement is worthless if both resolvers agree on the WRONG answer, and the
# wrong answer here is a specific one: the first declared timeout in the file is
# 5, belonging to a different hook. Five seconds bounds every suite on the box.
first_timeout_trap="$(CLAUDE_SETTINGS_OVERRIDE="$diff_dir/real.json" bash "$HOOK" resolve 2>/dev/null)"
if [ "${first_timeout_trap%% *}" = "900" ]; then
    ok "DIFFERENTIAL: the gate matches its registration by command path (900s), not the file's first timeout (5s)"
else
    bad "resolver matches by command path" "expected 900, got '${first_timeout_trap:-<none>}' — a positional read yields 5 and blocks every push"
fi

# ---------------------------------------------------------------------------
# CARRIED ACROSS — the pre-AGE-62 behaviour that must not have moved
# ---------------------------------------------------------------------------

# The GIT_* scrub, behaviourally. A GIT_DIR pointing at a foreign repository is
# the 2026-07-16 corruption vector: inherited here it makes `rev-parse
# --show-toplevel` resolve the WRONG repo, and it outranks the `-C <tmpdir>`
# isolation of any real-git fixture the gated suite then runs. The gate must
# resolve the fixture regardless.
foreign="$(make_fixture foreign-repo 'true')"
scrub="$(make_fixture scrub-target 'true')"
run_hook "$scrub" "$PUSH_CMD" GIT_DIR="$foreign/.git" GIT_WORK_TREE="$foreign"
if [ "$(log_repo "$scrub")" = "$scrub" ]; then
    ok "CARRIED: an inherited GIT_DIR is scrubbed before any git call — the gate resolved the real cwd"
else
    bad "GIT_* scrub" "with GIT_DIR=$foreign/.git the gate resolved repo=$(log_repo "$scrub"), expected $scrub"
fi

# The source-order half. The behavioural arm above proves the scrub happens; this
# proves it happens BEFORE the first git call, which is the property that would
# survive a future refactor moving the resolution earlier.
scrub_line="$(grep -n '^unset GIT_DIR' "$HOOK" | head -1 | cut -d: -f1)"
firstgit_line="$(grep -nE '^[[:space:]]*[a-z_]*="?\$\(git |^[[:space:]]*git ' "$HOOK" | head -1 | cut -d: -f1)"
if [ -n "$scrub_line" ] && [ -n "$firstgit_line" ] && [ "$scrub_line" -lt "$firstgit_line" ]; then
    ok "CARRIED: the GIT_* unset (line $scrub_line) precedes the first git call (line $firstgit_line)"
else
    bad "scrub precedes git" "unset at '${scrub_line:-<none>}', first git call at '${firstgit_line:-<none>}'"
fi

# The matcher, unchanged — including the HTTPS-override form this repo pushes
# with every day. Probed against a repo with no test command, so a MATCH records
# `no-test-command` and a non-match records nothing at all: the matcher's verdict
# is observable without running any suite.
matcher_fixture="$(make_fixture matcher '' --no-makefile)"

matcher_case() {  # <command> <should-match> <label>
    local command="$1" want="$2" label="$3" got=no
    : >"$matcher_fixture/verdicts.log"
    run_hook "$matcher_fixture" "$command"
    [ -s "$matcher_fixture/verdicts.log" ] && got=yes
    if [ "$got" = "$want" ]; then
        ok "CARRIED matcher: $label -> match=$want"
    else
        bad "CARRIED matcher: $label" "expected match=$want, got match=$got for: $command"
    fi
}

matcher_case 'git push origin main' yes 'plain push'
matcher_case 'git -c url."https://github.com/".insteadOf="git@github.com:" push origin b' yes 'https override form'
matcher_case 'git -C /tmp/x push origin b' yes 'dash-C global'
matcher_case 'git status --short' no 'git status'
matcher_case 'echo pushing' no 'the word pushing'
matcher_case 'gitpush origin main' no 'gitpush is not git push'

# ---------------------------------------------------------------------------
# THE INSTALLER — exercised against a fixture destination, never $HOME
# ---------------------------------------------------------------------------
#
# `make install-hooks` writes outside the repository, so it is NOT part of
# `make test`. PREPUSH_HOOK_DEST is what lets its behaviour be pinned anyway.

dest_dir="$WORK/fakehome/.claude/hooks"; mkdir -p "$dest_dir"
dest="$dest_dir/pre-push-tests.sh"

if PREPUSH_HOOK_DEST="$dest" bash "$INSTALLER" check >/dev/null 2>&1; then
    bad "installer: check reports a missing install" "check passed with nothing installed"
else
    ok "installer: check FAILS when the gate is not installed at all"
fi

install_out="$(PREPUSH_HOOK_DEST="$dest" bash "$INSTALLER" install 2>&1)"
if [ $? -eq 0 ] && cmp -s "$HOOK" "$dest"; then
    ok "installer: install writes a byte-identical copy of the repo's gate"
else
    bad "installer installs" "$install_out"
fi

if PREPUSH_HOOK_DEST="$dest" bash "$INSTALLER" check >/dev/null 2>&1; then
    ok "installer: check passes once the installed copy matches"
else
    bad "installer check after install" "check still reports drift"
fi

printf '\n# drift\n' >>"$dest"
if PREPUSH_HOOK_DEST="$dest" bash "$INSTALLER" check >/dev/null 2>&1; then
    bad "installer detects drift" "an edited installed copy still reported a match"
else
    ok "installer: check DETECTS drift in the installed copy"
fi

install_out="$(PREPUSH_HOOK_DEST="$dest" bash "$INSTALLER" install 2>&1)"
if printf '%s' "$install_out" | grep -q 'backed up the previous gate' \
   && ls "$dest".bak.* >/dev/null 2>&1; then
    ok "installer: a differing installed copy is backed up before it is overwritten"
else
    bad "installer backs up" "no backup was made: $install_out"
fi

# ---------------------------------------------------------------------------

echo ""
echo "prepush-gate: ${passed} passed, ${failed} failed"
if [ "$failed" -ne 0 ]; then
    for f in "${failures[@]}"; do echo "  failed: $f" >&2; done
    exit 1
fi
exit 0
