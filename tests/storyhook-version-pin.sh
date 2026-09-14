#!/usr/bin/env bash
# tests/storyhook-version-pin.sh — declare, and enforce, the storyhook MAJOR
# version this repository's suites are written against.
#
# WHY THIS EXISTS
#
# `story` is an out-of-repo CLI resolved from PATH at test time. Nothing here
# declared a compatible range, so upgrading it changed this repository's test
# outcome with NO commit in this repository's history — which is also why
# `git bisect` cannot attribute the resulting failures.
#
# Measured, not inferred (AGE-19), before storywork was retired. The real
# upstream storyhook v1.0.0 binary, placed first on PATH and run under
# tests/with-isolated-store.sh:
#
#     forge                    exit 1    72 `not ok`
#     storywork                exit 1    14 assertions (test-real-story-cas.sh)
#     storyhook-contract-root  exit 1     1 test
#     greenlight               exit 0     —
#     root-bats                exit 0     —
#
# 87 failing assertions across 3 suites. ZERO of the 2,693 log lines contained
# "version", "incompat" or "upgrade". The dominant symptom, 59 times over, was
#
#     error: unknown command `project`. Run `story --help` for usage.
#
# which BLAMES THE CALLER: a reader lands on forge-close-project-story.bats:14,
# sees this repo invoking a command storyhook says does not exist, and the
# natural next move is to "fix" this repo. That is worse than unattributable —
# it points at the wrong repository. One sentence from this file replaces it.
#
# WHAT THE FOUR REAL MAJORS ACTUALLY DO — every string below was recorded by
# running the real binary, never hand-written. This corpus is the reason the
# tests need no second binary and no network.
#
#   v0.2.0  CANNOT REPORT A VERSION AT ALL; `--help` lists no version flag.
#           Two different outputs, both exit 3, depending on the directory:
#             outside a project:  error: story project not initialized in this
#                                 directory; run `story init`
#             inside one:         error: story `--version` not found
#   v1.0.0  exit 0, "story 1.0.0" — but ONLY inside an isolated store. Against
#           a newer store it exits 5 refusing every invocation, --version
#           included: "this database is at schema version 8, but this storyhook
#           only understands up to version 2 ...". That refusal text contains
#           the numerals 8 and 2, so a version parse must not harvest from it.
#   v2.0.0  exit 0, "story 2.0.0" anywhere.
#   v3.0.0  exit 0, "story 3.0.0 (build 4186eed5129c)". Forge passes
#           523/523, and storyhook-contract-root passes 9/9 against this binary.
#
# Two consequences follow, and they decide the design:
#
#   1. "Cannot obtain a version" is NOT a hypothetical edge case — it is what
#      the oldest real major does. A guard treating cannot-verify as pass would
#      go vacuously green against the most broken binary in the wild. So absent,
#      non-zero-exit and unparseable are not three concerns; they are one
#      boolean ("can this repo trust its storyhook-driving suites?") rendered as
#      four different sentences.
#   2. This guard MUST run inside tests/with-isolated-store.sh, or a perfectly
#      readable 1.x binary is misreported as unreadable. The wrapper serves the
#      policy without containing it.
#
# WHY THE ANCHOR IS STRICT, WHICH LOOKS WRONG UNTIL YOU SEE THE MEASUREMENT
#
# A looser, program-name-tolerant scan ("first MAJOR.MINOR.PATCH anywhere") is
# tempting, because it keeps a cosmetic rebrand like `storyhook 3.1.0` green.
# It also admits a SILENT FALSE GREEN, measured:
#
#     warning: 3.0.0 config format is deprecated
#     story 4.0.0
#
#   first-triple-anywhere -> 3.0.0   ** a major-4 binary PASSES **
#   ^story <triple>       -> 4.0.0      correctly fails
#
# `grep -E` is per-line, so the strict anchor skips the banner instead of
# binding it. A rebrand false red is bounded, loud and self-announcing; a false
# green on the exact scenario being guarded is silent. A rebrand is NOT silently
# accepted here either — it lands in the unparseable branch, which fails naming
# the observed output, so it stays attributable.
#
# WHAT THIS GUARD DELIBERATELY DOES NOT DO
#
#   - It does NOT catch a break shipped WITHIN major 3. That is
#     forge-contract-check.sh's job: it derives every verb, relation and
#     subcommand from the LIVE binary and trusts no version number at all. This
#     file is the cheap, loud attribution layer; that one is the semantic layer.
#     Do not sell this as the thing that catches breakage.
#   - It does NOT use `story --version --json`. That form nests the SAME free
#     text ({"result":"ok","message":"story 3.0.0"}), so it needs an identical
#     triple parse while adding a jq dependency and a second upstream shape that
#     can break independently — zero extra detection for two new failure modes.
#     v0.2.0 offers neither surface anyway.
#   - It is NOT wired as a Make prerequisite of the storyhook-driving targets,
#     although that WOULD suppress the 87 downstream failures under `make -k`
#     rather than merely attributing them (measured: dependents never run).
#     gate-integrity.sh sub-makes `make -C . test-forge` asserting exit 0, and
#     builds its PATH by dropping every directory containing a `bats` — so on
#     any machine where `bats` and `story` share a directory, an edge would make
#     the META-GATE red for a storyhook reason. Trading the gate that certifies
#     every other result for log tidiness in one invocation mode is the wrong
#     trade. Revisit trigger: if a future major bump shows this file's sentence
#     was lost in `-k` noise, reopen it together with a fix that preserves
#     `story` in gate-integrity's filtered PATH.
#
# Decided by /council-vote 2-1 (every seat voted against its own proposal); the
# strict anchor overrides a 2-1 majority on a measurement that majority did not
# have. Full audit trail: .council/age19-storyhook-version-pin/DECISION.md

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── The pin ────────────────────────────────────────────────────────────────
#
# THE one datum. Raising it is the completion criterion for a storyhook port,
# not a formality: change it here, and change the CLAUDE.md sentence that
# test_claude_md_states_the_pinned_major derives from it.
STORYHOOK_MAJOR=3

fail() { echo "        $1" >&2; return 1; }

# ── The decision, as a pure function ───────────────────────────────────────
#
# verdict() is pure in (rc, text). That is the linchpin of this file: it makes
# every decision path testable from the recorded strings above, with no second
# binary, no network and no PATH surgery. Callers render the sentence.
#
# Echoes one of: ok | nonzero_exit | unparseable | major_mismatch:<observed>
verdict() {
    local rc="$1" text="$2" ver

    # A CLI that reported an error has not reported a version, whatever else it
    # printed. Checking rc FIRST is what keeps the schema-refusal text (which
    # contains "version 8" and "version 2") from ever reaching the parser.
    if [ "$rc" -ne 0 ]; then printf 'nonzero_exit'; return; fi

    # Strict, per-line, anchored. See the header: a looser scan admits a silent
    # false green when a warning banner precedes the real version line.
    ver="$(printf '%s\n' "$text" \
        | /usr/bin/grep -oE '^story[[:space:]]+v?[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1 \
        | /usr/bin/grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

    if [ -z "$ver" ]; then printf 'unparseable'; return; fi
    if [ "${ver%%.*}" != "$STORYHOOK_MAJOR" ]; then
        printf 'major_mismatch:%s' "$ver"; return
    fi
    printf 'ok'
}

# ── Reading the live CLI ───────────────────────────────────────────────────

# resolve_story_bin — PATH only, deliberately NOT honouring STORYHOOK_BIN the
# way forge-contract-check.sh does. PATH is what the suites themselves resolve;
# a gate verifying a different binary than the suites run is a false green.
resolve_story_bin() { command -v story 2>/dev/null || true; }

# check_live_cli — the whole guard. Echoes the operator-facing sentence and
# returns 0/1. Every failure names the observed value AND the expected range,
# and prints the resolved path so a stray `story` earlier on PATH is visible in
# the log rather than silently trusted.
check_live_cli() {
    local bin out rc v
    bin="$(resolve_story_bin)"

    if [ -z "$bin" ]; then
        printf 'storyhook not verifiable: no `story` CLI on PATH, so the required storyhook major %s cannot be confirmed — a tool that cannot be checked is not a tool that passes (AGE-18). Install it, or run `make -k test` and read only the non-storyhook targets.\n' \
            "$STORYHOOK_MAJOR"
        return 1
    fi

    out="$("$bin" --version 2>&1)"; rc=$?
    v="$(verdict "$rc" "$out")"

    case "$v" in
        ok) printf 'storyhook-version-pin: %s reports a supported major %s.x\n' "$bin" "$STORYHOOK_MAJOR"; return 0 ;;
        nonzero_exit)
            printf 'storyhook not verifiable: `%s --version` exited %s printing "%s", so the required storyhook major %s cannot be confirmed — real storyhook 0.x has no version flag at all, and a 1.x binary refuses every command against a newer store.\n' \
                "$bin" "$rc" "${out%%$'\n'*}" "$STORYHOOK_MAJOR"; return 1 ;;
        unparseable)
            printf 'storyhook not verifiable: `%s --version` exited 0 but printed "%s", which is not a `story <major>.<minor>.<patch>` banner, so the required storyhook major %s cannot be confirmed.\n' \
                "$bin" "${out%%$'\n'*}" "$STORYHOOK_MAJOR"; return 1 ;;
        major_mismatch:*)
            printf 'storyhook major mismatch: `%s --version` reports %s, but this repository'"'"'s suites are written against storyhook major %s (>=%s.0.0,<%s.0.0) — test-forge and test-storyhook-contract-root will now fail with errors that never name a version, and that is a consequence of this line, not an independent defect. Install a %s.x story, or port the suites and re-pin STORYHOOK_MAJOR in tests/storyhook-version-pin.sh together with the matching CLAUDE.md sentence.\n' \
                "$bin" "${v#major_mismatch:}" "$STORYHOOK_MAJOR" "$STORYHOOK_MAJOR" \
                "$((STORYHOOK_MAJOR + 1))" "$STORYHOOK_MAJOR"; return 1 ;;
    esac
}

# ── Test harness (house plain-bash shape) ──────────────────────────────────

# A PATH with every directory that provides a `story` removed. Filtering by
# "does this dir contain story" rather than hardcoding a minimal PATH is what
# keeps the absence oracle honest across machines — the same reasoning
# gate-integrity.sh:76 records for `bats`.
story_free_path() {
    local out="" d
    local IFS=:
    for d in $PATH; do
        [ -n "$d" ] || continue
        [ -x "$d/story" ] && continue
        out="${out:+$out:}$d"
    done
    printf '%s' "$out"
}

# --- Environment validity --------------------------------------------------
#
# Without this the absence oracle passes vacuously on any machine where the
# filter silently no-ops. Not hypothetical: gate-integrity.sh carries the same
# assertion for exactly this reason.
test_story_free_path_actually_hides_story() {
    local p; p="$(story_free_path)"
    ( export PATH="$p"; command -v story >/dev/null 2>&1 ) \
        && { fail "story is STILL resolvable under the story-free PATH — every absence assertion below is vacuous"; return 1; }
    ( export PATH="$p"; command -v bash >/dev/null 2>&1 ) \
        || { fail "the story-free PATH lost bash — the filter is too aggressive and the absence oracle proves nothing"; return 1; }
}

# --- THE GATE: the only assertion that reads reality ------------------------

test_installed_story_cli_is_a_supported_major() {
    local msg; msg="$(check_live_cli)" \
        || { fail "$msg"; return 1; }
}

# --- verdict(): recorded real outputs ---------------------------------------

test_verdict_rejects_recorded_real_major_2() {
    [ "$(verdict 0 'story 2.0.0')" = "major_mismatch:2.0.0" ] \
        || { fail "recorded real v2.0.0 banner was accepted after the major-3 compatibility boundary"; return 1; }
}

test_verdict_accepts_recorded_real_major_3() {
    [ "$(verdict 0 'story 3.0.0')" = ok ] || { fail "recorded real v3.0.0 banner was rejected"; return 1; }
}

# Recorded from the installed CLI during AGE-108 compatibility validation.
test_verdict_accepts_recorded_major_3_build_banner() {
    [ "$(verdict 0 'story 3.0.0 (build 4186eed5129c)')" = ok ] \
        || { fail "recorded major-3 build banner was rejected"; return 1; }
}

test_verdict_rejects_a_distant_future_major() {
    [ "$(verdict 0 'story 99.0.0')" = 'major_mismatch:99.0.0' ] \
        || { fail "a distant unsupported major was accepted"; return 1; }
}

test_verdict_rejects_recorded_real_major_1() {
    [ "$(verdict 0 'story 1.0.0')" = "major_mismatch:1.0.0" ] \
        || { fail "recorded real v1.0.0 banner (the binary that produced 87 failures) was not reported as a major mismatch"; return 1; }
}

# Both recorded v0.2.0 shapes. A major with NO version interface must fail, not
# skip — this is the case that would make a tolerant guard vacuously green.
test_verdict_rejects_the_recorded_v0_2_0_shapes() {
    [ "$(verdict 3 'error: story project not initialized in this directory; run `story init`')" = nonzero_exit ] \
        || { fail "recorded v0.2.0 (outside a project) was not rejected"; return 1; }
    [ "$(verdict 3 'error: story `--version` not found')" = nonzero_exit ] \
        || { fail "recorded v0.2.0 (inside a project) was not rejected"; return 1; }
}

# Adversarial parse: the real refusal text contains the numerals 8 and 2.
test_verdict_rejects_the_recorded_schema_refusal() {
    [ "$(verdict 5 'error: this database is at schema version 8, but this storyhook only understands up to version 2 — it was written by a newer storyhook; upgrade with `story update`')" = nonzero_exit ] \
        || { fail "the recorded v1.0.0 schema refusal was not rejected"; return 1; }
}

# SUBSUMED, AND KEPT DELIBERATELY — do not "simplify" this away.
#
# It was designed as the uniquely-load-bearing test for the rc check, on the
# reasoning that the recorded error cases above merely shift from nonzero_exit
# to unparseable (still failing) and so could not catch that mutation. MEASURED,
# that is false HERE: those tests assert the exact verdict TOKEN, not just
# "fails", so dropping the rc check reds three tests and this is not the only
# one. It survives because it pins a DIFFERENT property than they do — that rc
# outranks a perfectly parseable stdout — where they only cover it incidentally,
# because their recorded text happens not to parse. Loosen those assertions to a
# boolean, or record a future banner that does parse, and this becomes the only
# guard again. Subsumed defence-in-depth, not a redundancy.
test_verdict_rejects_a_nonzero_exit_whose_text_parses_as_a_version() {
    [ "$(verdict 5 'story 3.0.0')" = nonzero_exit ] \
        || { fail "a CLI that EXITED NON-ZERO was trusted because its stdout happened to parse — rc must be checked before the text"; return 1; }
}

test_verdict_rejects_the_next_major() {
    local next; next=$((STORYHOOK_MAJOR + 1))
    [ "$(verdict 0 "story $next.0.0")" = "major_mismatch:$next.0.0" ] \
        || { fail "major $next — the next unsupported major — was accepted"; return 1; }
}

test_verdict_accepts_any_minor_or_patch_within_the_major() {
    local b
    for b in 'story 3.0.1' 'story 3.1.0' 'story 3.99.7'; do
        [ "$(verdict 0 "$b")" = ok ] || { fail "[$b] was rejected — the pin must not false-red inside its own major"; return 1; }
    done
}

test_verdict_rejects_unparseable_output() {
    local b
    for b in '' 'story unknown' 'story 3.0' 'storyhook-version-3'; do
        [ "$(verdict 0 "$b")" = unparseable ] \
            || { fail "[$b] did not land in the unparseable branch — cannot-verify must never read as pass"; return 1; }
    done
}

# THE FALSE GREEN, measured during the council and the reason the anchor is
# strict. Only this test reds if anyone re-unanchors the regex.
test_verdict_is_not_fooled_by_a_version_in_a_leading_banner() {
    local out; out=$'warning: 3.0.0 config format is deprecated\nstory 4.0.0'
    [ "$(verdict 0 "$out")" = "major_mismatch:4.0.0" ] \
        || { fail "a leading banner masked the real version — an unanchored scan reads 3.0.0 here and PASSES a major-4 binary, which is a silent false green on the exact scenario this guard exists to catch"; return 1; }
}

# A cosmetic rebrand is REJECTED (strict anchor) but must be ATTRIBUTABLE, not
# silent — it lands in unparseable, whose sentence names the observed output.
test_verdict_rejects_an_unrecognized_banner_format() {
    local b
    for b in 'storyhook 3.1.0' 'story-cli 3.1.0'; do
        [ "$(verdict 0 "$b")" = unparseable ] \
            || { fail "[$b] did not land in the unparseable branch — a rebrand must fail loudly, never silently pass or be misreported as a major mismatch"; return 1; }
    done
}

# Only this test reds if `head -1` becomes `tail -1`.
test_verdict_reads_the_first_banner_line_not_a_trailing_one() {
    [ "$(verdict 0 $'story 3.1.0\nstory 9.9.9')" = ok ] \
        || { fail "the parser did not bind the FIRST story banner line"; return 1; }
}

test_verdict_tolerates_a_v_prefix() {
    [ "$(verdict 0 'story v3.1.0')" = ok ] || { fail "a 'v' prefix inside the supported major was rejected"; return 1; }
}

# --- The script's wiring: verdict -> exit status -> message -----------------

test_absent_story_cli_fails_the_gate() {
    local p out rc; p="$(story_free_path)"
    rc=0
    out="$( export PATH="$p"; check_live_cli )" || rc=$?
    [ "$rc" -ne 0 ] || { fail "the guard PASSED with no story CLI on PATH — a gate that cannot verify must not report success (AGE-18)"; return 1; }
    case "$out" in *'no `story` CLI on PATH'*) ;; *) fail "the absence message did not name the missing CLI: $out"; return 1 ;; esac
}

test_failure_message_names_observed_and_expected() {
    local out; out="$(verdict 0 'story 4.0.0')"
    [ "$out" = "major_mismatch:4.0.0" ] || { fail "expected major_mismatch:4.0.0, got $out"; return 1; }
    # Render it through the real message path with a shim, so the assertion
    # covers the sentence an operator actually reads — not just the verdict.
    local d; d="$(mktemp -d /private/tmp/age19-shim.XXXXXX)"
    printf '#!/bin/sh\necho "story 4.0.0"\n' >"$d/story"; chmod +x "$d/story"
    "$d/story" >/dev/null 2>&1   # warm it: macOS assesses a fresh executable on first exec
    local msg rc; rc=0
    msg="$( export PATH="$d:$PATH"; check_live_cli )" || rc=$?
    rm -rf "$d"
    [ "$rc" -ne 0 ] || { fail "the guard exited 0 against a shim reporting major 4"; return 1; }
    case "$msg" in *4.0.0*) ;; *) fail "the failure message did not name the OBSERVED version: $msg"; return 1 ;; esac
    case "$msg" in *"major $STORYHOOK_MAJOR"*) ;; *) fail "the failure message did not name the EXPECTED major: $msg"; return 1 ;; esac
}

# POSITIVE EFFECT ORACLE. Without it, the degenerate "fix" of making the guard
# fail unconditionally satisfies every other assertion in this file.
test_guard_exits_zero_against_a_shim_reporting_a_supported_major() {
    local d; d="$(mktemp -d /private/tmp/age19-shim.XXXXXX)"
    printf '#!/bin/sh\necho "story 3.4.1"\n' >"$d/story"; chmod +x "$d/story"
    "$d/story" >/dev/null 2>&1
    local rc; rc=0
    ( export PATH="$d:$PATH"; check_live_cli >/dev/null ) || rc=$?
    rm -rf "$d"
    [ "$rc" -eq 0 ] || { fail "the guard REJECTED a shim reporting a supported major — it may be failing unconditionally"; return 1; }
}

# --- Wiring into the gate ---------------------------------------------------
#
# Preserve both membership and relative prerequisite order for the version
# guard; the separate receipt suite also pins the aggregate suite census.

# Read Make's expanded prerequisites, not the spelling of a variable reference.
# Inspect an empty goal: even -q can execute recursive recipes on traversed goals.
_test_target_list() {
    local database rc=0 list
    database="$(
        unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES
        make --no-print-directory -qp -C "$REPO_ROOT" -f Makefile -f - __storyhook_version_pin_query <<'MAKE'
.PHONY: __storyhook_version_pin_query
__storyhook_version_pin_query:
MAKE
    )" || rc=$?
    # Query status 1 means an out-of-date target, not a Make error.
    if [ "$rc" -gt 1 ]; then
        printf 'version-pin: cannot evaluate %s/Makefile (make exit %s)\n' "$REPO_ROOT" "$rc" >&2
        return 1
    fi
    list="$(printf '%s\n' "$database" | awk '
        /^test: / {
            count++
            for (i = 2; i <= NF && $i != "|"; i++) {
                printf "%s%s", separator, $i
                separator = " "
            }
        }
        END { if (count != 1 || separator == "") exit 1 }
    ')" || {
        printf 'version-pin: no unambiguous nonempty test prerequisites in %s/Makefile\n' "$REPO_ROOT" >&2
        return 1
    }
    printf '%s\n' "$list"
}

test_guard_is_a_member_of_make_test() {
    local list
    list="$(_test_target_list)" || return 1
    case " $list " in
        *" test-storyhook-version-pin "*) ;;
        *) fail "test-storyhook-version-pin is not a prerequisite of \`test:\` — a guard nobody runs is worse than no guard"; return 1 ;;
    esac
}

# The surviving storyhook-driving set, MEASURED rather than assumed: under real
# storyhook 1.0.0 these two suites failed and greenlight/root-bats passed. The
# third measured suite, storywork, has been retired and is deliberately absent.
# Note that storyhook-path-guard.sh (pure git-grep, `command -v git` only) and
# greenlight (never execs story) are also deliberately ABSENT — naming them
# would send readers to suites that a storyhook mismatch never affects.
STORYHOOK_DRIVING_TARGETS=(test-storyhook-contract-root test-forge)

test_guard_precedes_every_storyhook_driving_target() {
    local list idx=0 pin=-1 t; local -a order=()
    list="$(_test_target_list)" || return 1
    for t in $list; do order+=("$t"); done
    for t in "${order[@]}"; do
        [ "$t" = "test-storyhook-version-pin" ] && pin=$idx
        idx=$((idx + 1))
    done
    [ "$pin" -ge 0 ] || { fail "test-storyhook-version-pin is absent from \`test:\`"; return 1; }
    local d found
    for d in "${STORYHOOK_DRIVING_TARGETS[@]}"; do
        found=-1; idx=0
        for t in "${order[@]}"; do [ "$t" = "$d" ] && found=$idx; idx=$((idx + 1)); done
        # Presence is asserted, not assumed: a renamed target must RED here
        # rather than silently drop out of the ordering comparison.
        [ "$found" -ge 0 ] || { fail "$d is not in \`test:\` — the ordering pin is comparing against a target that no longer exists"; return 1; }
        [ "$pin" -lt "$found" ] || { fail "test-storyhook-version-pin runs at position $pin, AFTER $d at $found — the attributing line must come first"; return 1; }
    done
}

# Exercise the same reader/assertions against real Make syntax and broken graphs.
# Fixture recipes deliberately have side effects, including forced/recursive
# lines which query mode alone would not suppress if it traversed the test goal.
test_target_reader_expands_dependencies_without_running_recipes() (
    local d list form
    d="$(mktemp -d /private/tmp/age102-make-reader.XXXXXX)"
    trap 'rm -rf "$d"' EXIT
    REPO_ROOT="$d"
    for form in literal variable; do
        if [ "$form" = literal ]; then
            printf 'test: test-storyhook-version-pin test-storyhook-contract-root test-forge\n' >"$d/Makefile"
        else
            cat >"$d/Makefile" <<'MAKE'
PIN = test-storyhook-version-pin
SUITES := $(PIN) \
    test-storyhook-contract-root
SUITES += test-forge
test: $(SUITES)
MAKE
        fi
        cat >>"$d/Makefile" <<'MAKE'
	+touch recipe-ran
	$(MAKE) --version > recursive-ran
	"$$STORYHOOK_GATE_RECEIPT" preflight
.PHONY: test test-storyhook-version-pin test-storyhook-contract-root test-forge
test-storyhook-version-pin test-storyhook-contract-root test-forge:
	+touch prerequisite-ran
MAKE
        printf '#!/bin/sh\ntouch "%s/receipt-ran"\n' "$d" >"$d/writer"
        chmod +x "$d/writer"
        export STORYHOOK_GATE_RECEIPT="$d/writer"
        list="$(_test_target_list)" || return 1
        [ "$list" = 'test-storyhook-version-pin test-storyhook-contract-root test-forge' ] \
            || { fail "$form dependency expansion was incorrect: $list"; return 1; }
        test_guard_is_a_member_of_make_test || return 1
        test_guard_precedes_every_storyhook_driving_target || return 1
        [ ! -e "$d/recipe-ran" ] && [ ! -e "$d/recursive-ran" ] \
            && [ ! -e "$d/prerequisite-ran" ] && [ ! -e "$d/receipt-ran" ] \
            || { fail "dependency inspection executed a fixture recipe"; return 1; }
    done
)

test_target_reader_rejects_missing_and_reordered_guards() (
    local d suites
    d="$(mktemp -d /private/tmp/age102-make-reader.XXXXXX)"
    trap 'rm -rf "$d"' EXIT
    REPO_ROOT="$d"
    for suites in \
        'test-storyhook-contract-root test-forge' \
        'test-storyhook-version-pin test-forge' \
        'test-storyhook-version-pin test-storyhook-contract-root' \
        'test-storyhook-contract-root test-storyhook-version-pin test-forge' \
        'test-forge test-storyhook-version-pin test-storyhook-contract-root'; do
        printf 'SUITES := %s\ntest: $(SUITES)\n.PHONY: test $(SUITES)\n' "$suites" >"$d/Makefile"
        if test_guard_precedes_every_storyhook_driving_target >"$d/diagnostic" 2>&1; then
            fail "ordering assertion accepted broken dependencies: $suites"; return 1
        fi
    done
    printf 'test: test-forge\n.PHONY: test test-forge\n' >"$d/Makefile"
    if test_guard_is_a_member_of_make_test >"$d/diagnostic" 2>&1; then
        fail "membership assertion accepted a missing version guard"; return 1
    fi
)

test_target_reader_reports_unreadable_make_graphs() (
    local d body
    d="$(mktemp -d /private/tmp/age102-make-reader.XXXXXX)"
    trap 'rm -rf "$d"' EXIT
    REPO_ROOT="$d"
    for body in 'test: test-storyhook-version-pin\n$(error deliberate parse failure)\n' 'unrelated:\n' 'test:\n'; do
        printf '%b' "$body" >"$d/Makefile"
        if _test_target_list >"$d/output" 2>"$d/error"; then
            fail "dependency reader accepted an invalid or empty graph: $body"; return 1
        fi
        [ -s "$d/error" ] || { fail "dependency reader failed without context"; return 1; }
    done
)

# --- Doc <-> code -----------------------------------------------------------
#
# The searched string is BUILT from STORYHOOK_MAJOR, so the repo holds exactly
# ONE literal: bumping the constant automatically demands the doc follow, and
# the doc cannot drift independently. A SUBSTRING match, not a whole line, so
# rewording the sentence around it is free.
test_claude_md_states_the_pinned_major() {
    local needle="storyhook major $STORYHOOK_MAJOR"
    /usr/bin/grep -qF "$needle" "$REPO_ROOT/CLAUDE.md" \
        || { fail "CLAUDE.md does not contain \"$needle\" — the declared major and the enforced one disagree"; return 1; }
}

test_readme_states_the_pinned_major() {
    local needle="storyhook** (major $STORYHOOK_MAJOR)"
    /usr/bin/grep -qF "$needle" "$REPO_ROOT/README.md" \
        || { fail "README.md does not contain \"$needle\" — its dependency summary disagrees with the enforced major"; return 1; }
}

# Effect oracle for the above: proves the doc check can be FALSE. Without it a
# grep that matches nothing would pass vacuously — the trap both
# storyhook-path-guard.sh and storyhook-contract-root.sh carry explicit pins for.
test_claude_md_disagreement_is_detected() {
    local d; d="$(mktemp -d /private/tmp/age19-doc.XXXXXX)"
    sed "s/storyhook major $STORYHOOK_MAJOR/storyhook major 9/g" "$REPO_ROOT/CLAUDE.md" >"$d/CLAUDE.md"
    if /usr/bin/grep -qF "storyhook major $STORYHOOK_MAJOR" "$d/CLAUDE.md"; then
        rm -rf "$d"; fail "the doc-disagreement fixture still contains the pinned string — this oracle proves nothing"; return 1
    fi
    rm -rf "$d"
}

# ── Runner ─────────────────────────────────────────────────────────────────

echo "=== storyhook-version-pin ==="
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
