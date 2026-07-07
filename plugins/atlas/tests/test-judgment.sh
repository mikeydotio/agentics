#!/usr/bin/env bash
# Tests for the Judgment Cache, the orthogonal-hash keys, judge-plan, and
# judgment ingest (Wave 3). The first four tests are the CORRECTNESS CRUX of
# atlas v2: they prove each judgment kind invalidates on exactly the change that
# affects it, so a pure body edit re-judges nothing (zero-LLM re-projection).

# A fixture with one public class (→ contract), one underscore-private helper
# referenced cross-file (→ load_bearing candidate), and two callers of it.
_judgment_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    cat > "$repo/src/core.py" <<'PY'
class PublicAPI:
    def run(self):
        return _Engine(1)

class _Engine:
    pass
PY
    cat > "$repo/src/caller.py" <<'PY'
from src.core import _Engine

def use_Engine():
    return _Engine(2)
PY
    local i
    for i in 1 2 3 4 5 6; do seed_file "$repo" "src/pad$i.txt"; done
    commit_all "$repo"
    echo "$repo"
}

# plan_key <repo> <kind> <symbol-id-or-module>  → the judgment key (from the
# all-missing plan). Symbol cells match on .symbol; module cells on .module.
plan_key() {
    run_atlas "$1" judge-plan
    echo "$OUTPUT" | jq -r --arg k "$2" --arg a "$3" \
        '.missing_keys[] | select(.kind==$k and ((.symbol // .module)==$a)) | .key' \
        | head -1
}

# ── CRUX 1: a pure body edit changes NO contract key ────────────────────────
test_body_edit_keeps_contract_key() {
    local repo; repo=$(_judgment_fixture)
    local before; before=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    [ -n "$before" ] || { echo "    FAIL: no contract key for PublicAPI"; return 1; }

    # Change PublicAPI.run's BODY; its declaration is untouched.
    cat > "$repo/src/core.py" <<'PY'
class PublicAPI:
    def run(self):
        return _Engine(99999)

class _Engine:
    pass
PY
    commit_all "$repo" body
    local after; after=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    assert_eq "$before" "$after" "contract key STABLE across a pure body edit" || return 1
    cleanup_fixture_repo "$repo"
}

# ── CRUX 2: a signature edit DOES change the contract key ────────────────────
test_signature_edit_changes_contract_key() {
    local repo; repo=$(_judgment_fixture)
    local before; before=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")

    # Change the class declaration (add a base) — the interface changed.
    cat > "$repo/src/core.py" <<'PY'
class PublicAPI(object):
    def run(self):
        return _Engine(1)

class _Engine:
    pass
PY
    commit_all "$repo" decl
    local after; after=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    [ "$before" != "$after" ] || {
        echo "    FAIL: contract key should change when the declaration changes"; return 1; }
    cleanup_fixture_repo "$repo"
}

# ── CRUX 3: a new caller changes load_bearing but NOT contract ───────────────
test_new_caller_changes_load_bearing_not_contract() {
    local repo; repo=$(_judgment_fixture)
    local lb0; lb0=$(plan_key "$repo" symbol.load_bearing "src/core.py::_Engine")
    local c0;  c0=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    [ -n "$lb0" ] || { echo "    FAIL: _Engine should be a load_bearing candidate"; return 1; }

    # Append a PRIVATE caller of _Engine to an existing file: no new public
    # surface, no new module — only _Engine's resolved-caller set grows.
    cat >> "$repo/src/caller.py" <<'PY'

def _also():
    return _Engine(3)
PY
    commit_all "$repo" caller
    local lb1; lb1=$(plan_key "$repo" symbol.load_bearing "src/core.py::_Engine")
    local c1;  c1=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")

    [ "$lb0" != "$lb1" ] || {
        echo "    FAIL: load_bearing key should change when a resolved caller is added"; return 1; }
    assert_eq "$c0" "$c1" "contract key UNCHANGED by a new caller" || return 1
    cleanup_fixture_repo "$repo"
}

# ── CRUX 4: reordering functions does NOT change module.purpose ─────────────
test_reorder_keeps_module_purpose_key() {
    local repo; repo=$(_judgment_fixture)
    local before; before=$(plan_key "$repo" module.purpose "src")

    # Swap the order of the two top-level definitions in core.py.
    cat > "$repo/src/core.py" <<'PY'
class _Engine:
    pass

class PublicAPI:
    def run(self):
        return _Engine(1)
PY
    commit_all "$repo" reorder
    local after; after=$(plan_key "$repo" module.purpose "src")
    assert_eq "$before" "$after" "module.purpose key STABLE across symbol reordering" || return 1
    cleanup_fixture_repo "$repo"
}

# ── judge-plan + ingest mechanics ───────────────────────────────────────────
test_judge_plan_all_missing_on_fresh_repo() {
    local repo; repo=$(_judgment_fixture)
    run_atlas "$repo" judge-plan
    assert_exit_code 0 "$EXIT_CODE" "judge-plan exits 0" || return 1
    local total missing present
    total=$(echo "$OUTPUT" | jq -r '.total_expected')
    missing=$(echo "$OUTPUT" | jq -r '.missing_count')
    present=$(echo "$OUTPUT" | jq -r '.present_count')
    assert_eq "$total" "$missing" "every cell is missing on a fresh repo" || return 1
    assert_eq "0" "$present" "nothing present yet" || return 1
    cleanup_fixture_repo "$repo"
}

test_ingest_marks_keys_present() {
    local repo; repo=$(_judgment_fixture)
    local key; key=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")

    printf '[{"key":"%s","kind":"symbol.contract","value":"Owns the public entry point","provenance":{"model":"test","generator":"cartographer/3"}}]' \
        "$key" | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)

    assert_file_exists "$repo/docs/atlas/judgments.json" "judgments.json written" || return 1
    run_atlas "$repo" judge-plan
    local present_for_key
    present_for_key=$(echo "$OUTPUT" | jq -r --arg k "$key" \
        '[.missing_keys[].key] | index($k) == null')
    assert_eq "true" "$present_for_key" "ingested key no longer missing" || return 1
    assert_json_field "$OUTPUT" '.present_count' "1" "one present cell" || return 1
    cleanup_fixture_repo "$repo"
}

test_ingest_stores_value_and_provenance() {
    local repo; repo=$(_judgment_fixture)
    local key; key=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    printf '[{"key":"%s","kind":"symbol.contract","value":"The contract prose","provenance":{"model":"m"}}]' \
        "$key" | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)

    local stored verdict commit
    stored=$(jq -r --arg k "$key" '.judgments[$k].value' "$repo/docs/atlas/judgments.json")
    verdict=$(jq -r --arg k "$key" '.judgments[$k].verify.verdict' "$repo/docs/atlas/judgments.json")
    commit=$(jq -r --arg k "$key" '.judgments[$k].provenance.created_at_commit' "$repo/docs/atlas/judgments.json")
    assert_eq "The contract prose" "$stored" "value stored" || return 1
    assert_eq "unverified" "$verdict" "default verdict is unverified" || return 1
    [ "${#commit}" -ge 7 ] || { echo "    FAIL: created_at_commit not stamped"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_ingest_rejects_malformed_cells() {
    local repo; repo=$(_judgment_fixture)
    # Missing value; and a key whose prefix disagrees with kind.
    printf '[{"key":"symbol.contract/abc","kind":"symbol.contract"},{"key":"module.purpose/x","kind":"symbol.contract","value":"v"}]' \
        | (cd "$repo" && python3 "$CLI" judgment ingest) > /tmp/atlas-ingest-out.$$ 2>/dev/null
    local out; out=$(cat /tmp/atlas-ingest-out.$$); rm -f /tmp/atlas-ingest-out.$$
    assert_json_field "$out" '.ingested' "0" "no malformed cell ingested" || return 1
    assert_json_field "$out" '.rejected | length' "2" "both cells rejected" || return 1
    cleanup_fixture_repo "$repo"
}

test_ingest_is_canonical_and_idempotent() {
    local repo; repo=$(_judgment_fixture)
    local key; key=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    local payload
    payload=$(printf '[{"key":"%s","kind":"symbol.contract","value":"v","provenance":{"created_at_commit":"fixed"}}]' "$key")
    echo "$payload" | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)
    local h1; h1=$(shasum "$repo/docs/atlas/judgments.json" | awk '{print $1}')
    echo "$payload" | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)
    local h2; h2=$(shasum "$repo/docs/atlas/judgments.json" | awk '{print $1}')
    assert_eq "$h1" "$h2" "re-ingesting identical cells is byte-stable" || return 1
    cleanup_fixture_repo "$repo"
}

test_signature_edit_restales_only_that_contract() {
    local repo; repo=$(_judgment_fixture)
    # Ingest contract for PublicAPI, then change ITS signature → it re-stales,
    # while the cached cell stays in the file under its old key (not lost).
    local key; key=$(plan_key "$repo" symbol.contract "src/core.py::PublicAPI")
    printf '[{"key":"%s","kind":"symbol.contract","value":"v"}]' "$key" \
        | (cd "$repo" && python3 "$CLI" judgment ingest >/dev/null)

    cat > "$repo/src/core.py" <<'PY'
class PublicAPI(object):
    def run(self):
        return _Engine(1)

class _Engine:
    pass
PY
    commit_all "$repo" decl
    run_atlas "$repo" judge-plan
    local now_missing
    now_missing=$(echo "$OUTPUT" | jq -r \
        '[.missing_keys[] | select(.symbol=="src/core.py::PublicAPI" and .kind=="symbol.contract")] | length')
    assert_eq "1" "$now_missing" "the changed symbol's contract re-stales" || return 1
    # The old cell is still cached (re-projection of unchanged docs stays free).
    local still_there
    still_there=$(jq -r --arg k "$key" '.judgments[$k].value' "$repo/docs/atlas/judgments.json")
    assert_eq "v" "$still_there" "old cached cell is retained under its old key" || return 1
    cleanup_fixture_repo "$repo"
}
