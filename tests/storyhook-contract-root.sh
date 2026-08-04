#!/usr/bin/env bash
# tests/storyhook-contract-root.sh — the F103 storyhook-grammar guard, pointed
# at this repository's own root agent-instruction files.
#
# WHY THIS EXISTS SEPARATELY FROM THE GUARD ITSELF
#
# plugins/forge/bin/forge-contract-check.sh derives its scan set by DIRECTORY
# SHAPE — <root>/references/*.md and <root>/skills/*/SKILL.md — which is exactly
# right for forge's own self-describing tree and cannot reach a repo-root file at
# all. Pointing it at a repo root today returns files_scanned:[] with
# contract_ok:true: a green having read nothing.
#
# The fix is NOT a filename baked into the shipped script. That script owns
# grammar and derives every verb, relationship and subcommand from the live
# `story` binary; WHICH of a repo's root files are storyhook documentation is
# that repo's knowledge. So the script gained `--file` (AGE-30) and this suite —
# repo-local, and the only place a filename is written down — supplies the list.
#
# THIS IS THE OTHER HALF OF tests/storyhook-path-guard.sh's Layer 3.
# Layer 3 greps root instruction files for retired storyhook SURFACES, which are
# fixed strings. AGE-27 claim #2, the dead id-first form `story <id> is done`, is
# pattern-shaped rather than a fixed string, so no grep can hold it — only a
# grammar guard can, and that is this file. The two suites are deliberately NOT
# merged: this one depends on the live `story` CLI and carries an ok:false
# cannot-verify path, and folding that into Layer 3's pure git-grep suite would
# give one suite's green two different meanings and misattribute its failures.
#
# WHY THE LIST IS HAND-MAINTAINED AND SEPARATE FROM LAYER 3'S
# Layer 3's allowlist is AGENTS.md, CLAUDE.md, README.md and .gitignore, and
# reusing it filtered to *.md would admit README.md by MECHANISM rather than by
# decision. Measured: README.md carries 0 `story ` occurrences and 4 fence
# markers — pure false-positive surface for zero detection. These are two lists
# that happen to overlap, not one list narrowed, so a Layer 3 edit made for
# path-guard reasons must never silently widen a grammar scan. False positives
# are worse than false negatives here: this suite gates `make test`.
#
# WHY CLAUDE.md IS IN DESPITE CARRYING NO INVOCATIONS TODAY
# Its only `story` occurrence is English prose ("parent story could permanently
# deadlock"), correctly ignored. Reach measures today's CONTENT, not blast
# radius — CLAUDE.md is read as instruction by every agent unprompted, so it is
# precisely where a silent coverage drop would go unnoticed. Excluding it would
# also create a documented safe harbour for the drift this guard exists to kill.
#
# ⚠ AGENTS.md IS GENERATED (`story scaffold agents-md`), and only the header
# above `<!-- BEGIN GENERATED -->` survives regeneration. So an `expect-dead`
# marker CANNOT durably live on a generated line, and the escape hatch for a
# false positive here is the PIN, not the marker: storyhook's generator emitting
# a form storyhook's own --help rejects IS the F103 drift class in its
# highest-leverage file, so the correct response is a story against
# mikeydotio/storyhook. If the gate must be unblocked first, removing AGENTS.md
# from ROOT_GRAMMAR_FILES reds test_root_grammar_allowlist_is_pinned unless the
# same single-purpose commit updates the pin and links the upstream story —
# a deliberate, attributable coverage loss rather than a silent one.
#
# Decided by /council-vote (ranked-choice majority, C=2 A=1 B=0). Full audit
# trail: .council/age30-repo-root-scan-interface/DECISION.md

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO_ROOT/plugins/forge/bin/forge-contract-check.sh"

fail() { echo "$1" >&2; return 1; }

# The pinned scan set. Hand-maintained ON PURPOSE: a future root GEMINI.md is
# not scanned until someone adds it here, and test_root_grammar_allowlist_is_pinned
# makes that addition a deliberate, reviewed act rather than a silent one.
ROOT_GRAMMAR_FILES=(
    'AGENTS.md'
    'CLAUDE.md'
)

# Build the --file argv the real gate uses. Run from REPO_ROOT with
# repo-relative paths so the checker's rel_f prefix strip is a no-op and a
# violation renders as `AGENTS.md:144` — the path an author can actually open.
check_root_files() {
    local args=() f
    for f in "${ROOT_GRAMMAR_FILES[@]}"; do args+=(--file "$f"); done
    ( cd "$REPO_ROOT" && bash "$CHECK" "${args[@]}" 2>&1 )
}

# --- The pins: without these the oracles below can silently stop covering ----

# The oracles iterate ROOT_GRAMMAR_FILES, so dropping an entry makes them pass
# by covering less. This is the ONLY assertion that reds on that.
test_root_grammar_allowlist_is_pinned() {
    local actual; actual="$(printf '%s\n' "${ROOT_GRAMMAR_FILES[@]}" | sort | tr '\n' ' ')"
    if [ "$actual" != "AGENTS.md CLAUDE.md " ]; then
        fail "ROOT_GRAMMAR_FILES changed to: $actual
Widening or narrowing the grammar scan is a deliberate act. If you added a root
instruction file, update this pin in the same commit and say why. If you REMOVED
AGENTS.md to unblock a regenerated false positive, link the upstream storyhook
story here — see the header."
        return 1
    fi
}

# A pathspec matching nothing passes vacuously. This is the only assertion that
# reds on a rename, and it matters more than usual here: before AGE-30 the
# checker listed a nonexistent file in files_scanned while never reading it.
test_root_grammar_allowlist_entries_all_exist() {
    local f
    for f in "${ROOT_GRAMMAR_FILES[@]}"; do
        if [ ! -f "$REPO_ROOT/$f" ]; then
            fail "Pinned root instruction file does not exist: $f"
            return 1
        fi
    done
}

# --- The gate ---------------------------------------------------------------

test_real_root_instruction_files_are_clean() {
    local out rc=0
    out="$(check_root_files)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "checker did not run (exit $rc): $out"
        return 1
    fi
    local ok; ok="$(printf '%s' "$out" | jq -r '.ok')"
    if [ "$ok" != "true" ]; then
        fail "checker could not verify (ok=$ok): $(printf '%s' "$out" | jq -r '.display')"
        return 1
    fi
    local contract; contract="$(printf '%s' "$out" | jq -r '.contract_ok')"
    if [ "$contract" != "true" ]; then
        fail "Root instruction files document a storyhook grammar the live CLI rejects:
$(printf '%s' "$out" | jq -r '.display')
$(printf '%s' "$out" | jq -c '{verb_violations, relation_violations, subcommand_violations, stale_suppressions}')"
        return 1
    fi
}

# THE ANTI-VACUITY ORACLE. Exact MEMBERSHIP, not a count and not a floor.
#
# A count of 2 would still pass if the argv became `--file AGENTS.md --file
# README.md` — coverage silently moved onto a file this suite excluded by
# decision. And with no --file at all the checker falls back to DOCS_ROOT = the
# forge PLUGIN root and reports green over 29 plugin files, an input set nobody
# asked for. Naming the expected set is the only form that catches both.
test_scan_manifest_is_exactly_the_pinned_set() {
    local out rc=0
    out="$(check_root_files)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "checker did not run (exit $rc): $out"
        return 1
    fi
    local expected; expected="$(printf '%s\n' "${ROOT_GRAMMAR_FILES[@]}" | sort | tr '\n' ' ')"
    local actual; actual="$(printf '%s' "$out" | jq -r '[.files_scanned[]] | sort | join(" ")') "
    if [ "$actual" != "$expected" ]; then
        fail "files_scanned is not exactly the pinned set.
  expected: $expected
  actual:   $actual"
        return 1
    fi
}

# --- Effect oracles: prove detection, per file AND per spelling --------------
#
# "The root files are clean" passes today for free and would pass identically if
# the scan set were empty — it is NOT an oracle. These are: each plants a form
# the live CLI rejects into a COPY of a real pinned file and requires it to be
# reported, by file and by token.
#
# A COPY, never a symlink: `find -type f` does not match a symlink, so a
# symlinked fixture scans nothing and reports contract_ok:true — measured. A
# failed cp is also a rename detector, so it fails loud.
#
# `.ok == "true"` is asserted alongside contract_ok:false in every case. Omit it
# and every one of these passes on a machine with no `story` CLI, because
# ok:false carries contract_ok:false with it — the vacuous green this whole
# suite exists to make impossible.
plant_and_expect_violation() {
    local file="$1" payload="$2" jq_path="$3" want_token="$4"
    local fix; fix="$(mktemp -d)"
    if ! cp "$REPO_ROOT/$file" "$fix/$file"; then
        rm -rf "$fix"
        fail "could not copy $file into the fixture (renamed or unreadable?)"
        return 1
    fi
    printf '%s\n' "$payload" >> "$fix/$file"

    local out rc=0
    out="$( cd "$fix" && bash "$CHECK" --file "$file" 2>&1 )" || rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -rf "$fix"
        fail "checker did not run on $file (exit $rc): $out"
        return 1
    fi

    local ok; ok="$(printf '%s' "$out" | jq -r '.ok')"
    if [ "$ok" != "true" ]; then
        rm -rf "$fix"
        fail "checker could not verify $file (ok=$ok) — a live story CLI is required for this suite to mean anything"
        return 1
    fi
    local contract; contract="$(printf '%s' "$out" | jq -r '.contract_ok')"
    if [ "$contract" != "false" ]; then
        rm -rf "$fix"
        fail "planted drift in $file was NOT detected (contract_ok=$contract) for payload: $payload"
        return 1
    fi
    local got; got="$(printf '%s' "$out" | jq -r "$jq_path")"
    if [ "$got" != "$want_token" ]; then
        rm -rf "$fix"
        fail "planted drift in $file reported the wrong token: expected '$want_token', got '$got'"
        return 1
    fi
    # The reported path must be the bare name the caller passed, not re-rooted
    # under a directory the file does not live in.
    local gotfile; gotfile="$(printf '%s' "$out" | jq -r '[.verb_violations[], .subcommand_violations[]][0].file')"
    if [ "$gotfile" != "$file" ]; then
        rm -rf "$fix"
        fail "violation in $file was reported against path '$gotfile' — an author cannot open that"
        return 1
    fi
    rm -rf "$fix"
}

# The id-first form AGE-27 claim #2 named, in an inline span — the spelling the
# docs actually use, and the one Layer 3's fixed-string grep cannot hold.
test_detects_id_first_form_in_an_inline_span() {
    local f
    for f in "${ROOT_GRAMMAR_FILES[@]}"; do
        plant_and_expect_violation "$f" \
            'Close it with `story AGE-1 is done`.' \
            '.verb_violations[0].verb' 'AGE-1' || return 1
    done
}

# The same dead grammar inside a fenced block, where the unit is the whole LINE
# rather than a span. Both paths must reach the checker.
test_detects_id_first_form_inside_a_fence() {
    local f
    for f in "${ROOT_GRAMMAR_FILES[@]}"; do
        plant_and_expect_violation "$f" \
            '```bash
story HP-3 is done
```' \
            '.verb_violations[0].verb' 'HP-3' || return 1
    done
}

# A real verb with a subcommand the CLI does not have. `project` IS dispatchable,
# so this must be reported as a SUBCOMMAND violation, not an unknown verb — this
# is the exact rename (`project init` -> `project new`) that passed the guard
# unseen before AGE-17.
test_detects_a_dead_subcommand_under_a_real_verb() {
    local f
    for f in "${ROOT_GRAMMAR_FILES[@]}"; do
        plant_and_expect_violation "$f" \
            'Start with `story project init` first.' \
            '.subcommand_violations[0].subcommand' 'init' || return 1
    done
}

# --- Fence-latch canary -----------------------------------------------------
#
# Aimed at the compound risk in the header: AGENTS.md is GENERATED and carries
# 16 fence markers. If a regeneration ever lands an UNBALANCED fence, the file
# ends at fence depth > 0 and every following line is scanned WHOLE instead of
# span-by-span — which turns ordinary English into violations and reds this gate
# with a mystery failure nobody can place.
#
# The payload is a true English sentence, chosen because it is clean when
# span-scanned (it contains no backticks, so there is no span to check) but a
# violation when LINE-scanned (`;` is a shell separator, so `story data ...`
# parses as an invocation of the nonexistent verb `data`). Asserting it stays
# clean therefore pins "this file ends at fence depth 0" as a property, and reds
# on the unbalanced fence itself rather than on its downstream symptom.
test_pinned_files_end_at_fence_depth_zero() {
    local f
    for f in "${ROOT_GRAMMAR_FILES[@]}"; do
        local fix; fix="$(mktemp -d)"
        if ! cp "$REPO_ROOT/$f" "$fix/$f"; then
            rm -rf "$fix"
            fail "could not copy $f into the fixture"
            return 1
        fi
        printf 'Recovery; story data lives in a SQLite store.\n' >> "$fix/$f"

        local out rc=0
        out="$( cd "$fix" && bash "$CHECK" --file "$f" 2>&1 )" || rc=$?
        if [ "$rc" -ne 0 ]; then
            rm -rf "$fix"
            fail "checker did not run on $f (exit $rc): $out"
            return 1
        fi
        local ok; ok="$(printf '%s' "$out" | jq -r '.ok')"
        if [ "$ok" != "true" ]; then
            rm -rf "$fix"
            fail "checker could not verify $f (ok=$ok)"
            return 1
        fi
        local contract; contract="$(printf '%s' "$out" | jq -r '.contract_ok')"
        if [ "$contract" != "true" ]; then
            rm -rf "$fix"
            fail "$f does not end at fence depth 0 — an unbalanced fence is line-scanning
ordinary prose. Fix the fence; do NOT suppress the resulting violations.
$(printf '%s' "$out" | jq -c '.verb_violations')"
            return 1
        fi
        rm -rf "$fix"
    done
}

# --- The interface contract this suite depends on ---------------------------

# If a pinned file is renamed, the caller must be told rather than handed a
# quietly smaller scan. Pairs with the entries-all-exist pin above.
test_a_missing_named_file_is_a_hard_error() {
    local out rc=0
    out="$( cd "$REPO_ROOT" && bash "$CHECK" --file 'no-such-instruction-file.md' 2>&1 )" || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "checker did not run (exit $rc): $out"
        return 1
    fi
    local err; err="$(printf '%s' "$out" | jq -r '.error')"
    if [ "$err" != "missing_file" ]; then
        fail "a nonexistent --file must be a hard error, got error='$err'"
        return 1
    fi
    local n; n="$(printf '%s' "$out" | jq -r '.files_scanned | length')"
    if [ "$n" != "0" ]; then
        fail "files_scanned must not name a file that was never read (got $n entries)"
        return 1
    fi
}

# --- Runner ----------------------------------------------------------------

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()

echo "=== storyhook-contract-root ==="
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
