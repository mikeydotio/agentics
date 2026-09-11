#!/usr/bin/env bash
# tests/bounded-capture-guard.sh — a command bounded by `timeout`/`gtimeout`,
# or by a wrapper around one, must never have its output captured through a
# command substitution.
#
# THE MECHANISM. `timeout(1)` signals the process GROUP it created. A descendant
# that calls setsid() leaves that group, survives the bound, and keeps the write
# end of a `$()` pipe open. A command substitution does not return until every
# writer closes it, so the caller blocks for the survivor's whole lifetime while
# the timeout appears intact. Measured 2026-08-04 on this machine, against a 5s
# bound, with a shim that forks a setsid child sleeping 30s then exits 0:
#
#     out=$(timeout 5 shim)                  30.08s   rc=0
#     timeout 5 shim > file                   0.03s   rc=0
#     out=$(timeout --kill-after=1 5 shim)   30.09s   rc=0
#
# `--kill-after` does NOT close it: SIGKILL targets the same group the
# descendant left. Redirect to a file and read it back with `$(<file)` — a plain
# file has no reader waiting on EOF. That is the fix AGE-16 shipped at
# plugins/forge/hooks/session-stop.sh:194-200, and this guard exists so the next
# occurrence cannot be written silently (AGE-22).
#
# ⚠ THE INVARIANT IS NARROWER THAN "DON'T CAPTURE A BOUNDED COMMAND". The hazard
# is the bounded command's stdout BEING the substitution's pipe. A wrapper that
# redirects the bounded child internally severs the chain: rca-repro.sh's
# run_bounded() runs `bash -c "$cmd" >"$outfile" 2>&1 &`, so a surviving
# descendant inherits the outfile fd and never a caller's pipe. That is why
# plugins/rca/tests/test-repro.sh:35 -- a `$()` capture containing the word
# `timeout` -- is CORRECT and stays green here. A guard matching "the word
# timeout appears inside $()" reds a correct line on day one; it is in the BENIGN
# corpus below so that calibration is executable rather than a claim.
#
# ⚠ WHAT THIS GUARD DELIBERATELY DOES NOT DO, and why -- the council record is
# at .council/age22-bounded-capture-guard/DECISION.md.
#
#   NO DERIVED CLOSURE over function bodies. Deriving "which functions wrap a
#   bounded command" was proposed and disqualified by measurement:
#   `run_explorer() (` at greenlight-explore.sh:135 is PAREN-bodied and is the
#   ONLY such definition in the repo, while the house body-extraction idiom
#   (sigpipe-shape-guard.sh:115, :272) keys on /^name() {/ ... /^}/. A closure
#   built on it silently loses one of the only two propagating wrappers, and an
#   empty derived set is indistinguishable from a correct one. rca-bisect.sh's
#   run_bounded is worse still: it is text inside a `cat > "$1" <<'WRAP'`
#   heredoc, not a definition in that file at all.
#
#   NO REDIRECT HEURISTIC. Deciding "was this bounded call redirected" from the
#   source was proposed, voted for, and withdrawn by its own author. Four shapes
#   break it, all in the UNSAFE direction: `2>/dev/null` alone leaves stdout on
#   the pipe; `2>&1 >file` sends stderr to the ORIGINAL stdout -- the pipe --
#   while reading as redirected; `| tee f` launders rather than severs, because
#   tee holds the pipe and blocks on the escaped writer; and `exec >"$f"` earlier
#   in a body is not on the invocation line at all. A fifth is already in this
#   repo: session-stop.sh:196's redirect sits on line 197 behind a backslash
#   continuation, so a per-line test misreads the blessed call site as
#   unredirected. Safety in fact requires BOTH of the bounded child's fds moved
#   and no other inherited fd carrying the pipe -- storyhook's SH-94 recorded a
#   daemon holding a pipe at fd 7 -- which no line-local test can establish.
#
# Instead the guard asserts four things it CAN know mechanically, and pins the
# census positively so a broken pathspec cannot pass vacuously:
#
#   L1  no bounded command at a COMMAND POSITION inside `$(...)` or backticks
#   L2  the command-position bounded invocations repo-wide are EXACTLY the
#       pinned set, counted in MATCHES (not lines) with per-file counts
#   L3  no capture of a registry wrapper name; each registry name has a
#       definition found by a pattern matching BOTH `() {` and `() (`
#   L4  the registry names' own occurrences are EXACTLY the pinned set -- this
#       is what closes depth-2 (`foo() { run_with_timeout 5 x; }` then
#       `out=$(foo)` introduces no new `timeout` site and no capture of a
#       registry name, so L1-L3 are all green; it introduces a tenth registry
#       OCCURRENCE, and L4 reds on that)
#
# ⚠ TWO REPAIRS THAT ARE LOAD-BEARING, both measured, both false greens in the
# census mechanism itself before they were made:
#
#   1. COMMAND POSITION must admit an exec prefix and a backtick opener. The
#      first-draft anchor matched `out=$(timeout 5 x)` but MISSED 5 of 6 probes:
#      the backtick-opened form and all four of env/command/nohup/xargs. So
#      `out=$(env timeout 5 story handoff)` -- a ONE-TOKEN rewrite of AGE-16's
#      own defect -- would have passed green.
#   2. THE COUNTING UNIT IS MATCHES, NOT LINES. `grep -c` counts lines, so
#      appending `; timeout 9 evil` to an already-pinned line leaves a
#      line-counting census sitting at its pinned total. Measured: grep -c = 1
#      where grep -o = 2. test_census_counts_matches_not_lines pins this.
#
# ⚠ AND ONE FALSE POSITIVE THIS GUARD'S OWN CALIBRATION FOUND, on documentation
# that describes the very defect. session-stop.bats:83 reads "...escapes the
# process group `timeout` signals and...", an English sentence inside a Python
# docstring inside a heredoc -- so it is NOT a `#` line and the comment filter
# cannot reach it. The fix is mechanical, not an exemption: the token's trailing
# class excludes a backtick, so an inline-code SPAN (`timeout`) does not match
# while a real backtick substitution (`timeout 5 x`) does. A guard you can
# satisfy by deleting a true sentence is the wrong guard (the AGE-11 rule).
#
# ⚠ KNOWN LIMIT OF THE SCAN. Every layer is seeded on the literal words
# `timeout`/`gtimeout` and on the literal registry names. NOT matched: a
# hand-rolled bound (the background-pid + `kill -TERM` mechanism this repo
# already uses twice in rca -- MORE exposed than timeout(1), since `kill` on a
# pid does not signal the group at all), `perl -e alarm`, a `read -t` loop, a
# bound reached through a variable (`"$TO" 5 cmd`), or a name assembled at
# runtime. The scan set is also INDEX-BASED (`git ls-files`), so a brand-new
# script is invisible until it is `git add`ed -- which is the right boundary for
# a pre-push gate (nothing unstaged can be pushed) but will surprise you if you
# expect a red while iterating on an untracked file. L4's fixpoint is also
# manual: a new registry occurrence reds loudly,
# but a reviewer who classifies a genuine depth-2 wrapper as an ordinary call
# reopens the hole one level down. Finally, shipped markdown instructing an agent
# to write the capture is out of scope by construction.
#   Treat a green as "no KNOWN bounding primitive and no KNOWN wrapper is
#   captured", never as "no capture is possible".

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREP=/usr/bin/grep   # AGE-42: an agent-run `grep` may be ugrep, whose POSIX
                     # classes differ. Pin the one bats and the hooks get.

PASS=0
FAIL=0
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# The detector
# ---------------------------------------------------------------------------

# A separator after which the next word is a COMMAND, not an argument. `(` and a
# backtick are included so a nested opener counts. The keywords require a
# preceding space-or-semicolon so that ordinary words containing them -- "window"
# contains "do" -- cannot pose as a separator.
SEP='([;&|(`{]|[[:space:];](then|do|else)[[:space:]])'

# Prefixes that still leave the NEXT word in command position. Bare-word only:
# admitting flags here would make `command -v timeout` -- a probe, present three
# times in this repo -- match, which is the whole reason the probe is in BENIGN.
EXEC='((env|command|nohup|xargs|stdbuf|setsid|ionice|nice|doas)[[:space:]]+)?'
ASSIGN='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'

# The trailing class EXCLUDES a backtick on purpose -- see the calibration note
# in the header. `)` is admitted so `$(timeout)` still matches.
TAIL='([[:space:]]|\)|$)'

# The registry detector uses a WIDER tail that admits the backtick, so that
# ``o=`run_explorer` `` is caught. The prose hazard that forced the narrow TAIL
# above is specific to `timeout`, an ordinary English word that documentation
# writes as an inline-code span; a registry entry is a repo-local identifier, and
# any prose occurrence of one would move the L4 census and be reviewed there.
TAIL_REG='([[:space:]]|\)|`|$)'

OPEN='(\$\(|`)'
BOUND="(timeout|gtimeout)${TAIL}"

# The registry: names that wrap, or hand-roll, a bound. Each carries a reviewed
# claim, not an inference -- see L3/L4. `run_bounded` is listed even though it
# redirects its bounded child internally: capturing it is not the AGE-16 hazard,
# but pinning its occurrences is what keeps L4's depth-2 arm honest, and a
# capture of it is a claim a reviewer should have to make out loud.
REGISTRY=(run_with_timeout run_explorer run_bounded)
REG_ALT="$(IFS='|'; printf '%s' "${REGISTRY[*]}")"

# L2 census anchor: a bounded command at a command position, anywhere.
CMD_POS="(^|${SEP})[[:space:]]*${ASSIGN}${EXEC}${BOUND}"
# L1: the same, but demonstrably INSIDE a substitution opened on this line.
L1_RE="${OPEN}([^)]*${SEP})?[[:space:]]*${ASSIGN}${EXEC}${BOUND}"
# L3: a registry name captured through a substitution.
L3_RE="${OPEN}([^)]*${SEP})?[[:space:]]*${ASSIGN}${EXEC}(${REG_ALT})${TAIL_REG}"
# L4: any occurrence of a registry name at all.
REG_ANY="(${REG_ALT})"

# A definition pattern that admits BOTH body forms. Brace-only is the house
# idiom's bug: it silently misses greenlight-explore.sh:135's `run_explorer() (`.
def_re() { printf '^[[:space:]]*(function[[:space:]]+)?%s[[:space:]]*\\(\\)[[:space:]]*[({]' "$1"; }

# Lines whose first non-space character is `#` are prose, not invocations.
# session-stop.sh:98-106 quotes this exact hazard in order to DENY it; a guard
# you can satisfy by deleting a true sentence is the wrong guard.
strip_comments() { "$GREP" -vE '^[[:space:]]*#' "$1" 2>/dev/null; }

# scan_lines <regex> -> "path:lineno:text" for every non-comment match in the
# scan set, empty if clean.
#
# ⚠ The trailing `|| true` is load-bearing, not decoration. This file arms
# `pipefail`, and `grep` exits 1 on a legitimate NO MATCH -- which is the normal
# case here. Without it the assignment carries status 1, and the runner's
# `set -e` kills the arm BEFORE it can print its diagnostic, so a clean tree and
# a broken regex both surface as a bare "FAIL" with no output. Cousin of AGE-21:
# pipefail reporting failure for a pipeline that did exactly what was asked.
scan_lines() {
    local re="$1" f
    {
        while IFS= read -r f; do
            strip_comments "$REPO_ROOT/$f" | "$GREP" -nE "$re" | sed "s|^|$f:|"
        done < <(scan_set)
    } || true
}

# ---------------------------------------------------------------------------
# The scan set
# ---------------------------------------------------------------------------

# Derived from `git ls-files`, never a filesystem glob: a glob would also walk
# the stale `.claude/worktrees/` copies and pin them. Extension globs UNION
# extensionless files carrying a SHELL shebang -- this repo has nine of the
# latter (plugins/*/tests/fakes/{gh,story,tmux,tailscale}), and a fake CLI is
# exactly where someone writes a bounded capture to simulate a hung tool.
# `plugins/deployit/bin/deployit-posttest` is extensionless PYTHON and is
# correctly excluded by the shebang test, though its docstring says "timeout".
SELF_REL="tests/bounded-capture-guard.sh"

shell_shebang_files() {
    git -C "$REPO_ROOT" ls-files | while IFS= read -r f; do
        case "${f##*/}" in *.*) continue ;; esac
        [ -f "$REPO_ROOT/$f" ] || continue
        head -1 "$REPO_ROOT/$f" 2>/dev/null \
            | "$GREP" -qE '^#!.*[[:space:]/](ba|z|k|a)?sh([[:space:]]|$)' \
            && printf '%s\n' "$f"
    done
}

# The guard necessarily contains the shapes it bans (its own regexes and both
# corpora), so it excludes itself. That exemption is pinned by
# test_scan_self_exclusion_is_exactly_one_pinned_file.
scan_set() {
    {
        git -C "$REPO_ROOT" ls-files -- '*.sh' '*.bash' '*.bats' 'Makefile' '*/Makefile'
        shell_shebang_files
    } | sort -u | "$GREP" -vxF "$SELF_REL"
}

# census <regex> <file>... -> "path<TAB>match-count" for every file with >0.
# Counts MATCHES via `grep -o`, not lines: see repair 2 in the header.
census() {
    local re="$1"; shift
    local f n
    for f in "$@"; do
        [ -f "$f" ] || continue
        # `|| true` for the same pipefail-plus-no-match reason as scan_lines.
        n=$(strip_comments "$f" | "$GREP" -oE "$re" | wc -l | tr -d ' ') || true
        [ "${n:-0}" -gt 0 ] && printf '%s\t%s\n' "$f" "$n"
    done
    return 0
}

census_repo() {  # <regex> -> census over the real scan set, repo-relative paths
    local re="$1" f
    while IFS= read -r f; do
        census "$re" "$REPO_ROOT/$f" | sed "s|^${REPO_ROOT}/||"
    done < <(scan_set)
}

# --- the pins ---------------------------------------------------------------
#
# Positively asserted, per file AND in total. A negative-only "no unpinned sites
# were found" assertion passes on BOTH ways this can break -- a typo'd pathspec
# (0 hits, rc 1) and running outside a git repo (fatal, empty output) -- which is
# why the totals and the positive control below exist.

BOUND_PINS=$(cat <<'PINS'
plugins/forge/hooks/session-stop.sh	2
plugins/greenlight/bin/greenlight-explore.sh	1
PINS
)
BOUND_TOTAL=3

REG_PINS=$(cat <<'PINS'
plugins/forge/hooks/session-stop.sh	2
plugins/greenlight/bin/greenlight-explore.sh	2
plugins/rca/bin/rca-bisect.sh	3
plugins/rca/bin/rca-repro.sh	2
PINS
)
REG_TOTAL=9

sum_counts() { awk -F'\t' '{s += $2} END {print s + 0}'; }

# ---------------------------------------------------------------------------
# L1 — no bounded command captured through a substitution
# ---------------------------------------------------------------------------

test_l1_no_bounded_command_is_captured() {
    local hits
    hits=$(scan_lines "$L1_RE")
    if [ -n "$hits" ]; then
        echo "a bounded command's output is captured through a substitution:"
        echo "$hits" | sed 's/^/    /'
        echo "the bound does NOT hold: a descendant that leaves the process group"
        echo "keeps the pipe's write end open and the substitution waits for it."
        echo "Redirect to a temp file and read it back with \$(<file) instead --"
        echo "see plugins/forge/hooks/session-stop.sh:194-200 for the shape."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# L2 — the bounded-invocation census
# ---------------------------------------------------------------------------

test_l2_bound_census_matches_the_pins_exactly() {
    local actual
    actual=$(census_repo "$CMD_POS" | sort)
    if [ "$actual" != "$(printf '%s\n' "$BOUND_PINS" | sort)" ]; then
        echo "the set of command-position timeout/gtimeout invocations changed."
        echo "expected:"; printf '%s\n' "$BOUND_PINS" | sort | sed 's/^/    /'
        echo "actual:";   printf '%s\n' "$actual"     | sed 's/^/    /'
        echo ""
        echo "This is the layer that makes a NEW bounding wrapper impossible to"
        echo "write silently. Do not just bump the pin: decide whether the new"
        echo "site's output can ever reach a caller's substitution pipe, and if"
        echo "it can, add its wrapper name to REGISTRY as well."
        return 1
    fi
}

test_l2_bound_census_total_is_pinned() {
    local n
    n=$(census_repo "$CMD_POS" | sum_counts)
    [ "$n" = "$BOUND_TOTAL" ] || {
        echo "expected $BOUND_TOTAL bounded invocations in total, found $n"
        return 1
    }
}

# ---------------------------------------------------------------------------
# L3 — the wrapper registry
# ---------------------------------------------------------------------------

test_l3_no_registry_wrapper_is_captured() {
    local hits
    hits=$(scan_lines "$L3_RE")
    if [ -n "$hits" ]; then
        echo "a bounding wrapper's output is captured through a substitution:"
        echo "$hits" | sed 's/^/    /'
        echo "the wrapper name hides the bound but not the hazard -- see L1."
        return 1
    fi
}

test_l3_every_registry_name_has_a_definition() {
    local name missing=()
    for name in "${REGISTRY[@]}"; do
        git -C "$REPO_ROOT" grep -qE "$(def_re "$name")" -- '*.sh' '*.bash' '*.bats' \
            || missing+=("$name")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "registry names with no definition in the tree:"
        printf '    %s\n' "${missing[@]}"
        echo "a registry entry that matches nothing bans nothing -- it is a"
        echo "vacuous pin. Either the wrapper was renamed (update REGISTRY and"
        echo "the L4 pins together) or it was deleted (drop the entry)."
        return 1
    fi
}

test_l3_definition_pattern_finds_the_paren_bodied_wrapper() {
    # The single most important arm in this file. `run_explorer() (` is the ONLY
    # paren-bodied definition in the repo, and the house extraction idiom keys on
    # `() {`. A regression to brace-only reds HERE instead of silently dropping a
    # genuinely propagating wrapper from the registry's reach.
    local hit
    hit=$(git -C "$REPO_ROOT" grep -nE "$(def_re run_explorer)" \
              -- 'plugins/greenlight/bin/greenlight-explore.sh')
    if [ -z "$hit" ]; then
        echo "the definition pattern no longer finds run_explorer() ("
        echo "it is paren-bodied; a pattern matching only '() {' misses it."
        return 1
    fi
    case "$hit" in
        *'() ('*) : ;;
        *) echo "expected a paren-bodied definition, got: $hit"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# L4 — the registry-occurrence census (this is what closes depth-2)
# ---------------------------------------------------------------------------

test_l4_registry_occurrence_census_matches_the_pins_exactly() {
    local actual
    actual=$(census_repo "$REG_ANY" | sort)
    if [ "$actual" != "$(printf '%s\n' "$REG_PINS" | sort)" ]; then
        echo "the set of registry-wrapper occurrences changed."
        echo "expected:"; printf '%s\n' "$REG_PINS" | sort | sed 's/^/    /'
        echo "actual:";   printf '%s\n' "$actual"   | sed 's/^/    /'
        echo ""
        echo "If the new occurrence is a function that CALLS a registry wrapper,"
        echo "that function is itself a bounding wrapper -- add its name to"
        echo "REGISTRY, or its callers can capture it and L1-L3 will not see it."
        echo "That depth-2 case is the entire reason this layer exists."
        return 1
    fi
}

test_l4_registry_occurrence_total_is_pinned() {
    local n
    n=$(census_repo "$REG_ANY" | sum_counts)
    [ "$n" = "$REG_TOTAL" ] || {
        echo "expected $REG_TOTAL registry occurrences in total, found $n"
        return 1
    }
}

# ---------------------------------------------------------------------------
# Scope integrity — the foundation all four layers stand on
# ---------------------------------------------------------------------------

test_scan_set_is_not_vacuous() {
    local n
    n=$(scan_set | wc -l | tr -d ' ')
    if [ "$n" -lt 100 ]; then
        echo "scan set has only $n files -- expected >=100."
        echo "a shrunken pathspec is how every layer here passes vacuously."
        return 1
    fi
}

test_scan_set_covers_every_tracked_shell_shebang_file() {
    local missing f set_file
    set_file="$WORK/scanset"; scan_set > "$set_file"
    missing=$(while IFS= read -r f; do
                  "$GREP" -qxF "$f" "$set_file" || printf '%s\n' "$f"
              done < <(shell_shebang_files))
    if [ -n "$missing" ]; then
        echo "tracked shell scripts outside the scan set:"
        echo "$missing" | sed 's/^/    /'
        return 1
    fi
}

test_scan_set_includes_a_known_extensionless_script() {
    # Not redundant with the arm above: that one detects a pathspec that DROPS a
    # known file, but nothing detects one that never SEES a newly added
    # extensionless script. This pins that the shebang path is wired at all.
    scan_set | "$GREP" -qxF 'plugins/rca/tests/fakes/story' || {
        echo "plugins/rca/tests/fakes/story is not in the scan set --"
        echo "the extensionless/shebang half of the scan set is not wired."
        return 1
    }
}

test_scan_set_excludes_extensionless_non_shell_scripts() {
    if scan_set | "$GREP" -qxF 'plugins/deployit/bin/deployit-posttest'; then
        echo "deployit-posttest is extensionless PYTHON and must not be scanned"
        echo "as shell -- its module docstring carries 'timeout' at line start."
        return 1
    fi
}

test_scan_self_exclusion_is_exactly_one_pinned_file() {
    local body excl
    body=$(awk '/^scan_set\(\) \{/ {f=1} f {print} f && /^\}/ {exit}' "${BASH_SOURCE[0]}")
    excl=$(printf '%s\n' "$body" | "$GREP" -c 'GREP" -vxF' )
    [ "$excl" = "1" ] || { echo "expected exactly 1 exclusion in scan_set, found $excl"; return 1; }
    [ "$SELF_REL" = "tests/bounded-capture-guard.sh" ] \
        || { echo "the one exclusion is not this file: $SELF_REL"; return 1; }
    [ -f "$REPO_ROOT/$SELF_REL" ] \
        || { echo "SELF_REL does not exist: $SELF_REL"; return 1; }
}

# ---------------------------------------------------------------------------
# Detector accuracy, as executable arms rather than one-time measurements
# ---------------------------------------------------------------------------

DANGEROUS=(
    'out=$(timeout 5 shim)'
    'out=$(gtimeout 5 shim)'
    'out=`timeout 5 shim`'
    'out=$(env timeout 5 shim)'
    'out=$(command timeout 5 shim)'
    'out=$(nohup timeout 5 shim)'
    'out=$(xargs timeout 5 shim)'
    'out=$(setsid timeout 5 shim)'
    'x="$(cd "$d" && timeout 5 story handoff)"'
    'v=$( { timeout 5 x; } )'
    'q=$(if true; then timeout 5 x; fi)'
    'z=$(FOO=1 timeout 5 x)'
    'out=$(timeout)'
)
BENIGN=(
    # The decisive live case: a correct capture whose text contains "timeout".
    "out=\$(bash \"\$REPO\" run --cmd 'sleep 5' --runs 1 --timeout 1 || true)"
    'if command -v timeout >/dev/null 2>&1; then'
    'emit_err timeout "run $i exceeded ${timeout}s"'
    '  local timeout="$1" outfile="$2" cmd="$3" pid elapsed=0'
    '_timeout="${STEP_TIMEOUT:-600}"'
    '  --timeout) timeout="${2:-600}"; shift 2 ;;'
    'timeout 5 shim > "$OUT"'
    'gtimeout 5 shim >"$f" 2>&1'
    'run_explorer > "$OUT" 2>/dev/null'
    'out=$(get_window_list)'
    'case "$x" in timeout) echo hi ;; esac'
    # Prose: an inline-code span, not an invocation. session-stop.bats:83.
    '`story ... daemon --serve` that escapes the process group `timeout` signals'
)
DANGEROUS_REG=(
    'out=$(run_with_timeout 5 story handoff)'
    'out=$(run_explorer)'
    'o=`run_explorer`'
    'x=$(cd "$d" && run_with_timeout 5 x)'
)
BENIGN_REG=(
    'run_explorer > "$OUT" 2>/dev/null'
    '    ( cd "$PROJECT_DIR" && run_with_timeout 5 story handoff --since "${D}" \'
    'run_bounded "${TEST_CMD:?}"; code=$?'
)

flags() { printf '%s\n' "$2" | "$GREP" -qE "$1"; }

test_detector_flags_every_dangerous_capture() {
    local bad=() line
    for line in "${DANGEROUS[@]}"; do
        flags "$L1_RE" "$line" || bad+=("$line")
    done
    [ ${#bad[@]} -eq 0 ] || { echo "L1 MISSED:"; printf '    %s\n' "${bad[@]}"; return 1; }
}

test_detector_ignores_every_benign_shape() {
    local bad=() line
    for line in "${BENIGN[@]}"; do
        flags "$L1_RE" "$line" && bad+=("$line")
    done
    [ ${#bad[@]} -eq 0 ] || { echo "L1 FALSE-POSITIVED:"; printf '    %s\n' "${bad[@]}"; return 1; }
}

test_registry_detector_flags_every_dangerous_capture() {
    local bad=() line
    for line in "${DANGEROUS_REG[@]}"; do
        flags "$L3_RE" "$line" || bad+=("$line")
    done
    [ ${#bad[@]} -eq 0 ] || { echo "L3 MISSED:"; printf '    %s\n' "${bad[@]}"; return 1; }
}

test_registry_detector_ignores_correct_call_sites() {
    local bad=() line
    for line in "${BENIGN_REG[@]}"; do
        flags "$L3_RE" "$line" && bad+=("$line")
    done
    [ ${#bad[@]} -eq 0 ] || { echo "L3 FALSE-POSITIVED:"; printf '    %s\n' "${bad[@]}"; return 1; }
}

test_exec_prefix_is_admitted_but_a_probe_is_not() {
    # The repair that matters most: without the exec prefix,
    # `$(env timeout 5 story handoff)` -- a one-token rewrite of AGE-16 -- is
    # invisible. Admitting FLAGS after the prefix would make `command -v timeout`
    # match, so this arm pins both directions at once.
    flags "$L1_RE" 'out=$(env timeout 5 x)'  || { echo "exec prefix not admitted"; return 1; }
    flags "$L1_RE" 'out=$(command timeout 5 x)' || { echo "command prefix not admitted"; return 1; }
    ! flags "$CMD_POS" 'if command -v timeout >/dev/null 2>&1; then' \
        || { echo "the 'command -v timeout' PROBE was read as an invocation"; return 1; }
}

test_inline_code_span_is_not_an_invocation() {
    # The trailing class excludes a backtick so prose survives. Deleting that
    # exclusion reds here rather than reddening a true sentence in a docstring.
    ! flags "$CMD_POS" 'the process group `timeout` signals and' \
        || { echo "an inline-code span was read as an invocation"; return 1; }
    flags "$CMD_POS" 'out=`timeout 5 x`' \
        || { echo "a real backtick substitution is no longer detected"; return 1; }
}

# ---------------------------------------------------------------------------
# Anti-vacuity: the census machinery must be able to FAIL
# ---------------------------------------------------------------------------

plant() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

test_positive_control_detector_hits_a_planted_site() {
    # Without this, a regex that matches nothing satisfies every negative arm in
    # this file. Measured: a typo'd pathspec returns 0 hits with rc=1, and a
    # negative-only assertion passes on that exactly as it passes on a clean tree.
    local f="$WORK/pos/evil.sh"
    plant "$f" 'out=$(timeout 5 shim)'
    [ -n "$(census "$CMD_POS" "$f")" ] \
        || { echo "the detector cannot hit a planted dangerous site at all"; return 1; }
    [ -n "$("$GREP" -nE "$L1_RE" "$f")" ] \
        || { echo "L1 cannot hit a planted capture at all"; return 1; }
}

test_scan_lines_plumbing_can_report_a_hit() {
    # L1 and L3 report through scan_lines, and their PASS is an empty result --
    # so plumbing that can never emit anything makes both of them vacuous. This
    # is not hypothetical: the first draft of this file lost every diagnostic to
    # pipefail (grep exits 1 on no-match, `set -e` then killed the arm before it
    # printed), and a clean tree was indistinguishable from a broken regex.
    local out
    out=$(scan_lines '[[:alnum:]]' | head -1)
    case "$out" in
        *:*:*) : ;;
        *) echo "scan_lines produced no path:line:text output for a regex that"
           echo "matches nearly every line -- L1 and L3 are reporting vacuously."
           echo "got: '$out'"
           return 1 ;;
    esac
}

test_census_counts_matches_not_lines() {
    # Repair 2. A second invocation appended to an ALREADY-PINNED line must move
    # the count. `grep -c` reports 1 here; `grep -o` reports 2.
    local f="$WORK/dbl/two.sh" n
    plant "$f" 'timeout "$secs" "$@"; timeout 9 evil'
    n=$(census "$CMD_POS" "$f" | cut -f2)
    [ "$n" = "2" ] || {
        echo "expected 2 matches on a doubled line, got '${n:-0}'"
        echo "the census is counting LINES; an appended second bounded call"
        echo "would ride an already-pinned line into a green."
        return 1
    }
}

test_census_sees_a_planted_fourth_site() {
    local f="$WORK/four/new.sh"
    plant "$f" '  timeout 30 some-new-thing'
    [ "$(census "$CMD_POS" "$f" | cut -f2)" = "1" ] \
        || { echo "a new bounding site would not be censused"; return 1; }
}

test_census_ignores_a_commented_out_site() {
    local f="$WORK/cmt/c.sh"
    plant "$f" '# timeout 30 documented-but-not-invoked'
    [ -z "$(census "$CMD_POS" "$f")" ] \
        || { echo "a comment was censused as an invocation"; return 1; }
}

test_depth_two_wrapper_is_caught_by_the_registry_census() {
    # The hole this layer exists for, as an executable arm. L1 sees no `timeout`
    # token here and L3 sees no capture of a registry NAME -- only the occurrence
    # census moves.
    local f="$WORK/d2/depth2.sh"
    plant "$f" 'foo() { run_with_timeout 5 cmd; }'
    ! "$GREP" -qE "$L1_RE" "$f" || { echo "L1 unexpectedly matched -- rewrite this arm"; return 1; }
    ! "$GREP" -qE "$L3_RE" "$f" || { echo "L3 unexpectedly matched -- rewrite this arm"; return 1; }
    [ "$(census "$REG_ANY" "$f" | cut -f2)" = "1" ] \
        || { echo "a depth-2 wrapper produces no registry occurrence -- the hole is open"; return 1; }
}

# ---------------------------------------------------------------------------

echo "=== bounded-capture-guard ==="
for fn in $(declare -F | awk '{print $3}' | "$GREP" '^test_' | sort); do
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
