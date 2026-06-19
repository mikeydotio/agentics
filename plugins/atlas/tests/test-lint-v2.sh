#!/usr/bin/env bash
# Tests for lint v2 (Wave 6): L7 as a Structure-Index join, L15 (no unfilled
# judgment placeholders in a committed doc), L16 (a committed doc must equal its
# deterministic projection), and the status tier-3 divergence signal. All v2
# checks are gated on a Judgment Cache existing, so v1 maps are unaffected.

# Drive a fixture to a fully-mapped, lint-clean v2 state.
_v2_map() {
    local repo="$1"
    (cd "$repo" && python3 "$CLI" judge-plan \
        | jq -c '[.missing_keys[] | {key, kind, value:"judged prose"}]' \
        | python3 "$CLI" judgment ingest >/dev/null)
    run_atlas "$repo" project >/dev/null
    run_atlas "$repo" index rebuild >/dev/null
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/3" >/dev/null
}

_lint_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    cat > "$repo/src/svc.py" <<'PY'
class Service:
    def start(self):
        return _boot(1)

def _boot(x):
    return x
PY
    cat > "$repo/src/other.py" <<'PY'
from src.svc import _boot

def use():
    return _boot(2)
PY
    local i
    for i in 1 2 3 4 5; do seed_file "$repo" "src/pad$i.txt"; done
    commit_all "$repo"
    echo "$repo"
}

err_count() { echo "$1" | jq -r --arg c "$2" '[.errors[]? | select(.check==$c)] | length'; }
warn_count() { echo "$1" | jq -r --arg c "$2" '[.warnings[]? | select(.check==$c)] | length'; }

test_clean_v2_map_lints_ok() {
    local repo; repo=$(_lint_fixture); _v2_map "$repo"
    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '.ok' "true" "fully-mapped v2 map lints clean" || return 1
    assert_eq "0" "$(err_count "$OUTPUT" L15)" "no L15 placeholders" || return 1
    assert_eq "0" "$(err_count "$OUTPUT" L16)" "no L16 divergence" || return 1
    assert_eq "0" "$(warn_count "$OUTPUT" L7)" "no L7 join failures" || return 1
    cleanup_fixture_repo "$repo"
}

test_l15_flags_unfilled_placeholder() {
    local repo; repo=$(_lint_fixture)
    # Project WITHOUT judging → docs are all placeholders. Commit + finalize so
    # lint sees a v2 map.
    run_atlas "$repo" project >/dev/null
    run_atlas "$repo" index rebuild >/dev/null
    # Touch judgments.json into existence so v2 checks engage.
    echo '{"version":1,"judgments":{}}' > "$repo/docs/atlas/judgments.json"
    run_atlas "$repo" lint
    local l15; l15=$(err_count "$OUTPUT" L15)
    [ "$l15" -ge 1 ] || { echo "    FAIL: expected L15 on placeholder docs, got $l15"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_l16_flags_hand_edited_doc() {
    local repo; repo=$(_lint_fixture); _v2_map "$repo"
    # Hand-edit a derived doc's body.
    local doc="$repo/docs/atlas/modules/src.md"
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("## Type notes", "## Type notes\n\nTAMPERED.\n", 1))
PY
    run_atlas "$repo" lint
    local l16; l16=$(err_count "$OUTPUT" L16)
    [ "$l16" -ge 1 ] || { echo "    FAIL: expected L16 on hand-edited doc, got $l16"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_l7_join_flags_symbol_not_indexed_at_file() {
    local repo; repo=$(_lint_fixture); _v2_map "$repo"
    # Repoint a Public API row's symbol to one not defined in that file.
    local doc="$repo/docs/atlas/modules/src.md"
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("| `Service` |", "| `NoSuchSymbol` |", 1))
PY
    run_atlas "$repo" lint
    local l7; l7=$(warn_count "$OUTPUT" L7)
    [ "$l7" -ge 1 ] || { echo "    FAIL: expected L7 join failure, got $l7"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_status_tier3_on_divergence() {
    local repo; repo=$(_lint_fixture); _v2_map "$repo"
    commit_all "$repo" map
    local doc="$repo/docs/atlas/modules/src.md"
    python3 - "$doc" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("## Purpose", "## Purpose\n\nDIVERGED.\n", 1))
PY
    run_atlas "$repo" status
    assert_json_field "$OUTPUT" '.tier' "3" "divergence is tier 3" || return 1
    cleanup_fixture_repo "$repo"
}

test_v1_map_unaffected_by_v2_checks() {
    local repo; repo=$(_lint_fixture)
    # A v1-style hand-written doc, NO judgments.json → v2 checks must not fire.
    write_full_module_doc "$repo" "src" "src" "Service" "src/svc.py"
    run_atlas "$repo" index rebuild >/dev/null
    run_atlas "$repo" ledger finalize --refresh-hashes >/dev/null
    run_atlas "$repo" lint
    assert_eq "0" "$(err_count "$OUTPUT" L15)" "no L15 without a cache" || return 1
    assert_eq "0" "$(err_count "$OUTPUT" L16)" "no L16 without a cache" || return 1
    cleanup_fixture_repo "$repo"
}
