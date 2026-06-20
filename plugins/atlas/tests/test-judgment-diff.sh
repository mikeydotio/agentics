#!/usr/bin/env bash
# Tests for Ledger v2 + `judgment diff` (Wave 5) — the update engine. The
# headline proofs: after a full judge+project, a no-op pull needs ZERO LLM; a
# body edit needs zero LLM (pure re-projection at most); a public signature
# edit re-judges exactly that symbol's contract; and `ledger finalize` records
# the v2 structure + judgment_keys blocks.

_diff_fixture() {
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

# Drive the structure to a fully-judged, projected, committed state: ingest a
# value for every missing cell, project, commit.
_fully_map() {
    local repo="$1"
    (cd "$repo" && python3 "$CLI" judge-plan \
        | jq -c '[.missing_keys[] | {key, kind, value:"judged"}]' \
        | python3 "$CLI" judgment ingest >/dev/null)
    run_atlas "$repo" project >/dev/null
    commit_all "$repo" map
}

test_clean_after_full_map() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    run_atlas "$repo" judgment diff
    assert_exit_code 0 "$EXIT_CODE" "diff exits 0" || return 1
    assert_json_field "$OUTPUT" '.clean' "true" "fully-mapped repo is clean" || return 1
    assert_json_field "$OUTPUT" '.missing_count' "0" "no missing cells" || return 1
    assert_json_field "$OUTPUT" '.stale_doc_count' "0" "no stale docs" || return 1
    cleanup_fixture_repo "$repo"
}

test_noop_pull_is_zero_llm() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # A second look with no source change: nothing to judge, nothing to render.
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.clean' "true" "no-op pull is clean (ZERO LLM)" || return 1
    cleanup_fixture_repo "$repo"
}

test_body_edit_needs_zero_judgment() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # Change a function BODY (signature unchanged) — the canonical zero-LLM edit.
    cat > "$repo/src/svc.py" <<'PY'
class Service:
    def start(self):
        return _boot(1)

def _boot(x):
    return x * 1000 + 7
PY
    commit_all "$repo" body
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.missing_count' "0" \
        "a pure body edit needs ZERO new judgment" || return 1
    cleanup_fixture_repo "$repo"
}

test_public_signature_edit_restales_only_contract() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # Change the public class declaration — only its contract should re-judge,
    # NOT the module prose or overview (capability set is unchanged).
    cat > "$repo/src/svc.py" <<'PY'
class Service(object):
    def start(self):
        return _boot(1)

def _boot(x):
    return x
PY
    commit_all "$repo" sig
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.missing_count' "1" "exactly one cell re-judges" || return 1
    assert_json_field "$OUTPUT" '.by_kind["symbol.contract"]' "1" "and it is a contract" || return 1
    local who
    who=$(echo "$OUTPUT" | jq -r '.missing_keys[0].symbol')
    assert_eq "src/svc.py::Service" "$who" "the changed symbol's contract" || return 1
    cleanup_fixture_repo "$repo"
}

test_adding_public_symbol_restales_module_prose() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # A NEW public capability changes the module surface → module prose re-judges
    # (plus the new symbol's own contract).
    cat >> "$repo/src/svc.py" <<'PY'

class Extra:
    def ping(self):
        return 1
PY
    commit_all "$repo" add
    run_atlas "$repo" judgment diff
    local mods contracts
    mods=$(echo "$OUTPUT" | jq -r '.by_kind["module.purpose"] // 0')
    contracts=$(echo "$OUTPUT" | jq -r '.by_kind["symbol.contract"] // 0')
    assert_eq "1" "$mods" "module.purpose re-judges when a capability is added" || return 1
    [ "$contracts" -ge 1 ] || { echo "    FAIL: new symbol needs a contract"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_removing_symbol_orphans_its_cells() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # Delete `use` from other.py → its contract cell is no longer required.
    cat > "$repo/src/other.py" <<'PY'
from src.svc import _boot
PY
    commit_all "$repo" rm
    run_atlas "$repo" judgment diff
    local orphans
    orphans=$(echo "$OUTPUT" | jq -r '.orphaned_count')
    [ "$orphans" -ge 1 ] || { echo "    FAIL: removed symbol should orphan >=1 cached cell"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_prune_drops_orphaned_cells() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    local total_before
    total_before=$(jq '.judgments | length' "$repo/docs/atlas/judgments.json")
    # Delete `use` from other.py → its cached cell(s) are no longer required.
    cat > "$repo/src/other.py" <<'PY'
from src.svc import _boot
PY
    commit_all "$repo" rm
    run_atlas "$repo" judgment diff
    local orphans
    orphans=$(echo "$OUTPUT" | jq -r '.orphaned_count')
    [ "$orphans" -ge 1 ] || { echo "    FAIL: setup expected >=1 orphaned cell"; return 1; }
    # prune removes exactly the orphans the diff reported.
    run_atlas "$repo" judgment prune
    assert_exit_code 0 "$EXIT_CODE" "prune exits 0" || return 1
    assert_json_field "$OUTPUT" '.pruned_count' "$orphans" "prune drops exactly the orphans" || return 1
    # The cache shrank by exactly the orphan count — required cells survive.
    local total_after
    total_after=$(jq '.judgments | length' "$repo/docs/atlas/judgments.json")
    assert_eq "$((total_before - orphans))" "$total_after" "cache shrinks by the orphan count" || return 1
    # diff now sees zero orphans, and a second prune is a no-op (idempotent).
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.orphaned_count' "0" "no orphans remain after prune" || return 1
    run_atlas "$repo" judgment prune
    assert_json_field "$OUTPUT" '.pruned_count' "0" "second prune is a no-op" || return 1
    cleanup_fixture_repo "$repo"
}

test_prune_noop_when_nothing_orphaned() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # A fully-mapped repo with no source change has nothing to prune.
    run_atlas "$repo" judgment prune
    assert_exit_code 0 "$EXIT_CODE" "prune exits 0 on a clean cache" || return 1
    assert_json_field "$OUTPUT" '.pruned_count' "0" "nothing to prune when current" || return 1
    cleanup_fixture_repo "$repo"
}

# ── Ledger v2 ───────────────────────────────────────────────────────────────
test_ledger_finalize_v2_blocks() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # With a Judgment Cache present, finalize stamps version 2 + the blocks.
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/3"
    assert_exit_code 0 "$EXIT_CODE" "finalize exits 0" || return 1
    local ledger="$repo/docs/atlas/atlas-ledger.json"
    assert_json_field "$(cat "$ledger")" '.version' "2" "ledger is v2" || return 1
    assert_json_field "$(cat "$ledger")" '.structure.index_digest | type' "string" \
        "structure block has an index_digest" || return 1
    assert_json_field "$(cat "$ledger")" '.judgment_keys | type' "object" \
        "judgment_keys block present" || return 1
    # Each module doc records the keys it consumed.
    local keys
    keys=$(jq -r '.judgment_keys["docs/atlas/modules/src.md"] | length' "$ledger")
    [ "$keys" -ge 1 ] || { echo "    FAIL: src doc should record consumed keys"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_ledger_v1_unchanged_without_judgments() {
    local repo; repo=$(_diff_fixture)
    # No judgments.json → finalize stays v1 (back-compat).
    write_full_module_doc "$repo" "src" "src" "Service" "src/svc.py"
    run_atlas "$repo" ledger finalize --refresh-hashes
    local ledger="$repo/docs/atlas/atlas-ledger.json"
    assert_json_field "$(cat "$ledger")" '.version' "1" "no cache → v1 ledger" || return 1
    cleanup_fixture_repo "$repo"
}

test_structure_digest_stable_across_body_edit() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/3"
    local d1
    d1=$(jq -r '.structure.symbols["src/svc.py"][] | select(.id|endswith("::Service")) | .signature_hash' \
        "$repo/docs/atlas/atlas-ledger.json")
    cat > "$repo/src/svc.py" <<'PY'
class Service:
    def start(self):
        return _boot(123456)

def _boot(x):
    return x
PY
    commit_all "$repo" body
    _fully_map "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/3"
    local d2
    d2=$(jq -r '.structure.symbols["src/svc.py"][] | select(.id|endswith("::Service")) | .signature_hash' \
        "$repo/docs/atlas/atlas-ledger.json")
    assert_eq "$d1" "$d2" "Service signature_hash stable across a body edit" || return 1
    cleanup_fixture_repo "$repo"
}
