#!/usr/bin/env bash
# Tests for the tree-sitter helper backend (Wave 2) and its graceful fallback.
#
# atlas bundles no tree-sitter. The helper is an external structure-extraction
# binary emitting the JSON contract (symbols + scope-resolved call sites). These
# tests stand up a STUB helper that emits that contract for a known fixture —
# mocking the helper's DATA, never atlas's behavior: extract's real parse +
# resolve_edges run against it. They prove (a) the backend is used and stamped,
# (b) a scope-resolved call (`to`) promotes a corpus-ambiguous name to a
# resolved edge, (c) symbol ids match the regex backend, and that an absent or
# broken helper falls back to regex without error.

# Write an executable stub helper that emits the contract for the fixture's two
# `process` definitions and a call resolved (by `to`) to the api one — a call
# the regex backend can only mark ambiguous.
_write_stub_helper() {
    local path="$1"
    cat > "$path" <<'STUB'
#!/usr/bin/env python3
import json, sys
# Consume the newline-delimited path list on stdin (contract: we may ignore it
# and answer for the files we know).
sys.stdin.read()
print(json.dumps({
    "version": 1,
    "files": {
        "src/api.py": {
            "symbols": [
                {"name": "process", "kind": "func", "start_line": 1,
                 "end_line": 2, "signature": "def process(x)",
                 "visibility": "public"}
            ],
            "calls": []
        },
        "src/worker.py": {
            "symbols": [
                {"name": "process", "kind": "func", "start_line": 1,
                 "end_line": 2, "signature": "def process(y)",
                 "visibility": "public"}
            ],
            "calls": []
        },
        "src/caller.py": {
            "symbols": [
                {"name": "orchestrate", "kind": "func", "start_line": 1,
                 "end_line": 2, "signature": "def orchestrate()",
                 "visibility": "public"}
            ],
            "calls": [
                {"callee": "process", "line": 2,
                 "to": {"file": "src/api.py", "start_line": 1}}
            ]
        }
    }
}))
STUB
    chmod +x "$path"
}

_ts_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    cat > "$repo/src/api.py" <<'PY'
def process(x):
    return x
PY
    cat > "$repo/src/worker.py" <<'PY'
def process(y):
    return y
PY
    cat > "$repo/src/caller.py" <<'PY'
def orchestrate():
    return process(1)
PY
    local i
    for i in 1 2 3 4 5 6 7 8; do seed_file "$repo" "src/pad$i.txt"; done
    commit_all "$repo"
    echo "$repo"
}

test_treesitter_backend_used_and_stamped() {
    local repo; repo=$(_ts_fixture)
    local helper="$repo/ts-helper"; _write_stub_helper "$helper"

    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    assert_exit_code 0 "$EXIT_CODE" "extract exits 0 with helper" || return 1
    assert_json_field "$OUTPUT" '.backend.py' "tree-sitter" "python via tree-sitter" || return 1
    assert_json_field "$OUTPUT" '.degraded' "false" "not degraded when helper present" || return 1
    # The symbol record carries the tree-sitter provenance.
    local ext
    ext=$(jq -r '.symbols[] | select(.name=="orchestrate") | .extraction' \
        "$repo/.atlas/structure/index.json")
    assert_eq "tree-sitter" "$ext" "symbol extraction stamped tree-sitter" || return 1
    cleanup_fixture_repo "$repo"
}

test_scope_resolved_call_promotes_ambiguous_to_resolved() {
    local repo; repo=$(_ts_fixture)
    local helper="$repo/ts-helper"; _write_stub_helper "$helper"

    # Regex alone: `process` matches two defs → ambiguous.
    run_atlas "$repo" extract --backend regex
    local conf_regex
    conf_regex=$(jq -r '.edges[] | select(.from=="src/caller.py::orchestrate") | .confidence' \
        "$repo/.atlas/structure/index.json")
    assert_eq "ambiguous" "$conf_regex" "regex backend marks it ambiguous" || return 1

    # tree-sitter helper supplies `to` → the same call resolves.
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    local edge
    edge=$(jq -c '.edges[] | select(.from=="src/caller.py::orchestrate")' \
        "$repo/.atlas/structure/index.json")
    assert_json_field "$edge" '.confidence' "resolved" "scope-resolved call is resolved" || return 1
    assert_json_field "$edge" '.to' "src/api.py::process" "resolved to the api definition" || return 1
    cleanup_fixture_repo "$repo"
}

test_symbol_ids_match_across_backends() {
    local repo; repo=$(_ts_fixture)
    local helper="$repo/ts-helper"; _write_stub_helper "$helper"

    run_atlas "$repo" extract --backend regex
    local regex_ids
    regex_ids=$(jq -S '[.symbols[].id]' "$repo/.atlas/structure/index.json")
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    local ts_ids
    ts_ids=$(jq -S '[.symbols[].id]' "$repo/.atlas/structure/index.json")
    assert_eq "$regex_ids" "$ts_ids" "symbol ids identical across backends" || return 1
    cleanup_fixture_repo "$repo"
}

test_absent_helper_falls_back_to_regex() {
    local repo; repo=$(_ts_fixture)
    # No ATLAS_TS_HELPER, no tree-sitter on PATH inside the run: auto → regex.
    run_atlas "$repo" extract --backend auto
    assert_exit_code 0 "$EXIT_CODE" "auto backend exits 0 without a helper" || return 1
    assert_json_field "$OUTPUT" '.backend.py' "regex" "falls back to regex" || return 1
    assert_json_field "$OUTPUT" '.degraded' "false" "auto fallback is not degraded" || return 1
    cleanup_fixture_repo "$repo"
}

test_explicit_treesitter_without_helper_is_degraded() {
    local repo; repo=$(_ts_fixture)
    ATLAS_TS_HELPER="$repo/does-not-exist" run_atlas "$repo" extract --backend treesitter
    assert_exit_code 0 "$EXIT_CODE" "still produces a valid index" || return 1
    assert_json_field "$OUTPUT" '.backend.py' "regex" "degraded to regex" || return 1
    assert_json_field "$OUTPUT" '.degraded' "true" \
        "explicit treesitter without a helper flags degraded" || return 1
    cleanup_fixture_repo "$repo"
}

test_broken_helper_falls_back_cleanly() {
    local repo; repo=$(_ts_fixture)
    local helper="$repo/bad-helper"
    printf '#!/usr/bin/env bash\necho "not json at all"\n' > "$helper"
    chmod +x "$helper"
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend auto
    assert_exit_code 0 "$EXIT_CODE" "broken helper does not crash extract" || return 1
    assert_json_field "$OUTPUT" '.backend.py' "regex" "broken helper falls back to regex" || return 1
    cleanup_fixture_repo "$repo"
}

test_force_regex_ignores_present_helper() {
    local repo; repo=$(_ts_fixture)
    local helper="$repo/ts-helper"; _write_stub_helper "$helper"
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend regex
    assert_json_field "$OUTPUT" '.backend.py' "regex" "--backend regex forces regex" || return 1
    cleanup_fixture_repo "$repo"
}
