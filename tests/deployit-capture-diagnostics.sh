#!/usr/bin/env bash
#
# AGE-35 — a deployit test that fails must SAY WHY.
#
# THE DEFECT THIS PINS
#
# `deployit-cli` and `deployit-release` each define a top-level `fail()` that
# prints its JSON diagnosis to STDOUT and exits 1. A test that captures one
# under `set -e` therefore dies AT the capture, with the diagnosis sealed inside
# the shell variable and never printed — 0 bytes on stdout and 0 bytes on
# stderr. The runner then reports a bare `FAIL (exit 1)` above an empty
# diagnostic block, so the failure is undiagnosable even from a complete log.
# That is why AGE-35's 2026-08-04 occurrence could never be explained.
#
# WHY THIS GUARD IS BEHAVIOURAL AND NOT A SOURCE-LEVEL CENSUS
#
# It was tried. A census keyed on the visible `out=$(python3 …/deployit-cli …)`
# shape found 9 files; running the suite under an injected failure found 18
# files that actually call a CLI, 12 of them silent. The census undercounts by
# five, because the defect has at least four invocation shapes and only the
# first is visible to any regex:
#
#   plain      out=$(python3 .../deployit-cli ...)
#   array      test-cli-rm.sh:87    CLI=(...) then out=$("${CLI[@]}" ...)
#   function   test-cli-preflight.sh:50   out=$(run_preflight)
#   discarded  test-release-tag-exists-omits-target.sh:28   ... >/dev/null
#
# Every miss is the variable-binding blind spot this repo has already been bitten
# by (AGE-34, AGE-57). So the property is measured, not parsed: inject a failure
# at the k-th CLI call and observe what the file does.
#
# WHY MEMBERSHIP IS PINNED RATHER THAN DISCOVERED
#
# Deciding "is this file covered?" by "did the shim fire?" is self-excluding: the
# membership predicate and the asserted predicate would be the same signal, so a
# renamed entrypoint, an added wrapper or an argv change silently empties the run
# set — and an empty sweep reports zero silent files as GREEN, a gate that
# verifies nothing while reporting success. Measured: grepping the suite for a
# hypothetical renamed entrypoint returns zero files. So the set is derived once
# and COMMITTED here, then enforced by set equality — the same shape as
# bounded-capture-guard's REGISTRY. A hand-maintained list needs someone to
# remember; a derived-then-pinned list makes the gate say when to re-derive.
#
# HOW TO RE-DERIVE after legitimately adding or changing a deployit test:
#   run this script; every arm prints the observed value it expected, so a red
#   arm hands you the replacement literal directly.
#
# VERDICT LETTERS, per (file, injection depth k):
#   L  the file failed AND its output names the injected cause   (the good case)
#   H  the file exited 0 — it EXPECTED a failure at that call and handled it
#   N  the shim never fired — the file makes fewer than k CLI calls
#   S  the file failed and did NOT name the cause                (the defect)
# S is never acceptable. An L that becomes an H is a swallow-fix — a real failure
# converted into a pass — and reds this guard by design.
#
# DELIBERATE LIMITS, recorded rather than discovered later (filed as AGE-60):
#   * The receipt only classifies paths a run actually EXECUTES. An unguarded
#     capture on an untaken branch is invisible here.
#   * 17 of the 35 candidate files never call a CLI at all and are unclassified.
#   * A future test reaching a CLI through a composed path containing neither
#     literal is never executed under the shim. Redesign trigger: a deployit test
#     is added that invokes a CLI without either literal appearing in the file.
#
# DO NOT "improve" coverage by running all 50 deployit tests instead of the
# narrowed 35. Narrowing is a SAFETY property, not an optimisation: the excluded
# files spawn 14 additional fixed-port backend servers (test-backend-healthz.sh
# pins PORT=18729), which would double this gate's exposure to still-open AGE-56.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
DEPLOYIT_TESTS="$REPO_ROOT/plugins/deployit/tests"
MAX_DEPTH=6

FAILED=0
note()   { printf '  %s\n' "$*"; }
ok()     { printf 'PASS  %s\n' "$*"; }
bad()    { printf 'FAIL  %s\n' "$*" >&2; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d /private/tmp/age35-capture.XXXXXX)" || {
    echo "cannot create work dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# --- the committed pins -----------------------------------------------------

# Candidate set: tracked deployit test files naming a CLI entrypoint. Used ONLY
# to decide which files to execute, never to classify them.
read -r -d '' PINNED_CANDIDATES <<'EOF' || true
test-appcast-module.sh
test-bootstrap-dirs.sh
test-cli-archive-build-number.sh
test-cli-archive-configuration.sh
test-cli-bump.sh
test-cli-classify-push-failure.sh
test-cli-config-sparkle.sh
test-cli-config-toolchain.sh
test-cli-deploy-autoprune.sh
test-cli-deploy-pr-automerge.sh
test-cli-deploy-pr-leave-open.sh
test-cli-deploy-release-wiring.sh
test-cli-detect-sparkle.sh
test-cli-posttest-spawn.sh
test-cli-preflight.sh
test-cli-publish-preserve-on-failure.sh
test-cli-redeploy.sh
test-cli-rm-pr-fallback.sh
test-cli-rm.sh
test-cli-sparkle-sign-required.sh
test-cli-sparkle-tool-resolution.sh
test-cli-stage-macos-no-sparkle-tools.sh
test-cli-stage-macos-sparkle.sh
test-cli-version.sh
test-cli-worktree-guard.sh
test-gc.sh
test-metadata-single-app.sh
test-metadata.sh
test-release-adhoc-signing.sh
test-release-appcast-asset.sh
test-release-context.sh
test-release-existing-tag.sh
test-release-gh-invocation.sh
test-release-tag-exists-omits-target.sh
test-release-version-resolution.sh
EOF

# Covered set with its per-depth verdict string for k=1..6. Derived by
# measurement, then committed.
read -r -d '' PINNED_VERDICTS <<'EOF' || true
LLNNNN test-bootstrap-dirs.sh
LHNNNN test-cli-bump.sh
LLLLNN test-cli-preflight.sh
LLLLLN test-cli-redeploy.sh
LHNNNN test-cli-rm-pr-fallback.sh
HHHHHL test-cli-rm.sh
LNNNNN test-cli-version.sh
LLHNNN test-gc.sh
LLLLNN test-release-appcast-asset.sh
LNNNNN test-release-context.sh
LLNNNN test-release-gh-invocation.sh
LLNNNN test-release-tag-exists-omits-target.sh
LLLNNN test-cli-deploy-release-wiring.sh
LLHHNN test-cli-worktree-guard.sh
LNNNNN test-metadata-single-app.sh
LNNNNN test-metadata.sh
LLNNNN test-release-adhoc-signing.sh
LLNNNN test-release-existing-tag.sh
EOF

# The two entrypoints the shim impersonates.
read -r -d '' PINNED_ENTRYPOINTS <<'EOF' || true
deployit-cli
deployit-release
EOF

# --- arm 1: the entrypoint set is derived, not assumed ----------------------
#
# An entrypoint qualifies iff it defines a top-level fail() that prints and then
# exits — that is the shape whose diagnosis a capture can swallow. Keying on
# `"ok": False` markers instead would be wrong: deployit-backend carries 17 of
# them and has no top-level fail(), because those are HTTP response payloads.

derive_entrypoints() {
    local f
    for f in "$REPO_ROOT"/plugins/deployit/bin/*; do
        [ -f "$f" ] || continue
        if awk '/^def fail\(/ {infn=1; next}
                infn && /^[a-zA-Z@]/ {infn=0}
                infn && /print\(/ {p=1}
                infn && /sys\.exit\(/ && p {found=1}
                END {exit !found}' "$f"; then
            basename "$f"
        fi
    done | sort
}

observed_entrypoints="$(derive_entrypoints)"
if [ "$observed_entrypoints" = "$(printf '%s\n' "$PINNED_ENTRYPOINTS" | sort)" ]; then
    ok "entrypoint set is exactly the pinned pair"
else
    bad "the set of bin/ entrypoints with a stdout-printing fail() changed.
      pinned:   $(printf '%s' "$PINNED_ENTRYPOINTS" | tr '\n' ' ')
      observed: $(printf '%s' "$observed_entrypoints" | tr '\n' ' ')
      A new entrypoint of this shape needs covering: add it to PINNED_ENTRYPOINTS
      and to the shim's case arm, then re-derive the verdict table."
fi

# --- arm 2: the candidate set is pinned -------------------------------------

observed_candidates="$(
    cd "$REPO_ROOT" &&
    git ls-files 'plugins/deployit/tests/test-*.sh' |
        xargs grep -l 'deployit-cli\|deployit-release' |
        xargs -n1 basename | sort
)"
if [ "$observed_candidates" = "$(printf '%s\n' "$PINNED_CANDIDATES" | sort)" ]; then
    ok "candidate set is the pinned $(printf '%s\n' "$PINNED_CANDIDATES" | grep -c .) files"
else
    bad "the set of deployit tests naming a CLI entrypoint changed.
$(diff <(printf '%s\n' "$PINNED_CANDIDATES" | sort) <(printf '%s\n' "$observed_candidates") \
      | sed 's/^/      /')
      A new one means a new file may carry an unguarded capture. Re-derive."
fi

# --- the oracle -------------------------------------------------------------
#
# argv-aware: it impersonates a CLI only when one is actually being invoked, and
# forwards every other python3 call to the real interpreter, so tests that use
# python3 for their own assertions are unaffected.

REAL_PYTHON3="$(command -v python3)"
[ -n "$REAL_PYTHON3" ] || { echo "python3 not found" >&2; exit 1; }
mkdir -p "$WORK/bin"
SENTINEL="AGE35-INJECTED-CAUSE-b7f21c"
cat > "$WORK/bin/python3" <<EOF
#!/bin/bash
for a in "\$@"; do
  case "\$a" in
    */deployit-cli|*/deployit-release)
      n=0; [ -s "\$AGE35_COUNT" ] && n=\$(cat "\$AGE35_COUNT")
      n=\$((n + 1)); printf '%s' "\$n" > "\$AGE35_COUNT"
      if [ "\$n" -eq "\$AGE35_K" ]; then
        printf 'fired\n' >> "\$AGE35_RECEIPT"
        printf '{\n  "ok": false,\n  "display": "$SENTINEL"\n}\n'
        exit 1
      fi
      exec "$REAL_PYTHON3" "\$@" ;;
  esac
done
exec "$REAL_PYTHON3" "\$@"
EOF
chmod +x "$WORK/bin/python3"

# One (file, depth) probe. Echoes a single verdict letter.
probe() {
    local file="$1" k="$2" rc=0
    : > "$WORK/receipt"; : > "$WORK/count"
    AGE35_K="$k" AGE35_COUNT="$WORK/count" AGE35_RECEIPT="$WORK/receipt" \
        PATH="$WORK/bin:$PATH" bash "$DEPLOYIT_TESTS/$file" > "$WORK/out" 2>&1 || rc=$?
    if [ ! -s "$WORK/receipt" ]; then printf 'N'
    elif [ "$rc" -eq 0 ];        then printf 'H'
    elif grep -q "$SENTINEL" "$WORK/out"; then printf 'L'
    else printf 'S'; fi
}

# --- arm 3: sanity — the oracle can distinguish silence from a diagnosis -----
#
# Without this, every arm below could be passing because the shim never fires and
# `N` is indistinguishable from a correct result. A synthetic pair proves the
# probe reports L for a file that explains itself and S for one that does not.

mk_synthetic() {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$2" > "$WORK/$1"
}
mk_synthetic loud.sh \
  'out=$(python3 "'"$REPO_ROOT"'/plugins/deployit/bin/deployit-cli" --version) || { echo "cause: $out"; exit 1; }'
mk_synthetic quiet.sh \
  'out=$(python3 "'"$REPO_ROOT"'/plugins/deployit/bin/deployit-cli" --version)'
syn_verdict() {
    local rc=0
    : > "$WORK/receipt"; : > "$WORK/count"
    AGE35_K=1 AGE35_COUNT="$WORK/count" AGE35_RECEIPT="$WORK/receipt" \
        PATH="$WORK/bin:$PATH" bash "$WORK/$1" > "$WORK/out" 2>&1 || rc=$?
    if [ ! -s "$WORK/receipt" ]; then printf 'N'
    elif [ "$rc" -eq 0 ];        then printf 'H'
    elif grep -q "$SENTINEL" "$WORK/out"; then printf 'L'
    else printf 'S'; fi
}
syn_loud="$(syn_verdict loud.sh)"
syn_quiet="$(syn_verdict quiet.sh)"
if [ "$syn_loud" = "L" ] && [ "$syn_quiet" = "S" ]; then
    ok "oracle discriminates: guarded capture reports L, unguarded reports S"
else
    bad "the oracle cannot tell a diagnosis from silence, so every verdict below
      is meaningless. Expected L/S from the synthetic pair, observed
      $syn_loud/$syn_quiet. Fix the shim before trusting this gate."
fi

# --- arm 4: the covered set is discovered, not assumed -----------------------
#
# k=1 is swept over ALL candidates, not just the pinned ones. That is what keeps
# this arm from being vacuous: iterating the pinned list and then comparing the
# result to that same list is self-consistent by construction, so deleting a row
# would delete it from both sides and pass. (Measured — an earlier draft did
# exactly that, and mutation M2 walked straight through it.) Sweeping the
# candidates independently means a pinned file that stops firing, and an
# unpinned file that starts, both red.

covered_observed="$WORK/covered"
: > "$covered_observed"
declare -a FIRST_VERDICT_FILE=() FIRST_VERDICT_LETTER=()
while read -r file; do
    [ -n "${file:-}" ] || continue
    v="$(probe "$file" 1)"
    [ "$v" = "N" ] && continue
    printf '%s\n' "$file" >> "$covered_observed"
    FIRST_VERDICT_FILE+=("$file")
    FIRST_VERDICT_LETTER+=("$v")
done <<< "$PINNED_CANDIDATES"

pinned_covered="$(printf '%s\n' "$PINNED_VERDICTS" | awk 'NF {print $2}' | sort)"
if [ "$(sort "$covered_observed")" = "$pinned_covered" ]; then
    ok "covered set is the pinned $(printf '%s\n' "$pinned_covered" | grep -c .) files"
else
    bad "the set of deployit tests that actually invoke a CLI changed:
$(diff <(printf '%s\n' "$pinned_covered") <(sort "$covered_observed") | sed 's/^/      /')
      A file that stopped firing is no longer covered — check the shim still
      matches it. A file that started firing needs a pinned verdict row."
fi

# --- arm 5: every covered file matches its pinned verdict string -------------

observed_table="$WORK/observed"
: > "$observed_table"
for i in "${!FIRST_VERDICT_FILE[@]}"; do
    file="${FIRST_VERDICT_FILE[$i]}"
    verdicts="${FIRST_VERDICT_LETTER[$i]}"
    seen_n=0
    for k in $(seq 2 "$MAX_DEPTH"); do
        if [ "$seen_n" -eq 1 ]; then
            # Once a file makes fewer than k calls it makes fewer than k+1 too,
            # so the remaining depths are N without paying to re-run the file.
            verdicts="${verdicts}N"; continue
        fi
        v="$(probe "$file" "$k")"
        [ "$v" = "N" ] && seen_n=1
        verdicts="${verdicts}${v}"
    done
    printf '%s %s\n' "$verdicts" "$file" >> "$observed_table"
done
sort -k2 -o "$observed_table" "$observed_table"
PINNED_VERDICTS="$(printf '%s\n' "$PINNED_VERDICTS" | sort -k2)"

if diff -q <(printf '%s\n' "$PINNED_VERDICTS") "$observed_table" >/dev/null 2>&1; then
    ok "all $(printf '%s\n' "$PINNED_VERDICTS" | grep -c .) covered files match their pinned verdicts across k=1..$MAX_DEPTH"
else
    bad "a covered file's behaviour under an injected CLI failure changed:
$(diff <(printf '%s\n' "$PINNED_VERDICTS") "$observed_table" | sed 's/^/      /')
      S anywhere means a failure that explains nothing — the AGE-35 defect.
      L becoming H means a real failure was converted into a pass.
      L becoming N means the file stopped calling a CLI, so it is no longer
      covered and the shim may have stopped matching."
fi

# --- verdict ----------------------------------------------------------------

echo
if [ "$FAILED" -eq 0 ]; then
    echo "deployit-capture-diagnostics: all arms passed"
    exit 0
fi
echo "deployit-capture-diagnostics: $FAILED arm(s) failed" >&2
exit 1
