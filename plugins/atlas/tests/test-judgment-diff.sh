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

# ── verify-set (judgment-cell verification) ─────────────────────────────────
test_verify_plan_lists_only_high_risk_unverified() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    run_atlas "$repo" judgment verify-set --plan
    assert_exit_code 0 "$EXIT_CODE" "verify-set --plan exits 0" || return 1
    [ "$(echo "$OUTPUT" | jq -r '.target_count')" -ge 1 ] \
        || { echo "    FAIL: expected >=1 in-scope target"; return 1; }
    # Only the falsifiable, high-consequence kinds — never soft prose or overview.
    local k
    for k in $(echo "$OUTPUT" | jq -r '.targets[].kind' | sort -u); do
        case "$k" in
            symbol.contract|symbol.load_bearing|module.gotchas) : ;;
            *) echo "    FAIL: out-of-scope kind planned: $k"; return 1 ;;
        esac
    done
    # Symbol targets carry a source location for the verifier to check against.
    echo "$OUTPUT" | jq -e '.targets[] | select(.symbol != null) | .file' >/dev/null 2>&1 \
        || { echo "    FAIL: a symbol target is missing its source file"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_verify_ingest_pass_stamps_by_key_and_collapses() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    run_atlas "$repo" judgment verify-set --plan
    local key
    key=$(echo "$OUTPUT" | jq -r '.targets[0].key')
    [ -n "$key" ] && [ "$key" != "null" ] || { echo "    FAIL: no target key"; return 1; }
    local out
    out=$(cd "$repo" && printf '[{"key":"%s","verdict":"pass"}]' "$key" \
        | python3 "$CLI" judgment verify-set 2>/dev/null)
    assert_json_field "$out" '.stamped' "1" "one verdict stamped" || return 1
    assert_json_field "$out" '.passed' "1" "as a pass" || return 1
    # The verdict is recorded under that exact judgment key.
    local v
    v=$(jq -r --arg k "$key" '.judgments[$k].verify.verdict' "$repo/docs/atlas/judgments.json")
    assert_eq "pass" "$v" "verify.verdict stamped on the cell by key" || return 1
    # Delta collapse: a cached pass is skipped on the next plan (no re-verify).
    run_atlas "$repo" judgment verify-set --plan
    local still
    still=$(echo "$OUTPUT" | jq -r --arg k "$key" '[.targets[].key] | index($k)')
    assert_eq "null" "$still" "a cached pass is skipped on the next plan" || return 1
    cleanup_fixture_repo "$repo"
}

test_verify_ingest_fail_is_surfaced_with_failures() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    run_atlas "$repo" judgment verify-set --plan
    local key
    key=$(echo "$OUTPUT" | jq -r '.targets[0].key')
    local out
    out=$(cd "$repo" && printf '[{"key":"%s","verdict":"fail","failures":["claims X but code does Y"]}]' "$key" \
        | python3 "$CLI" judgment verify-set 2>/dev/null)
    assert_json_field "$out" '.failed' "1" "fail recorded" || return 1
    assert_eq "$key" "$(echo "$out" | jq -r '.fail_keys[0]')" \
        "fail key surfaced for the protocol's directed re-judge" || return 1
    # The verifier's failures[] are preserved on the cell to direct the re-judge.
    local det
    det=$(jq -r --arg k "$key" '.judgments[$k].verify.failures[0]' "$repo/docs/atlas/judgments.json")
    assert_eq "claims X but code does Y" "$det" "verifier failures[] preserved on the cell" || return 1
    cleanup_fixture_repo "$repo"
}

test_verify_plan_empty_when_all_in_scope_pass() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # Stamp every in-scope target as pass, then re-plan: nothing left (delta empty).
    run_atlas "$repo" judgment verify-set --plan
    echo "$OUTPUT" | jq -c '[.targets[] | {key, verdict:"pass"}]' \
        | (cd "$repo" && python3 "$CLI" judgment verify-set >/dev/null 2>&1)
    run_atlas "$repo" judgment verify-set --plan
    assert_json_field "$OUTPUT" '.target_count' "0" "no targets once all in-scope cells pass" || return 1
    cleanup_fixture_repo "$repo"
}

test_verify_ingest_rejects_unknown_key() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    local out
    out=$(cd "$repo" && printf '[{"key":"symbol.contract/deadbeefdeadbeefdeadbeef","verdict":"pass"}]' \
        | python3 "$CLI" judgment verify-set 2>/dev/null)
    assert_json_field "$out" '.stamped' "0" "an unknown key is not stamped" || return 1
    assert_json_field "$out" '.rejected[0].reason' "unknown_key" "and is surfaced as rejected" || return 1
    cleanup_fixture_repo "$repo"
}

# ── Ledger v2 ───────────────────────────────────────────────────────────────
test_ledger_finalize_v2_blocks() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    # With a Judgment Cache present, finalize stamps version 2 + the blocks.
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/4"
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

test_ledger_is_v2_even_without_judgments() {
    local repo; repo=$(_diff_fixture)
    # v1 is retired (v2.1) — finalize stamps v2 even with no Judgment Cache,
    # deriving the structure block straight from the index.
    write_full_module_doc "$repo" "src" "src" "Service" "src/svc.py"
    run_atlas "$repo" ledger finalize --refresh-hashes
    local ledger="$repo/docs/atlas/atlas-ledger.json"
    assert_json_field "$(cat "$ledger")" '.version' "2" "no cache → still v2 (v1 retired)" || return 1
    assert_json_field "$(cat "$ledger")" '.structure.index_digest | type' "string" \
        "structure block is present without a Judgment Cache" || return 1
    cleanup_fixture_repo "$repo"
}

test_structure_digest_stable_across_body_edit() {
    local repo; repo=$(_diff_fixture)
    _fully_map "$repo"
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/4"
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
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/4"
    local d2
    d2=$(jq -r '.structure.symbols["src/svc.py"][] | select(.id|endswith("::Service")) | .signature_hash' \
        "$repo/docs/atlas/atlas-ledger.json")
    assert_eq "$d1" "$d2" "Service signature_hash stable across a body edit" || return 1
    cleanup_fixture_repo "$repo"
}

# ── edge.semantic key delta (item #6) ───────────────────────────────────────
# A two-module fixture so there is a genuine resolved CROSS-module edge:
# src-web.handle -> src-store.Store (a TYPE reference — the flat _diff_fixture is a
# single module, whose calls are intra-module and carry no edge.semantic cell).
_edge_diff_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/store" "$repo/src/web"
    cat > "$repo/src/store/db.py" <<'PY'
class Store:
    pass
PY
    cat > "$repo/src/web/handler.py" <<'PY'
from src.store.db import Store

def handle(req):
    return Store(req)
PY
    local i
    for i in 1 2 3 4 5 6 7; do
        seed_file "$repo" "src/store/pad$i.txt"
        seed_file "$repo" "src/web/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

test_edge_semantic_planned_then_clean_after_fill() {
    local repo; repo=$(_edge_diff_fixture)
    run_atlas "$repo" judgment diff
    local planned
    planned=$(echo "$OUTPUT" | jq '[.missing_keys[] | select(.kind=="edge.semantic")] | length')
    assert_eq "1" "$planned" "the cross-module edge plans one edge.semantic cell" || return 1
    # Filling every cell (edge.semantic included) reaches clean — zero LLM next pull.
    _fully_map "$repo"
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.clean' "true" "fully judged incl edge.semantic → clean" || return 1
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_rekeys_when_caller_body_changes() {
    local repo; repo=$(_edge_diff_fixture)
    run_atlas "$repo" judge-plan
    local k1
    k1=$(echo "$OUTPUT" | jq -r '.missing_keys[] | select(.kind=="edge.semantic") | .key')
    _fully_map "$repo"
    # Change ONLY the caller's body — the call still resolves to Store, but
    # handle's span_hash moves, so the cell must re-key (taxonomy: regenerates
    # when the calling code changes) and the old key orphans.
    cat > "$repo/src/web/handler.py" <<'PY'
from src.store.db import Store

def handle(req):
    checked = req
    return Store(checked)
PY
    commit_all "$repo" caller-body
    run_atlas "$repo" judgment diff
    local k2
    k2=$(echo "$OUTPUT" | jq -r '.missing_keys[] | select(.kind=="edge.semantic") | .key')
    { [ -n "$k2" ] && [ "$k2" != "$k1" ]; } \
        || { echo "    FAIL: a caller body change must re-key edge.semantic ($k1 -> $k2)"; return 1; }
    assert_json_contains "$OUTPUT" '.orphaned_keys' "$k1" "the old edge.semantic key orphans" || return 1
    cleanup_fixture_repo "$repo"
}

test_edge_semantic_orphaned_when_call_removed() {
    local repo; repo=$(_edge_diff_fixture)
    run_atlas "$repo" judge-plan
    local k1
    k1=$(echo "$OUTPUT" | jq -r '.missing_keys[] | select(.kind=="edge.semantic") | .key')
    _fully_map "$repo"
    # Drop the cross-module call entirely → the edge and its cell are gone.
    cat > "$repo/src/web/handler.py" <<'PY'
def handle(req):
    return req
PY
    commit_all "$repo" no-call
    run_atlas "$repo" judgment diff
    local nmiss
    nmiss=$(echo "$OUTPUT" | jq '[.missing_keys[] | select(.kind=="edge.semantic")] | length')
    assert_eq "0" "$nmiss" "no edge.semantic required once the call is removed" || return 1
    assert_json_contains "$OUTPUT" '.orphaned_keys' "$k1" "the removed edge's cell is orphaned" || return 1
    # …and prune drops it (keeps judgments.json from accreting dead cells).
    run_atlas "$repo" judgment prune
    assert_json_contains "$OUTPUT" '.pruned_keys' "$k1" "prune removes the orphaned edge.semantic cell" || return 1
    cleanup_fixture_repo "$repo"
}
