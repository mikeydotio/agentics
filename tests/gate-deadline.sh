#!/usr/bin/env bash
# Fail-closed self-deadline for `make test` when it is running AS the pre-push gate.
#
# WHY THIS EXISTS
#
# The global pre-push hook (`~/.claude/hooks/pre-push-tests.sh`) is registered as a
# PreToolUse(Bash) hook with a declared `timeout`. When the suite it runs exceeds that
# timeout, Claude Code CANCELS the hook and **allows the tool call anyway** — measured
# 12/12 on 2026-08-04..05, during which two tag pushes (v3.0.0, v2.39.1), a branch push
# and a PR creation all went out with no test verdict at all. Nothing in the session
# says so: a PreToolUse hook that exits 0 has its stderr discarded, and a cancelled one
# never returns the exit 2 that would have blocked the push.
#
# That is this repo's recurring class — a mechanism that reports success having verified
# nothing (AGE-18, AGE-21, AGE-27, AGE-33) — except the silence is the platform's, not
# ours. We cannot change the platform's cancel-means-allow semantics. What we CAN do is
# refuse first: if the suite is going to blow the budget, it stops itself and exits
# non-zero while the hook is still alive to see it, which the hook turns into a real
# block.
#
# ⚠ AGE-62 CHANGED WHAT THIS FILE MAY CLAIM, in one direction only. The hook script is
# now this repository's — `hooks/pre-push-tests.sh`, installed by `make install-hooks` —
# and it bounds its OWN run with `timeout`, so a breach becomes an exit 2 at 840s rather
# than a cancellation at 900s. This file did not become redundant: it refuses at 720s,
# BEFORE the hook's own bound, and it is the only layer that can name the target it
# stopped in front of. The two are ordered deliberately (720 -> 840 -> 900), and the
# outer two are now both ours.
#
# THE CLAIM, SPLIT IN TWO (council: .council/age36-prepush-gate-scope/DECISION.md)
#
#   OWNED, and pinned by tests/gate-deadline-guard.sh:
#     "This repo declares a budget for its own suite and refuses past it."
#
#   HALF VERIFIABLE FROM INSIDE THIS REPO — the split moved with AGE-62, so read it
#   precisely rather than by memory:
#     "This also closes the platform's fail-open."  True only while the declared timeout
#     exceeds our budget. Observed 900s on 2026-08-05. The SCRIPT that reads that value
#     is now ours and is pinned twice — here, and differentially against the gate's own
#     resolver in tests/prepush-gate.sh. The REGISTRATION that declares it still is not:
#     `~/.claude/settings.json` is outside every repository, and **lowering the value
#     there makes this guard inert with nothing here able to detect it**. That residue is
#     disclosed, not guarded — the same call bounded-capture-guard.sh makes in its
#     "Deliberately not covered" header, and the one AGE-34 made when it declined a
#     source-level guard.
#
# WHY ACTIVATION IS BY PROCESS ANCESTRY
#
# The hook invokes literally `make test` with no distinguishing environment
# (hooks/pre-push-tests.sh:342, :435-437), so there is nothing in the child's env to key
# on. Two alternatives were considered and rejected with reasons:
#
#   - An environment variable the hook would set. ⚠ AGE-62 made this POSSIBLE — the hook
#     is ours now — and it is still not taken, for a reason that survived the change:
#     what Claude Code runs is the INSTALLED COPY under ~/.claude/hooks/, and
#     `make check-hooks` reports drift between it and this repo without preventing it.
#     A mechanism armed by a variable the installed copy may not set ships inert and
#     cannot report that it never armed, which is this file's own thesis. Ancestry reads
#     the caller that is actually there.
#   - `[ -t 1 ]`: the hook redirects to a log (`:435-437`) — but so does this loop's own
#     `make -k test`. A tty test cannot separate the gate's run from a hand-run, so it
#     would bind an unrelated caller.
#
# Ancestry reads the actual caller. **No hook ancestor means no deadline at all**, so a
# human `make test`, a fresh clone, a container and CI behave exactly as before.
#
# WHY THE BUDGET IS DERIVED AND NEVER COPIED
#
# Hardcoding `840` here would be a second copy of a value living in a file this repo does
# not own: change that file to 600 and this guard silently becomes wrong, which is the
# very defect class it exists to close. So we READ the hook's own declared timeout. The
# value is not ours; the reader is ours, and the reader is pinnable — the same shape as
# tests/storyhook-version-pin.sh, which pins a CLI resolved from PATH.
#
# ⚠ TRAP, and it is not hypothetical: settings.json carries TWO PreToolUse entries and
# the FIRST `timeout` in the file is **5** (git-readonly-allow.py), not 900. A resolver
# that takes the first timeout it finds sets a five-second budget and blocks every push.
# We therefore match on the hook's own command path. Pinned by the guard's fixtures.
#
# WHY THE BOUND IS ARITHMETIC AND NOT `timeout`
#
# No `timeout`/`gtimeout` call site is introduced HERE, deliberately — the gate itself
# does bound with one (hooks/pre-push-tests.sh:435-437, redirected to a file and pinned
# in bounded-capture-guard.sh's census), but that is a different process at a different
# layer.
#
# A bounded command whose output reaches a caller's substitution pipe is AGE-22's defect
# (measured 30.08s against a 5s bound, because a descendant that setsid()s out of the
# process group survives), and a watchdog here would be signalling a process group that
# contains the hook and the runner themselves. Instead the wrapper compares elapsed time
# against the budget BETWEEN make targets. That satisfies "never capture a bounded command
# through $(…)" structurally rather than by discipline, and needs no
# bounded-capture-guard REGISTRY entry.
#
# Because the check happens between targets, the margin must cover the longest single
# target's overshoot: test-deployit-capture-diagnostics measures ~140-170s, so the floor
# is 180s.

set -euo pipefail

# The hook script this guard arms for. Matched as a path fragment against `ps` argv.
readonly GATE_HOOK_MARKER="${GATE_HOOK_MARKER:-pre-push-tests.sh}"

# Seconds reserved for the target about to start. Floor is 180s: above the ~140-170s
# measured for the longest single target (test-deployit-capture-diagnostics).
readonly GATE_DEADLINE_MARGIN="${GATE_DEADLINE_MARGIN:-180}"

# Exit status for a budget refusal. Deliberately NOT 1 (a test failure) and not 2 (the
# hook's own block status), so a refusal is never miscounted as a red suite at mining
# time.
readonly GATE_DEADLINE_EXIT=3

# Settings files searched, in Claude Code's precedence order. Every path tried is named
# in the diagnosis when resolution fails, so an unresolvable budget is debuggable rather
# than mysterious.
#
# CLAUDE_SETTINGS_OVERRIDE, when set, REPLACES the chain rather than being prepended to
# it. That is what "override" should mean, and it also makes this hermetic under test:
# a prepended override still falls through to the developer's real ~/.claude/settings.json
# when the fixture declares no pre-push hook, so the unresolvable branch could never be
# exercised and the guard silently read live machine config on every run.
_gate_settings_candidates() {
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

# Walk the process tree upward looking for the hook. Echoes its pid, or nothing.
# Bounded to 40 hops so a malformed ps table can never spin.
gate_find_hook_ancestor() {
    local pid="${1:-$$}" hops=0 cmd parent
    while [ "$hops" -lt 40 ] && [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
        cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
        case "$cmd" in
            *"$GATE_HOOK_MARKER"*) printf '%s' "$pid"; return 0 ;;
        esac
        parent="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
        [ -z "$parent" ] && break
        [ "$parent" = "$pid" ] && break
        pid="$parent"
        hops=$((hops + 1))
    done
    return 1
}

# Elapsed seconds for a pid, parsed from `ps -o etime=` ([[dd-]hh:]mm:ss).
gate_elapsed_seconds() {
    local pid="$1" raw days=0 rest hh=0 mm ss
    raw="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    [ -z "$raw" ] && return 1
    case "$raw" in
        *-*) days="${raw%%-*}"; rest="${raw#*-}" ;;
        *)   rest="$raw" ;;
    esac
    case "$rest" in
        *:*:*) hh="${rest%%:*}"; rest="${rest#*:}" ;;
    esac
    mm="${rest%%:*}"
    ss="${rest#*:}"
    # Strip leading zeros so nothing is read as octal.
    printf '%s' "$(( 10#$days * 86400 + 10#$hh * 3600 + 10#$mm * 60 + 10#$ss ))"
}

# Resolve the hook's own declared timeout (seconds) from the settings precedence chain.
# Matches on the hook's command path — NEVER the first timeout in the file, which is 5.
# Echoes "<seconds> <path>" on success.
gate_resolve_timeout() {
    local candidate seconds
    while IFS= read -r candidate; do
        [ -z "$candidate" ] && continue
        [ -f "$candidate" ] || continue
        # The marker goes through argv, not a command-prefix assignment: it is
        # `readonly` here, and `VAR=x cmd` on a readonly name is a fatal bash error.
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
        # Match the hook by its command path, not by position: the FIRST timeout in
        # this file belongs to a different hook and is 5 seconds.
        if marker in str(hook.get("command", "")):
            # Named `declared`, not `timeout`: bounded-capture-guard.sh scans this file
            # as SHELL, and a Python local called `timeout` sits at what that detector
            # reads as a shell command position. It is not a bounded command, so the
            # honest fix is to not look like one rather than to exempt the file — the
            # same language-vs-document distinction AGE-26 turned on.
            declared = hook.get("timeout")
            if isinstance(declared, (int, float)) and declared > 0:
                print(int(declared))
                sys.exit(0)
sys.exit(1)
' "$candidate" "$GATE_HOOK_MARKER" 2>/dev/null || true)"
        if [ -n "$seconds" ]; then
            printf '%s %s' "$seconds" "$candidate"
            return 0
        fi
    done < <(_gate_settings_candidates)
    return 1
}

# Append one line to the repo-local breadcrumb. Gitignored, and repo-local on purpose:
# a fixed /tmp path is machine-global state shared with every other project and every
# concurrent run (AGE-34; AGE-56 and AGE-57 are still open on exactly that).
gate_breadcrumb() {
    local dir="${GATE_DEADLINE_DIR:-$PWD/.gate-deadline}"
    mkdir -p "$dir" 2>/dev/null || return 0
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"$dir/log" 2>/dev/null || true
}

# The check the wrapper calls before each target. Exits GATE_DEADLINE_EXIT to refuse.
gate_deadline_check() {
    local label="${1:-<unknown>}" hook_pid resolved budget elapsed timeout_s source_path

    if ! hook_pid="$(gate_find_hook_ancestor "$$")"; then
        # Not the gate. No deadline applies — a human run, a fresh clone, CI.
        gate_breadcrumb "inactive target=$label (no ${GATE_HOOK_MARKER} ancestor)"
        return 0
    fi

    if ! resolved="$(gate_resolve_timeout)"; then
        # Under the hook, but its budget is unknowable. Refuse rather than guess: a
        # guessed budget is the "verified nothing" failure wearing a number.
        {
            echo "gate deadline: CANNOT DERIVE THE PRE-PUSH BUDGET — refusing to guess."
            echo "  Running under ${GATE_HOOK_MARKER} (pid ${hook_pid}), but no settings file"
            echo "  declares that hook's timeout. Paths searched, in order:"
            _gate_settings_candidates | while IFS= read -r c; do
                [ -n "$c" ] && echo "    - $c"
            done
            echo "  Fix the registration, or set GATE_DEADLINE_MARGIN and re-run on a quiet box."
        } >&2
        gate_breadcrumb "unresolved target=$label hook_pid=$hook_pid"
        exit "$GATE_DEADLINE_EXIT"
    fi

    timeout_s="${resolved%% *}"
    source_path="${resolved#* }"
    budget=$(( timeout_s - GATE_DEADLINE_MARGIN ))

    if ! elapsed="$(gate_elapsed_seconds "$hook_pid")"; then
        gate_breadcrumb "unreadable-etime target=$label hook_pid=$hook_pid"
        return 0
    fi

    if [ "$elapsed" -ge "$budget" ]; then
        {
            echo ""
            echo "=============================================================="
            echo "  BUDGET, NOT CORRECTNESS — the suite refused to continue."
            echo "=============================================================="
            echo "  No test failed. The pre-push gate ran out of time."
            echo ""
            echo "  elapsed ${elapsed}s of a ${budget}s budget"
            echo "  (hook timeout ${timeout_s}s from ${source_path}, less a ${GATE_DEADLINE_MARGIN}s margin)"
            echo "  stopped before: ${label}"
            echo ""
            echo "  Had this run continued past ${timeout_s}s the hook would have been"
            echo "  cancelled and the push allowed with NO verdict at all. This refusal"
            echo "  is that silent outcome made loud."
            echo ""
            echo "  WHAT TO DO: re-run once on a quiet box — this fires on machine load,"
            echo "  and a concurrent test run in another repo is the measured cause. If it"
            echo "  fires again, stop and add the timing to the suite-duration story"
            echo "  rather than working around it. The budget cannot be raised: it is"
            echo "  pinned from above by a value this repo does not control, so the only"
            echo "  remedy for a suite that outgrows it is a faster suite."
            echo "=============================================================="
        } >&2
        gate_breadcrumb "REFUSED target=$label elapsed=${elapsed}s budget=${budget}s timeout=${timeout_s}s"
        exit "$GATE_DEADLINE_EXIT"
    fi

    echo "gate deadline: ${elapsed}s/${budget}s (derived from ${source_path}) -> ${label}" >&2
    gate_breadcrumb "ok target=$label elapsed=${elapsed}s budget=${budget}s"
    return 0
}

# Allow direct invocation for the guard's fixtures: `gate-deadline.sh check <label>`.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        check) shift; gate_deadline_check "${1:-<direct>}" ;;
        resolve) gate_resolve_timeout || { echo "unresolved" >&2; exit 1; } ;;
        ancestor) gate_find_hook_ancestor "$$" || { echo "none" >&2; exit 1; } ;;
        elapsed) gate_elapsed_seconds "${2:?pid}" ;;
        *) echo "usage: gate-deadline.sh {check <label>|resolve|ancestor|elapsed <pid>}" >&2; exit 2 ;;
    esac
fi
