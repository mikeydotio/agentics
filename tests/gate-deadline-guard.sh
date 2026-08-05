#!/usr/bin/env bash
# Behavioural pin for tests/gate-deadline.sh — the pre-push budget self-deadline.
#
# WHAT THIS PINS, AND WHAT IT DELIBERATELY DOES NOT
#
# Pinned (owned by this repo, therefore testable here):
#   - the deadline is INERT unless the suite is a descendant of the pre-push hook;
#   - the budget is READ from the hook's own declared timeout, matched by command path,
#     never by position and never hardcoded;
#   - past budget the suite REFUSES, with a distinct exit status;
#   - the refusal explains itself as a budget event, not a test failure.
#
# NOT pinned, and it cannot be from inside this repo: that the derived budget is
# actually below the platform's cancellation point. That is a property of
# ~/.claude/settings.json, which this repo does not own. Lowering the hook's timeout
# below our margin makes the guard inert; nothing here can detect that. It is disclosed
# in gate-deadline.sh's header rather than falsely guarded — the same call
# bounded-capture-guard.sh makes in its "Deliberately not covered" section.
#
# HOW ACTIVATION IS SIMULATED
#
# The checker matches an ancestor's argv against GATE_HOOK_MARKER. A fixture script
# named for a per-run sentinel that invokes the checker IS, to the checker, the real
# thing — no mocking of ps, no injected environment.
#
# ⚠ EVERY case here must pin its OWN marker, and the reason is not hypothetical: this
# suite runs inside `make test`, and `make test` runs as the pre-push gate, so the
# ambient process tree ALREADY contains a real `pre-push-tests.sh` ancestor. A first
# draft used the real marker name and asserted the inert case by assuming no such
# ancestor existed. That held when run by hand and FAILED the moment the suite ran as
# the gate — turning `make test` red on every push and blocking it. Measured, not
# reasoned: the hook blocked a real command with "elapsed 4s of a -99099s budget".
#
# So the inert case pins a sentinel that cannot match anything, and the activation
# cases pin a sentinel matched only by their own fixture. The guard is then hermetic in
# both directions: identical results whether or not it is itself running under the gate.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
readonly REPO="$PWD"
readonly CHECKER="$REPO/tests/gate-deadline.sh"

passed=0
failed=0
failures=()

ok()   { echo "  PASS  $1"; passed=$((passed + 1)); }
bad()  { echo "  FAIL  $1"; echo "        $2" >&2; failed=$((failed + 1)); failures+=("$1"); }

WORK="$(mktemp -d /private/tmp/agentics-gate-deadline.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# The real shape: TWO PreToolUse entries, and the FIRST timeout in the file is 5 —
# belonging to a different hook. A resolver reading position rather than command path
# derives a five-second budget and blocks every push.
cat >"$WORK/settings-real-shape.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 \"$HOME/.claude/hooks/git-readonly-allow.py\"", "timeout": 5 }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"$HOME/.claude/hooks/pre-push-tests.sh\"", "timeout": 900 }
        ]
      }
    ]
  }
}
JSON

# Seat 2's mutation: the same file with the budget lowered. Proves the value is read.
sed 's/"timeout": 900/"timeout": 600/' "$WORK/settings-real-shape.json" \
    >"$WORK/settings-lowered.json"

# A settings file that declares no pre-push hook at all.
cat >"$WORK/settings-absent.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
  { "type": "command", "command": "python3 other.py", "timeout": 5 } ] } ] } }
JSON

# Markers. FIXTURE_MARKER is matched only by the fixtures below; NEVER_MARKER cannot
# appear in any process's argv, so it makes "no hook ancestor" true by construction
# rather than by assuming anything about the ambient process tree.
readonly FIXTURE_MARKER="age36-fixture-hook-$$.sh"
readonly NEVER_MARKER="age36-no-such-ancestor-sentinel-$$"

# The marker identifies the hook for BOTH purposes — which ancestor arms the deadline,
# and which entry in the settings file declares its timeout. So an activation fixture
# needs a settings file whose command names the fixture, or the resolver correctly
# reports the budget as underivable. Same two-entry shape as the real file, first
# timeout 5.
cat >"$WORK/settings-fixture.json" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 git-readonly-allow.py", "timeout": 5 }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash $FIXTURE_MARKER", "timeout": 900 }
        ]
      }
    ]
  }
}
JSON

# A fixture that IS the hook, as far as ancestry is concerned.
make_fake_hook() {
    local path="$WORK/$1/$FIXTURE_MARKER"
    mkdir -p "$WORK/$1"
    # NOT `exec`: exec REPLACES this process, so the argv the ancestry walk matches on
    # would vanish and the checker would correctly conclude it is not under a hook.
    # (That bug made the first draft of this guard report a green "inert" for every
    # activation case — the fixture, not the checker, was wrong.)
    cat >"$path" <<EOF
#!/usr/bin/env bash
bash "$CHECKER" check "\${1:-fixture-target}"
EOF
    chmod +x "$path"
    printf '%s' "$path"
}

run_under_hook() {  # <settings> <margin> [label] -> sets RC / OUT
    local settings="$1" margin="$2" label="${3:-test-fixture}" hook
    hook="$(make_fake_hook "hook$RANDOM")"
    OUT="$(CLAUDE_SETTINGS_OVERRIDE="$settings" \
           GATE_DEADLINE_MARGIN="$margin" \
           GATE_DEADLINE_DIR="$WORK/crumbs" \
           GATE_HOOK_MARKER="$FIXTURE_MARKER" \
           bash "$hook" "$label" 2>&1)"
    RC=$?
}

# ---------------------------------------------------------------------------
# 1. Inert unless under the hook — the property that makes this safe to ship
# ---------------------------------------------------------------------------

# The margin is absurd on purpose: if activation were to happen, the budget would be
# hugely negative and the check would certainly refuse. Passing therefore proves
# inertness rather than merely proving the budget was not yet exhausted.
OUT="$(CLAUDE_SETTINGS_OVERRIDE="$WORK/settings-real-shape.json" \
       GATE_DEADLINE_MARGIN=99999 \
       GATE_DEADLINE_DIR="$WORK/crumbs" \
       GATE_HOOK_MARKER="$NEVER_MARKER" \
       bash "$CHECKER" check plain-run 2>&1)"; RC=$?
if [ "$RC" -eq 0 ]; then
    ok "no hook ancestor -> inert, even with a margin that would refuse everything"
else
    bad "no hook ancestor -> inert" "expected rc=0, got rc=$RC: $OUT"
fi

# The inert case must stay inert while this suite is itself running as the gate. Under
# the real hook the ambient tree DOES contain a pre-push-tests.sh ancestor, so pin that
# the real marker is not what the case above relied on.
if grep -q 'GATE_HOOK_MARKER="\$NEVER_MARKER"' "$0"; then
    ok "the inert case pins a sentinel marker, so it holds when run as the gate itself"
else
    bad "inert case is hermetic" "it relies on the ambient process tree; running as the gate would red it and block every push"
fi

# ---------------------------------------------------------------------------
# 2. The command-path trap: the first timeout in the file is 5, not 900
# ---------------------------------------------------------------------------

resolved="$(CLAUDE_SETTINGS_OVERRIDE="$WORK/settings-real-shape.json" \
            bash "$CHECKER" resolve 2>/dev/null)"
if [ "${resolved%% *}" = "900" ]; then
    ok "resolver matches the hook by command path (900s), not the file's first timeout (5s)"
else
    bad "resolver matches by command path" "expected 900, got '${resolved:-<none>}' — a positional read yields 5 and blocks every push"
fi

# ---------------------------------------------------------------------------
# 3. The budget is READ, not copied — Seat 2's timeout:600 mutation
# ---------------------------------------------------------------------------

resolved_low="$(CLAUDE_SETTINGS_OVERRIDE="$WORK/settings-lowered.json" \
                bash "$CHECKER" resolve 2>/dev/null)"
if [ "${resolved_low%% *}" = "600" ]; then
    ok "lowering the hook's declared timeout changes the derived budget (900 -> 600)"
else
    bad "budget tracks the declared timeout" "expected 600, got '${resolved_low:-<none>}' — a hardcoded constant would still report 900"
fi

# ---------------------------------------------------------------------------
# 4. Past budget -> refuse, with a status distinct from a test failure
# ---------------------------------------------------------------------------

# margin == timeout makes the budget 0, so any elapsed time is over budget.
run_under_hook "$WORK/settings-fixture.json" 900 "test-over-budget"
if [ "$RC" -eq 3 ]; then
    ok "over budget -> refuses with exit 3 (not 1=test failure, not 2=hook block)"
else
    bad "over budget refuses with exit 3" "got rc=$RC: $OUT"
fi

case "$OUT" in
    *"BUDGET, NOT CORRECTNESS"*) ok "the refusal leads by distinguishing budget from correctness" ;;
    *) bad "refusal explains itself" "diagnosis did not lead with BUDGET, NOT CORRECTNESS: $OUT" ;;
esac

# ---------------------------------------------------------------------------
# 5. Anti-normalisation: the refusal must NOT advertise the bypass
# ---------------------------------------------------------------------------
#
# The council's reason, recorded so a future reader does not "helpfully" add it back:
# naming the bypass in a message that fires on ordinary machine load is how a bypass
# becomes habitual, and a habit does not stay scoped to timeouts — it erodes the gate
# for genuine test failures too. The hook already advertises the variable itself on
# every run (pre-push-tests.sh:62), so repeating it here buys nothing and costs the
# distinction between a load bypass and a deliberate docs-only one.

case "$OUT" in
    *SKIP_PREPUSH_TESTS*)
        bad "refusal does not advertise the bypass" "the diagnosis names SKIP_PREPUSH_TESTS, which normalises it" ;;
    *)
        ok "refusal does not advertise SKIP_PREPUSH_TESTS" ;;
esac

case "$OUT" in
    *"cannot be raised"*) ok "refusal states the budget cannot be raised (the forcing function)" ;;
    *) bad "refusal states the budget cannot be raised" "missing: the only remedy is a faster suite" ;;
esac

# ---------------------------------------------------------------------------
# 6. Inside budget -> proceed
# ---------------------------------------------------------------------------

run_under_hook "$WORK/settings-fixture.json" 180 "test-inside-budget"
if [ "$RC" -eq 0 ]; then
    ok "inside budget -> proceeds"
else
    bad "inside budget proceeds" "expected rc=0, got rc=$RC: $OUT"
fi

# ---------------------------------------------------------------------------
# 7. Under the hook but the budget is unknowable -> refuse, never guess
# ---------------------------------------------------------------------------

run_under_hook "$WORK/settings-absent.json" 180 "test-unresolvable"
if [ "$RC" -eq 3 ]; then
    ok "under the hook with no declared timeout -> refuses rather than guessing a budget"
else
    bad "unresolvable budget refuses" "expected rc=3, got rc=$RC: $OUT"
fi
case "$OUT" in
    *"Paths searched"*) ok "the unresolvable diagnosis names every path searched" ;;
    *) bad "unresolvable diagnosis names paths" "no path list in: $OUT" ;;
esac

# ---------------------------------------------------------------------------
# 8. etime parsing across ps's formats
# ---------------------------------------------------------------------------
# Parsed wrong, a budget comparison silently reads minutes as seconds. `10#` guards
# against 08/09 being read as invalid octal — a classic that fires only in September.

etime_case() {  # <raw> <expected-seconds>
    local raw="$1" want="$2" got
    got="$(GATE_ETIME_RAW="$raw" bash -c '
        set -euo pipefail
        raw="$GATE_ETIME_RAW"; days=0; hh=0
        case "$raw" in *-*) days="${raw%%-*}"; rest="${raw#*-}" ;; *) rest="$raw" ;; esac
        case "$rest" in *:*:*) hh="${rest%%:*}"; rest="${rest#*:}" ;; esac
        mm="${rest%%:*}"; ss="${rest#*:}"
        printf "%s" "$(( 10#$days * 86400 + 10#$hh * 3600 + 10#$mm * 60 + 10#$ss ))"
    ' 2>/dev/null)"
    if [ "$got" = "$want" ]; then
        ok "etime '$raw' -> ${want}s"
    else
        bad "etime '$raw' -> ${want}s" "got '${got:-<error>}'"
    fi
}
etime_case "10:29"      629
etime_case "01:10:29"   4229
etime_case "1-01:10:29" 90629
etime_case "00:08"      8
etime_case "00:09"      9

# ---------------------------------------------------------------------------
# 9. The breadcrumb is repo-local, never a fixed /tmp path (AGE-34)
# ---------------------------------------------------------------------------

if grep -qE '/tmp/[a-z-]*gate-deadline|GATE_DEADLINE_DIR:-/tmp' "$CHECKER"; then
    bad "breadcrumb is repo-local" "the checker names a fixed /tmp path — machine-global state shared with every concurrent run (AGE-34, AGE-56, AGE-57)"
else
    ok "breadcrumb defaults to a repo-local path, not a fixed /tmp path"
fi

if [ -s "$WORK/crumbs/log" ]; then
    ok "the checker records a breadcrumb so an inert run is auditable"
else
    bad "breadcrumb is written" "no crumbs at $WORK/crumbs/log"
fi

# ---------------------------------------------------------------------------
# 10. No `timeout` call site was introduced (bounded-capture-guard's domain)
# ---------------------------------------------------------------------------
# The bound is arithmetic on purpose: a `timeout` here would need a REGISTRY entry, and
# the easy alternative (background pid + kill -TERM) is deliberately UNCOVERED by that
# guard, so the path of least resistance would silently evade it.

# The alternation is built from a variable rather than written literally: spelled out,
# `|gtimeout)` is itself a command-position match for bounded-capture-guard.sh, so this
# assertion would add a phantom entry to the very census it exists to keep at three.
bound_word='timeout'
if grep -nE "(^|[^[:alnum:]_])(${bound_word}|g${bound_word})[[:space:]]+[0-9]" "$CHECKER" >/dev/null 2>&1; then
    bad "no bounded-command call site" "gate-deadline.sh introduced a timeout call site; it must be registered in bounded-capture-guard.sh's REGISTRY"
else
    ok "the bound is arithmetic — no timeout/gtimeout call site introduced"
fi

# ---------------------------------------------------------------------------

echo ""
echo "gate-deadline-guard: ${passed} passed, ${failed} failed"
if [ "$failed" -ne 0 ]; then
    for f in "${failures[@]}"; do echo "  failed: $f" >&2; done
    exit 1
fi
exit 0
