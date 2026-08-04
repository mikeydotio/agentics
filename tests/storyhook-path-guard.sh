#!/usr/bin/env bash
# tests/storyhook-path-guard.sh — the retired per-repo storyhook path must not
# come back.
#
# WHY: storyhook 1.0.0 (2026-07-29) moved every project's story data into ONE
# SQLite store outside the repository. A repo carries exactly one storyhook
# artifact — the committed pointer file `.storyhook.toml`, which names the
# project's uuid and prefix and holds no story state. `story help storage` is
# the authoritative statement of this.
#
# Nine shipped forge sites did not get the memo (AGE-11). Three of them ran
#
#     forge-step-exit.sh ... --extra-path <retired-dir>
#
# and forge-step-exit.sh silently skips an --extra-path that isn't on disk, so
# all three were dead no-ops that failed silently for over a year while
# `references/handoff-format.md` told every agent story state was
# version-controlled with the repo. Nothing was ever red.
#
# That is the defect class this guard kills: a path that cannot exist, asserted
# in shipped instructions an LLM executes literally, with no failure mode.
#
# TWO LAYERS, deliberately different in scope:
#
#   Layer 1 — the invocation form. No --extra-path may name the retired path,
#     in ANY spelling, ANYWHERE in the repository. This layer is exceptionless:
#     there is no legitimate reason to write it, so it has zero false positives
#     by construction. It matches the unslashed spelling too — `<retired>` and
#     `<retired>/` are the same git pathspec, and a trailing-slash-only pattern
#     would repeat AGE-17's mistake exactly (a guard that inspected only a
#     command's first token missed a subcommand rename for months).
#
#   Layer 2 — the bare path name in SHIPPED content only, reusing
#     tests/plugin-content-drift.sh's own definition of "shipped" rather than
#     inventing a second one. Test harnesses and *.bats are excluded because an
#     install never reads them, and that exclusion is load-bearing: it preserves
#     historical rationale comments that name the retired path precisely in
#     order to DENY it (e.g. plugins/forge/bin/forge-crash-recover.bats explains
#     why its fixture no longer builds one). Deleting those would remove the
#     institutional memory that stops the myth being reintroduced.
#
# The retired name is assembled from fragments below rather than written out,
# so this file does not trip its own Layer 2 scan. The alternative — exempting
# this file — would make it the one place in the repo where the myth may be
# restated freely, which is the reservoir Layer 2 exists to drain.
#
# Self-contained plain-bash harness (NO bats) so it always runs under the
# pre-push gate — mirrors tests/plugin-versions.sh and
# tests/plugin-content-drift.sh: define test_* functions, run each in an
# isolated subshell, print "  PASS|FAIL  fn", exit with the failure count.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "$1" >&2; return 1; }

# Assembled, not literal — see the header. Concatenation happens at parse time;
# these hold the real strings at run time.
RETIRED_BARE=".story""hook"
RETIRED_DIR="${RETIRED_BARE}/"

# Layer 1: `--extra-path` (space- or =-separated) followed by any token that
# contains the retired name, slash or not, quoted or not.
L1_PATTERN="--extra-path[=[:space:]][^[:space:]]*${RETIRED_BARE}"

# Shipped runtime pathspec — kept identical to tests/plugin-content-drift.sh's
# SHIPPED_PATHSPEC. If that one changes, change this one with it: the two are
# meant to answer the same question ("what does an install actually read?").
SHIPPED_PATHSPEC=(
    'plugins/'
    ':(exclude,glob)plugins/*/tests/**'   # test harnesses never run from an install
    ':(exclude,glob)plugins/**/*.bats'    # bats also live in plugins/*/bin, plugins/*/lib
    ':(exclude,glob)plugins/*/README.md'  # GitHub-facing docs, not read at runtime
)

# Layer 3 pathspec — repo-root agent-instruction files. Layer 2's scope is
# `plugins/` only, which is exactly how the myth escaped it: AGE-27 found the
# retired directory asserted in repo-root AGENTS.md and .gitignore, neither of
# which any earlier layer reads.
#
# An ALLOWLIST, not a blanket root scan, and the distinction is load-bearing in
# the same way Layer 2's exclusions are. CHANGELOG.md (release history),
# PROGRESS.md (this backlog's own analysis of the bug) and .planning/ all name
# the retired path legitimately — a blanket scan would red on documents that are
# CORRECT, which is the guard shape AGE-11's council rejected unanimously:
# a guard you can satisfy by deleting true sentences is the wrong guard.
#
# Hand-maintained on purpose. A future root GEMINI.md or .cursorrules is not
# scanned until someone adds it here, and test_layer3_allowlist_is_pinned makes
# that addition a deliberate, reviewed act rather than a silent one.
ROOT_INSTRUCTION_PATHSPEC=(
    'AGENTS.md'
    'CLAUDE.md'
    'README.md'
    '.gitignore'
)

# The retired SURFACES a root instruction file must never assert. Each is a
# fixed string (git grep -F), assembled rather than written out for the same
# reason as RETIRED_BARE above. Layer 3's job is eradicating known-dead names,
# not parsing grammar.
#
# Deliberately NOT here: the id-first form (`story <id> is done`, AGE-27 claim
# #2). It is pattern-shaped rather than a fixed string, so it belongs to the
# grammar guard — forge-contract-check.sh — whose scan set does not yet reach
# repo-root files. That is AGE-30, blocked on AGE-24 and AGE-29.
RETIRED_MCP="mcp-""config"
RETIRED_SURFACES=("$RETIRED_DIR" "$RETIRED_MCP")

# --- Detectors (work on any repo root; used by the real checks + fixtures) ---

# git grep exits 1 on "no match", which is the success case here — swallow it
# so `set -e` inside a test function doesn't abort before the assertion.
layer1_hits() {
    git -C "$1" grep -nIE -e "$L1_PATTERN" -- . 2>/dev/null || true
}

layer2_hits() {
    git -C "$1" grep -nIF -e "$RETIRED_DIR" -- "${SHIPPED_PATHSPEC[@]}" 2>/dev/null || true
}

# One -e per retired surface: git grep ORs them, so a single pass reports every
# dead assertion in the allowlisted root files.
layer3_hits() {
    local args=() s
    for s in "${RETIRED_SURFACES[@]}"; do args+=(-e "$s"); done
    git -C "$1" grep -nIF "${args[@]}" -- "${ROOT_INSTRUCTION_PATHSPEC[@]}" 2>/dev/null || true
}

# --- Fixture ---------------------------------------------------------------

# A throwaway repo shaped like the marketplace: one plugin with shipped content
# (a skill, a reference doc, a hook script), plus the three shapes Layer 2
# excludes. Files are `git add`ed but not committed — git grep reads tracked
# working-tree files, which is all the detectors need.
make_fixture() {
    local fix
    fix="$(mktemp -d)"
    mkdir -p "$fix/plugins/alpha/skills/alpha" \
             "$fix/plugins/alpha/references" \
             "$fix/plugins/alpha/hooks" \
             "$fix/plugins/alpha/bin" \
             "$fix/plugins/alpha/tests"
    printf 'clean skill\n'     > "$fix/plugins/alpha/skills/alpha/SKILL.md"
    printf 'clean reference\n' > "$fix/plugins/alpha/references/topic.md"
    printf 'clean hook\n'      > "$fix/plugins/alpha/hooks/hook.sh"
    printf 'clean harness\n'   > "$fix/plugins/alpha/tests/test-tool.sh"
    printf 'clean bats\n'      > "$fix/plugins/alpha/bin/tool.bats"
    printf 'clean readme\n'    > "$fix/plugins/alpha/README.md"
    git -C "$fix" init -q
    git -C "$fix" add -A
    echo "$fix"
}

# A throwaway repo shaped like this one's ROOT: the four allowlisted
# instruction files, plus the three shapes Layer 3 must not scan because they
# name retired surfaces legitimately (release history, this backlog's own
# analysis of the bug, and planning docs).
make_root_fixture() {
    local fix
    fix="$(mktemp -d)"
    mkdir -p "$fix/.planning"
    printf 'clean agents doc\n'   > "$fix/AGENTS.md"
    printf 'clean claude doc\n'   > "$fix/CLAUDE.md"
    printf 'clean readme\n'       > "$fix/README.md"
    printf 'node_modules/\n'      > "$fix/.gitignore"
    printf 'clean changelog\n'    > "$fix/CHANGELOG.md"
    printf 'clean progress\n'     > "$fix/PROGRESS.md"
    printf 'clean plan\n'         > "$fix/.planning/HARNESS-PLAN.md"
    git -C "$fix" init -q
    git -C "$fix" add -A
    echo "$fix"
}

# --- Layer 1: real repo ----------------------------------------------------

test_no_extra_path_names_the_retired_storyhook_path() {
    local hits; hits="$(layer1_hits "$REPO_ROOT")"
    if [ -n "$hits" ]; then
        fail "--extra-path may never name storyhook's retired per-repo directory: it has not
        existed since storyhook 1.0.0, and forge-step-exit.sh SILENTLY SKIPS a path that is not
        on disk, so the call is a no-op that can never fail (AGE-11). Story state lives in a
        store outside the repository — there is nothing to commit. Delete the flag.
        Offending lines:
$hits"
    fi
}

# --- Layer 2: real repo ----------------------------------------------------

test_shipped_content_does_not_name_the_retired_storyhook_path() {
    local hits; hits="$(layer2_hits "$REPO_ROOT")"
    if [ -n "$hits" ]; then
        fail "shipped plugin content names storyhook's retired per-repo directory. A repository
        carries only the .storyhook.toml pointer file; story data lives in storyhook's own store
        (\`story help storage\`). Shipped content is read at runtime by agents that act on it
        literally, so a retired path here becomes a wrong instruction (AGE-11). Excluded from
        this scan on purpose: plugins/*/tests/**, **/*.bats, plugins/*/README.md — historical
        rationale comments that name the path in order to deny it belong there.
        Offending lines:
$hits"
    fi
}

# --- Layer 3: real repo ----------------------------------------------------

test_root_instruction_files_do_not_assert_retired_storyhook_surfaces() {
    local hits; hits="$(layer3_hits "$REPO_ROOT")"
    if [ -n "$hits" ]; then
        fail "a repo-root agent-instruction file asserts a storyhook surface that no longer
        exists. These files are read by agents BY CONVENTION, unprompted, so a wrong instruction
        here reaches agents that never load a plugin skill (AGE-27). There is no per-repo
        storyhook directory (\`story help storage\`) and no MCP server — storyhook has one
        interface, the CLI. Not scanned, on purpose: CHANGELOG.md, PROGRESS.md and .planning/,
        which name these surfaces legitimately in order to record or deny them.
        Offending lines:
$hits"
    fi
}

# --- Layer 3 detector: effect oracles + scope proofs ------------------------
#
# Same AGE-18 discipline as Layer 1: prove the detector can actually hit, in
# every allowlisted file and for every retired surface, before trusting a
# "no hits" result on the real repo.

test_layer3_detects_every_retired_surface_in_every_allowlisted_file() {
    local fix f s
    for f in "${ROOT_INSTRUCTION_PATHSPEC[@]}"; do
        for s in "${RETIRED_SURFACES[@]}"; do
            fix="$(make_root_fixture)"
            printf 'commit %s to keep project state with the repo\n' "$s" >> "$fix/$f"
            git -C "$fix" add -A
            [ -n "$(layer3_hits "$fix")" ] || {
                rm -rf "$fix"
                fail "Layer 3 missed retired surface '$s' in allowlisted root file $f"
            }
            rm -rf "$fix"
        done
    done
}

test_layer3_does_not_scan_files_that_name_retired_surfaces_legitimately() {
    local fix f s
    for f in CHANGELOG.md PROGRESS.md .planning/HARNESS-PLAN.md; do
        for s in "${RETIRED_SURFACES[@]}"; do
            fix="$(make_root_fixture)"
            printf 'the retired %s was removed in storyhook 1.0.0 — recorded so it stays dead\n' \
                "$s" >> "$fix/$f"
            git -C "$fix" add -A
            local hits; hits="$(layer3_hits "$fix")"
            [ -z "$hits" ] || {
                rm -rf "$fix"
                fail "Layer 3 wrongly flagged $f. That exclusion is load-bearing: release
        history and this backlog's own bug analysis must be able to NAME a retired surface in
        order to record or deny it. A guard you can satisfy by deleting true sentences is the
        wrong guard (AGE-11 council, unanimous). Hits: $hits"
            }
            rm -rf "$fix"
        done
    done
}

test_layer3_ignores_the_pointer_file() {
    local fix; fix="$(make_root_fixture)"
    printf 'a repo carries only %s.toml, the committed pointer file — commit it\n' \
        "$RETIRED_BARE" >> "$fix/AGENTS.md"
    git -C "$fix" add -A
    local hits; hits="$(layer3_hits "$fix")"
    [ -z "$hits" ] || fail "Layer 3 must not match the live pointer file: it carries no trailing
        slash and IS version-controlled. Flagging it would tell agents to delete the one
        storyhook artifact a repo genuinely owns. Hits: $hits"
    rm -rf "$fix"
}

# The allowlist is hand-maintained, so pin it. Adding or removing a scanned file
# is a coverage change and must be a deliberate, reviewed edit — not something
# that happens silently in an unrelated diff.
test_layer3_allowlist_is_pinned() {
    local actual expected
    actual="$(printf '%s\n' "${ROOT_INSTRUCTION_PATHSPEC[@]}" | sort | tr '\n' ' ')"
    expected="$(printf '%s\n' AGENTS.md CLAUDE.md README.md .gitignore | sort | tr '\n' ' ')"
    [ "$actual" = "$expected" ] || fail "Layer 3's allowlist changed. Expected: $expected
        Got: $actual
        If you are ADDING a root agent-instruction file, update this pin in the same commit and
        say why in the message. If you are REMOVING one, you are removing coverage."
}

# A rename must drop coverage LOUDLY. Without this, renaming AGENTS.md leaves
# the pathspec silently matching nothing and Layer 3 reports a clean pass over
# a file that no longer exists — the vacuous green this repo has fought three
# times (AGE-16, AGE-18, AGE-21).
test_layer3_allowlist_entries_all_exist() {
    local f missing=""
    for f in "${ROOT_INSTRUCTION_PATHSPEC[@]}"; do
        [ -e "$REPO_ROOT/$f" ] || missing="$missing $f"
    done
    [ -z "$missing" ] || fail "Layer 3 allowlist names files that do not exist:$missing
        A pathspec matching nothing passes vacuously. Either restore the file or remove it from
        ROOT_INSTRUCTION_PATHSPEC and its pin, deliberately."
}

# --- Layer 1 detector: effect oracles --------------------------------------
#
# AGE-18's lesson: a check that asserts "no hits" is satisfied perfectly by a
# detector that can never hit. Each spelling gets its own proof.

test_layer1_detects_the_slashed_spelling() {
    local fix; fix="$(make_fixture)"
    printf -- 'run tool --extra-path %s\n' "$RETIRED_DIR" >> "$fix/plugins/alpha/skills/alpha/SKILL.md"
    git -C "$fix" add -A
    [ -n "$(layer1_hits "$fix")" ] || fail "Layer 1 missed the slashed --extra-path spelling"
    rm -rf "$fix"
}

test_layer1_detects_the_unslashed_spelling() {
    local fix; fix="$(make_fixture)"
    printf -- 'run tool --extra-path %s\n' "$RETIRED_BARE" >> "$fix/plugins/alpha/skills/alpha/SKILL.md"
    git -C "$fix" add -A
    [ -n "$(layer1_hits "$fix")" ] || fail "Layer 1 missed the UNSLASHED spelling — this is the
        AGE-17 failure mode: the two are the same git pathspec, so a trailing-slash-only pattern
        lets the relapse straight through"
    rm -rf "$fix"
}

test_layer1_detects_the_equals_spelling() {
    local fix; fix="$(make_fixture)"
    printf -- 'run tool --extra-path=%s\n' "$RETIRED_DIR" >> "$fix/plugins/alpha/skills/alpha/SKILL.md"
    git -C "$fix" add -A
    [ -n "$(layer1_hits "$fix")" ] || fail "Layer 1 missed the --extra-path=<path> spelling, which
        forge-step-exit.sh accepts (see its --extra-path=* case)"
    rm -rf "$fix"
}

test_layer1_detects_it_inside_a_test_harness_too() {
    local fix; fix="$(make_fixture)"
    printf -- 'run tool --extra-path %s\n' "$RETIRED_DIR" >> "$fix/plugins/alpha/bin/tool.bats"
    git -C "$fix" add -A
    [ -n "$(layer1_hits "$fix")" ] || fail "Layer 1 must be repo-wide: unlike Layer 2 it has no
        exclusions, because a dead flag in a .bats is still a dead flag being asserted"
    rm -rf "$fix"
}

test_layer1_ignores_a_legitimate_extra_path() {
    local fix; fix="$(make_fixture)"
    printf -- 'run tool --extra-path tests/new_test.sh --extra-path docs/\n' \
        >> "$fix/plugins/alpha/skills/alpha/SKILL.md"
    git -C "$fix" add -A
    local hits; hits="$(layer1_hits "$fix")"
    [ -z "$hits" ] || fail "Layer 1 flagged a legitimate --extra-path: $hits"
    rm -rf "$fix"
}

# --- Layer 2 detector: effect oracles + exclusion proofs -------------------

test_layer2_detects_it_in_shipped_content() {
    local fix f
    for f in skills/alpha/SKILL.md references/topic.md hooks/hook.sh; do
        fix="$(make_fixture)"
        printf 'story data lives in %s\n' "$RETIRED_DIR" >> "$fix/plugins/alpha/$f"
        git -C "$fix" add -A
        [ -n "$(layer2_hits "$fix")" ] || fail "Layer 2 missed the retired path in shipped $f"
        rm -rf "$fix"
    done
}

test_layer2_ignores_the_three_unshipped_shapes() {
    local fix f
    for f in tests/test-tool.sh bin/tool.bats README.md; do
        fix="$(make_fixture)"
        printf 'the retired %s no longer exists — this is why the fixture does not build one\n' \
            "$RETIRED_DIR" >> "$fix/plugins/alpha/$f"
        git -C "$fix" add -A
        local hits; hits="$(layer2_hits "$fix")"
        [ -z "$hits" ] || fail "Layer 2 wrongly flagged unshipped $f — that exclusion is
        load-bearing: it is what preserves historical rationale comments that name the retired
        path in order to deny it. Hits: $hits"
        rm -rf "$fix"
    done
}

test_layer2_ignores_the_pointer_file_and_the_jq_field() {
    local fix; fix="$(make_fixture)"
    {
        printf 'a repo carries only %s.toml, the committed pointer file\n' "$RETIRED_BARE"
        printf 'jq reads .story%s_consecutive_failures from state.json\n' "hook"
    } >> "$fix/plugins/alpha/references/topic.md"
    git -C "$fix" add -A
    local hits; hits="$(layer2_hits "$fix")"
    [ -z "$hits" ] || fail "Layer 2 must not match the live pointer file or the
        storyhook_consecutive_failures jq path — neither carries the trailing slash. Hits: $hits"
    rm -rf "$fix"
}

# --- Runner ----------------------------------------------------------------

command -v git >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()

echo "=== storyhook-path-guard ==="
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
