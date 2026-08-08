#!/usr/bin/env bash
# PreToolUse(Bash) hook — enforce "tests pass locally before pushing".
#
# Policy (global, all projects): tests do NOT run in GitHub Actions; they run
# locally and must pass before any push. This hook gates Claude's `git push`
# calls: it detects the project's test command, runs it, and BLOCKS the push
# (exit 2) if the tests fail. Non-push Bash commands pass through untouched.
#
# Deliberate bypass (e.g. a docs-only push): include `SKIP_PREPUSH_TESTS=1` or
# `--no-verify` anywhere in the command.
#
# Exit codes: 0 = allow the push; 2 = block it (stderr is fed back to Claude).
#
# ---------------------------------------------------------------------------
# WHY THIS FILE LIVES IN A REPOSITORY (AGE-62)
# ---------------------------------------------------------------------------
#
# This is safety-critical code that spent months as an ORPHAN GLOBAL FILE with no
# owner, no version and no test. That is why it could fail open undetected. The
# installed copy at `~/.claude/hooks/pre-push-tests.sh` is now a COPY of this
# file: `make install-hooks` writes it, `make check-hooks` reports drift, and
# `tests/prepush-gate.sh` is what makes any claim here checkable.
#
# ---------------------------------------------------------------------------
# WHY THE GATE BOUNDS ITSELF
# ---------------------------------------------------------------------------
#
# The registration in `~/.claude/settings.json` declares a `timeout` (observed
# 900s, 2026-08-05). When the suite exceeds it, Claude Code CANCELS the hook and
# **allows the tool call anyway** — no verdict, no message, nothing in the
# session that says so. Measured twice, independently: 12/12 in AGE-36, and 18
# cancellations across 1 906 transcripts re-mined for AGE-62, every one at
# `timeoutMs: 900000`, seventeen followed by the gated command executing — tag
# pushes `v3.0.0` and `v2.39.1`, branch pushes, and a PR creation, all released
# with no test verdict at all. Spread across every project on the machine
# (agentics 12, storyhook 5, scad-caliper 1).
#
# The origin is not the suite's size. It is that the gate DELEGATED ITS OWN
# LIVENESS to a platform whose cancellation semantics fail open: it ran an
# unbounded command under a bound it neither knew nor enforced. So the hook now
# derives its own declared timeout, reserves a margin, runs the suite under that
# bound, and on breach exits 2 — a real block — before the platform ever reaches
# its cancellation point.
#
# Layering, for a repo that also ships `tests/gate-deadline.sh` (agentics does):
#
#   720s  gate-deadline.sh refuses BETWEEN make targets (margin 180s) -> exit 3,
#         which this hook turns into a block, with the informative banner
#   840s  this hook's own bound (margin 60s) — EVERY repo, and the backstop for
#         a single target that overruns the between-target check -> exit 2
#   900s  platform cancellation — never reached
#
# ---------------------------------------------------------------------------
# WHY THE BUDGET IS DERIVED AND NEVER COPIED
# ---------------------------------------------------------------------------
#
# Hardcoding 840 here would be a second copy of a value living in a file this
# script does not own: change that file to 600 and the bound is silently wrong,
# which is the very defect class this exists to close. So the hook READS the
# declared timeout of its OWN registration, matched by command path.
#
# ⚠ TRAP, and it is not hypothetical: settings.json carries TWO PreToolUse
# entries and the FIRST `timeout` in the file is **5** (git-readonly-allow.py),
# not 900. A resolver that takes the first timeout it finds bounds the suite at
# five seconds and blocks every push. Matching is therefore on the hook's own
# command path — `basename "$0"`, so a rename that updates the registration
# keeps working. `tests/gate-deadline.sh` pins the identical trap for its own
# resolver, and `tests/prepush-gate.sh` runs the two resolvers DIFFERENTIALLY
# over shared fixtures, which kills the drift class rather than documenting it.
#
# ---------------------------------------------------------------------------
# WHY A REFUSAL IS NOT A SKIP
# ---------------------------------------------------------------------------
#
# An underivable budget, a missing bound tool and a non-positive bound all exit
# 2 WITHOUT STARTING THE SUITE. "Fail closed" that runs the whole suite first
# and then refuses is satisfiable by a gate that verified nothing, so
# tests/prepush-gate.sh asserts a sentinel the fixture suite would have written
# is ABSENT, not merely that the exit status was 2.
#
# ⚠ `timeout 0 cmd` means NO TIMEOUT in GNU coreutils — a non-positive bound is
# a silent return to the fail-open this file exists to end, so it refuses.
#
# ---------------------------------------------------------------------------
# WHY A BREACH DOES NOT WEAR A FAILURE'S VOCABULARY (AGE-48)
# ---------------------------------------------------------------------------
#
# A budget breach and a red suite are different events with different remedies,
# so they print different sentences: the breach leads with "PRE-PUSH BUDGET
# EXCEEDED" and never says "TESTS FAILED". Both are pinned separately.
#
# The breach banner also does NOT name `SKIP_PREPUSH_TESTS`, deliberately, and
# the split is principled rather than stylistic: a breach fires on ORDINARY
# MACHINE LOAD (measured: 3.5x wall-clock from concurrent suites in other
# repos), and naming the bypass in a message that fires on load is how a bypass
# becomes habitual — the same call `tests/gate-deadline-guard.sh` pins for the
# sibling refusal. The configuration refusals DO name it, because those fire on
# a broken machine setup where the operator genuinely needs an escape and no
# amount of re-running will clear it. The `running …` line below advertises the
# variable on every run in any case.
#
# ---------------------------------------------------------------------------
# THE VERDICT LOG
# ---------------------------------------------------------------------------
#
# A PreToolUse hook that exits 0 has its stderr discarded, and a cancelled one
# never returns the exit 2 that blocks — so this gate was invisible from inside
# a session in BOTH directions, and AGE-32 wrongly concluded from a missing
# `running …` line that the hook was not firing. It was firing. One append-only
# line per MATCHED invocation makes the next breach attributable without mining
# 1 900 transcripts, and doubles as free evidence for AGE-63 (the matcher greps
# the whole command string, so prose quoting a push costs a suite run).
#
# ---------------------------------------------------------------------------
# WHAT WAS DELIBERATELY NOT CHANGED
# ---------------------------------------------------------------------------
#
# The matcher, the GIT_* scrub, the test-command detection and the bypasses are
# carried across from the pre-AGE-62 global file UNCHANGED — including the
# matcher's known over-firing (AGE-63), the double suite run per push (AGE-64)
# and the attestation inversion (AGE-65). All three are filed and stay filed;
# widening this change to them would make the bound impossible to attribute.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Seconds reserved between this hook's bound and the platform's cancellation
# point: enough for the breach banner, the log write and the hook's own exit to
# be observed. Overridable for tests and for the end-to-end verification, which
# drives the bound down to a second rather than manufacturing a 14-minute run.
PREPUSH_BOUND_MARGIN="${PREPUSH_BOUND_MARGIN:-60}"

# Seconds granted to a bounded suite that ignores SIGTERM before it is killed
# outright. Without it a suite that traps TERM hangs past the bound and the
# platform's fail-open is back.
PREPUSH_BOUND_KILL_AFTER="${PREPUSH_BOUND_KILL_AFTER:-10}"

# How this hook recognises its own registration in a settings file. Derived from
# the file's own name, so a rename that updates the registration still resolves.
PREPUSH_HOOK_MARKER="${PREPUSH_HOOK_MARKER:-$(basename "$0")}"

# Where the bounding tool is looked for, as a PATH-shaped list. The two Homebrew
# prefixes are appended because a hook does not reliably inherit a login PATH:
# stock macOS ships no `timeout` at all and coreutils installs `gtimeout`.
#
# Overridable so the "no bounding tool" refusal is REACHABLE UNDER TEST. On a
# developer machine that has coreutils, that branch is otherwise unreachable and
# would ship unexercised — the shape of every fail-closed path that turns out not
# to fail closed. It is a search path, not a result: a wrong value makes the gate
# refuse, never pass.
PREPUSH_BOUND_SEARCH_PATH="${PREPUSH_BOUND_SEARCH_PATH:-$PATH:/opt/homebrew/bin:/usr/local/bin}"

# Append-only verdict log. Under $HOME rather than a fixed path in /tmp: a fixed
# /tmp path is machine-global state shared with every other project and every
# concurrent run, which is AGE-34's defect class (AGE-56 and AGE-57 still open on
# it). This hook is the file's only writer and only ever appends.
PREPUSH_VERDICT_LOG="${PREPUSH_VERDICT_LOG:-$HOME/.claude/pre-push-verdicts.log}"

# ---------------------------------------------------------------------------
# Budget resolution
# ---------------------------------------------------------------------------

# Settings files searched, in Claude Code's precedence order. Every path tried is
# named in the diagnosis when resolution fails, so an underivable budget is
# debuggable rather than mysterious.
#
# CLAUDE_SETTINGS_OVERRIDE, when set, REPLACES the chain rather than being
# prepended to it. That is what "override" should mean, and it is also what makes
# the suite hermetic: a prepended override still falls through to the developer's
# real ~/.claude/settings.json when the fixture declares no hook, so the
# unresolvable branch could never be exercised and every run would silently read
# live machine config. tests/gate-deadline.sh made the identical call.
prepush_settings_candidates() {
    if [ -n "${CLAUDE_SETTINGS_OVERRIDE:-}" ]; then
        printf '%s\n' "$CLAUDE_SETTINGS_OVERRIDE"
        return 0
    fi
    printf '%s\n' \
        "$PWD/.claude/settings.local.json" \
        "$PWD/.claude/settings.json" \
        "${HOME}/.claude/settings.json" \
        "/Library/Application Support/ClaudeCode/managed-settings.json"
}

# Resolve this hook's own declared timeout (seconds) from the precedence chain.
# Echoes "<seconds> <path>" on success; returns 1 when nothing declares it.
#
# Kept deliberately identical in behaviour to gate_resolve_timeout() in
# tests/gate-deadline.sh. The duplication is FORCED — this file is installed
# standalone under ~/.claude/hooks/ and cannot source a repo file — so the
# honest answer is the differential arm in tests/prepush-gate.sh, which feeds
# both resolvers the same fixtures and asserts identical output.
prepush_resolve_timeout() {
    local candidate seconds
    while IFS= read -r candidate; do
        [ -z "$candidate" ] && continue
        [ -f "$candidate" ] || continue
        seconds="$(python3 -c '
import json, sys

marker = sys.argv[2]
try:
    with open(sys.argv[1]) as fh:
        settings = json.load(fh)
except (OSError, ValueError):
    sys.exit(1)

for entry in (settings.get("hooks") or {}).get("PreToolUse") or []:
    for hook in entry.get("hooks") or []:
        # Match the hook by its command path, not by position: the FIRST timeout
        # in this file belongs to a different hook and is 5 seconds.
        if marker in str(hook.get("command", "")):
            # Named `declared`, not `timeout`: tests/bounded-capture-guard.sh
            # scans this file as SHELL, and a Python local called `timeout` sits
            # at what that detector reads as a shell command position. It is not
            # a bounded command, so the honest fix is to not look like one rather
            # than to exempt the file.
            declared = hook.get("timeout")
            if isinstance(declared, (int, float)) and declared > 0:
                print(int(declared))
                sys.exit(0)
sys.exit(1)
' "$candidate" "$PREPUSH_HOOK_MARKER" 2>/dev/null || true)"
        if [ -n "$seconds" ]; then
            printf '%s %s' "$seconds" "$candidate"
            return 0
        fi
    done < <(prepush_settings_candidates)
    return 1
}

# Resolve the bounding tool. Echoes "<name> <dir>"; returns 1 when neither is
# available anywhere on the search path.
#
# ⚠ An explicit directory scan rather than `command -v`, for one reason: the
# search path has to be REPLACEABLE so the refusal branch can be exercised on a
# machine that does have coreutils. Lookup order is otherwise PATH's own — first
# directory wins.
#
# The directory is prepended to PATH and the tool is then invoked by its LITERAL
# NAME rather than through this variable; the reason is at the invocation itself.
prepush_resolve_bound_tool() {
    local dir cand
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        for cand in timeout gtimeout; do
            if [ -x "$dir/$cand" ]; then
                printf '%s %s' "$cand" "$dir"
                return 0
            fi
        done
    done < <(printf '%s' "$PREPUSH_BOUND_SEARCH_PATH" | tr ':' '\n')
    return 1
}

# ---------------------------------------------------------------------------
# The verdict log
# ---------------------------------------------------------------------------

# verdict <token> <elapsed> <bound> <declared>
#
# Never fails the hook: a gate that blocks a push because it could not write its
# own audit line would be worse than the invisibility it exists to cure.
prepush_verdict() {
    local token="$1" elapsed="$2" bound="$3" declared="$4" dir snippet
    dir="$(dirname "$PREPUSH_VERDICT_LOG")"
    mkdir -p "$dir" 2>/dev/null || return 0
    # One line per invocation is the whole contract, so a multi-line command
    # (a heredoc body, a commit message) is flattened before it is recorded.
    snippet="$(printf '%s' "${cmd:-}" | tr '\n\t' '  ' | cut -c1-60)"
    printf '%s %s repo=%s elapsed=%ss bound=%ss timeout=%ss cmd=%s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$token" "${root:-<none>}" \
        "$elapsed" "$bound" "$declared" "$snippet" \
        >>"$PREPUSH_VERDICT_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Diagnostic entry point
# ---------------------------------------------------------------------------
#
# `pre-push-tests.sh resolve` prints "<seconds> <path>" and reads no stdin. This
# is what lets tests/prepush-gate.sh run this resolver and gate-deadline.sh's
# side by side over identical fixtures. The platform invokes the hook with no
# arguments, so the gate path below is untouched by it.
if [ "${1:-}" = "resolve" ]; then
    prepush_resolve_timeout || { echo "unresolved" >&2; exit 1; }
    exit 0
fi

# ---------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# Is this a `git push`? Match a git invocation whose subcommand is `push`,
# allowing leading `-c k=v` / `-C dir` globals (covers the HTTPS-override form
# `git -c url."https://...".insteadOf="git@github.com:" push origin <branch>`).
#
# ⚠ Ordered BEFORE the bypass check, where the pre-AGE-62 file had it after. The
# outcome is identical either way — both paths exit 0 — but it keeps the verdict
# log to matched invocations only, which is what makes the log small enough to
# read and useful as AGE-63 evidence.
if ! printf '%s' "$cmd" \
    | grep -Eq '(^|[^[:alnum:]_])git( +-[cC] +[^ ]+)* +push([^[:alnum:]_]|$)'; then
    exit 0
fi

# Explicit bypasses.
case "$cmd" in
    *SKIP_PREPUSH_TESTS=1*|*--no-verify*) prepush_verdict bypass 0 - -; exit 0 ;;
esac

# Scrub git's targeting variables before ANY git call below. When a push runs
# from a linked worktree, git's own worktree indirection can leave GIT_DIR (and
# friends) pointing at the worktree's gitdir; inherited here they (a) make
# `git rev-parse --show-toplevel` resolve the wrong repo, and (b) outrank the
# `-C <tmpdir>` isolation of any real-git test fixture the suite runs, so the
# tests silently retarget writes onto the real shared .git/config. That is the
# conductor 2026-07-16 corruption (core.bare=true + a stray committer identity,
# 17 misattributed commits). Unsetting at the gate closes the vector for every
# project, not just those whose own suite scrubs.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

# Resolve the repo root from the hook's cwd.
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ]; then
    # Matched a push but there is no repository here. Logged rather than exited
    # silently: this is the shape AGE-63 predicts — prose or a heredoc body
    # quoting a push invocation, run from somewhere that is not a checkout.
    prepush_verdict no-repo 0 - -
    exit 0
fi
cd "$root" || exit 0

# Detect the test command (make test convention first).
if [ -f Makefile ] && make -n test >/dev/null 2>&1; then
    testcmd=(make test)
elif [ -f Package.swift ]; then
    testcmd=(swift test)
elif [ -f package.json ] && grep -q '"test"[[:space:]]*:' package.json; then
    testcmd=(npm test --silent)
else
    echo "pre-push-tests: no test command detected in $root — skipping the gate. " \
         "Add a Makefile 'test' target to enforce local tests here." >&2
    prepush_verdict no-test-command 0 - -
    exit 0
fi

# --- The bound, resolved before anything is run -----------------------------

if ! resolved="$(prepush_resolve_timeout)"; then
    {
        echo "pre-push-tests: CANNOT DERIVE THIS HOOK'S OWN TIMEOUT — blocking the push."
        echo "  Without it the suite would run unbounded, and a suite that outruns the"
        echo "  platform's cancellation point lets the push out with NO verdict at all."
        echo "  Looked for a PreToolUse hook whose command names '${PREPUSH_HOOK_MARKER}',"
        echo "  in these files, in order:"
        prepush_settings_candidates | while IFS= read -r c; do
            [ -n "$c" ] && echo "    - $c"
        done
        echo "  Fix the registration, or bypass deliberately with SKIP_PREPUSH_TESTS=1."
    } >&2
    prepush_verdict unresolved-budget 0 - -
    exit 2
fi

declared_s="${resolved%% *}"
source_path="${resolved#* }"
bound=$(( declared_s - PREPUSH_BOUND_MARGIN ))

if ! bound_tool="$(prepush_resolve_bound_tool)"; then
    {
        echo "pre-push-tests: NO BOUNDING TOOL AVAILABLE — blocking the push."
        echo "  Neither 'timeout' nor 'gtimeout' was found in any of:"
        printf '%s' "$PREPUSH_BOUND_SEARCH_PATH" | tr ':' '\n' | while IFS= read -r d; do
            [ -n "$d" ] && echo "    - $d"
        done
        echo "  A gate that cannot bound itself must not run unbounded: past ${declared_s}s"
        echo "  the platform cancels this hook and ALLOWS the push with no verdict."
        echo "  Fix: brew install coreutils. Or bypass deliberately with SKIP_PREPUSH_TESTS=1."
    } >&2
    prepush_verdict no-bound-tool 0 "$bound" "$declared_s"
    exit 2
fi

bound_name="${bound_tool%% *}"
bound_dir="${bound_tool#* }"

if [ "$bound" -le 0 ]; then
    {
        echo "pre-push-tests: THE BOUND IS NOT POSITIVE (${bound}s) — blocking the push."
        echo "  Derived from a ${declared_s}s hook timeout (${source_path}) less a"
        echo "  ${PREPUSH_BOUND_MARGIN}s margin. A zero or negative duration means NO"
        echo "  TIMEOUT to ${bound_name}, which is silently the fail-open this gate exists"
        echo "  to end."
        echo "  Lower PREPUSH_BOUND_MARGIN, raise the hook's declared timeout, or bypass"
        echo "  deliberately with SKIP_PREPUSH_TESTS=1."
    } >&2
    prepush_verdict invalid-bound 0 "$bound" "$declared_s"
    exit 2
fi

# --- Run it -----------------------------------------------------------------

log="$(mktemp -t prepush-tests.XXXXXX)"
echo "pre-push-tests: running '${testcmd[*]}' before push (bypass: SKIP_PREPUSH_TESTS=1)…" >&2

# ⚠ THE TOOL IS INVOKED BY ITS LITERAL NAME, IN TWO BRANCHES, ON PURPOSE.
# `"$bound_tool" …` would be a bound reached through a VARIABLE, which
# tests/bounded-capture-guard.sh's header records as DELIBERATELY UNCOVERED — so
# the convenient spelling is exactly the one that evades review. Two literal call
# sites cost one duplicated line and put this gate into that guard's census,
# where a future change to it reds by design.
#
# Output is REDIRECTED TO A FILE and read back, never captured through `$(…)`:
# `timeout` signals only the process group it created, so a descendant that
# setsid()s out of that group survives, holds a substitution's pipe open, and
# blocks the caller for its whole lifetime while the bound LOOKS intact
# (measured 30.08s against a 5s bound; --kill-after does not help). AGE-22.
#
# The PATH extension is a COMMAND PREFIX rather than an assignment to this shell, so it
# is scoped to this invocation. ⚠ Be precise about what that does and does not buy: a
# prefix assignment IS placed in the command's environment, so the bounded suite still
# inherits the extended PATH — it must, or the tool could not be found. What the prefix
# avoids is leaving the hook's own PATH rewritten for everything after this line. In the
# ordinary case `$bound_dir` was already on PATH and the prepend is a no-op.
started="$(date +%s)"
rc=0
if [ "$bound_name" = "gtimeout" ]; then
    PATH="$bound_dir:$PATH" gtimeout -k "$PREPUSH_BOUND_KILL_AFTER" "$bound" "${testcmd[@]}" >"$log" 2>&1 || rc=$?
else
    PATH="$bound_dir:$PATH" timeout -k "$PREPUSH_BOUND_KILL_AFTER" "$bound" "${testcmd[@]}" >"$log" 2>&1 || rc=$?
fi
elapsed=$(( $(date +%s) - started ))

# ⚠ 124 ALONE IS NOT A BREACH. It is what the bounding tool reports on timeout,
# but a test suite is free to exit 124 of its own accord in a second — reporting
# that as a budget event would be the same vocabulary theft this gate refuses to
# commit in the other direction. Both conditions must hold.
if [ "$rc" -eq 124 ] && [ "$elapsed" -ge "$bound" ]; then
    {
        echo ""
        echo "=============================================================="
        echo "  PRE-PUSH BUDGET EXCEEDED — the gate blocked this push."
        echo "=============================================================="
        echo "  No test failed. '${testcmd[*]}' ran out of time."
        echo ""
        echo "  elapsed ${elapsed}s against a ${bound}s bound"
        echo "  (hook timeout ${declared_s}s from ${source_path}, less a"
        echo "   ${PREPUSH_BOUND_MARGIN}s margin, enforced with ${bound_name})"
        echo ""
        echo "  Had this run continued past ${declared_s}s the hook would have been"
        echo "  cancelled and the push ALLOWED with no verdict at all — measured 18"
        echo "  times, including two tag pushes and a PR. This block is that silent"
        echo "  outcome made loud."
        echo ""
        echo "  WHAT TO DO: re-run once on a quiet box — this fires on machine load,"
        echo "  and a concurrent test run in another repo is the measured cause (3.5x"
        echo "  wall clock, same commit, same day). If it fires again, the suite has"
        echo "  outgrown the budget, and the budget cannot be raised from here: it is"
        echo "  pinned from above by the platform's own cancellation point, so the"
        echo "  only remedy is a faster suite."
        echo "----- last 40 lines of '${testcmd[*]}' -----"
        tail -40 "$log"
        echo "=============================================================="
    } >&2
    rm -f "$log"
    prepush_verdict refused-budget "$elapsed" "$bound" "$declared_s"
    exit 2
fi

if [ "$rc" -eq 0 ]; then
    echo "pre-push-tests: tests passed — allowing push." >&2
    rm -f "$log"
    prepush_verdict pass "$elapsed" "$bound" "$declared_s"
    exit 0
fi

echo "pre-push-tests: TESTS FAILED — blocking the push. Fix them and retry." >&2
echo "----- last 40 lines of '${testcmd[*]}' -----" >&2
tail -40 "$log" >&2
rm -f "$log"
prepush_verdict fail "$elapsed" "$bound" "$declared_s"
exit 2
