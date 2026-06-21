#!/usr/bin/env bash
# Tests for the REAL atlas-ts-helper (plugins/atlas/helpers/ts-helper) driving
# atlas end-to-end on Swift fixtures. Unlike test-extract-treesitter.sh (which
# stubs the contract DATA to prove atlas's consumption), these run the actual
# tree-sitter parse + scope resolution and prove the precision win:
#   - an overloaded-name cross-file call becomes a `resolved` edge (vs the
#     `ambiguous` the regex floor must report),
#   - symbol ids are identical across the regex and tree-sitter backends,
#   - the backend is stamped and not degraded.
#
# tree-sitter is a compiled dependency the core suite must not require, so these
# tests SKIP (cleanly, exit 0) when no tree-sitter-capable Python is found. To
# run them, install the helper (see helpers/ts-helper/README.md) or point
# ATLAS_TS_HELPER_PYTHON at a Python that can `import tree_sitter_language_pack`.

TS_HELPER_MODULE="$PLUGIN_ROOT/helpers/ts-helper/atlas_ts_helper.py"

# Echo (only) a Python interpreter that can import the helper's grammar dep, or
# return 1. Caller idiom (skips cleanly when tree-sitter is absent):
#   local py; py=$(_ts_python) || { echo "    [skip] ..."; return 0; }
_ts_python() {
    local py
    for py in "${ATLAS_TS_HELPER_PYTHON:-}" python3; do
        [ -n "$py" ] || continue
        if "$py" -c "import tree_sitter_language_pack" >/dev/null 2>&1; then
            echo "$py"; return 0
        fi
    done
    return 1
}
TS_SKIP="    [skip] no tree-sitter Python (install helpers/ts-helper or set ATLAS_TS_HELPER_PYTHON)"

# _make_wrapper <python> <repo> — write an executable that runs the helper module
# under <python>, so atlas's $ATLAS_TS_HELPER probe finds a real, tree-sitter
# backed binary. Echoes its path.
_make_wrapper() {
    local py="$1" repo="$2" wrapper="$2/ts-helper-run"
    printf '#!/usr/bin/env bash\nexec "%s" "%s" "$@"\n' "$py" "$TS_HELPER_MODULE" > "$wrapper"
    chmod +x "$wrapper"
    echo "$wrapper"
}

# Two modules (two directories) so orchestrate->run is a genuine CROSS-module
# edge, with the callee name `run` deliberately OVERLOADED across two types in
# one file — the case the regex floor cannot disambiguate.
_swift_fixture() {
    local repo; repo=$(create_fixture_repo)
    mkdir -p "$repo/Sources/Engine" "$repo/Sources/Main"
    cat > "$repo/Sources/Engine/Engine.swift" <<'SW'
public final class Engine {
    public func run(_ x: Int) -> Int { return x }
}

public final class Pipeline {
    public func run(_ y: Int) -> Int { return y }
}
SW
    cat > "$repo/Sources/Main/Main.swift" <<'SW'
public func orchestrate() {
    let engine = Engine()
    engine.run(1)
    let pipeline = Pipeline()
    pipeline.run(2)
}
SW
    local i
    for i in 1 2 3 4 5 6 7 8; do
        seed_file "$repo" "Sources/Engine/pad$i.txt"
        seed_file "$repo" "Sources/Main/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

test_ts_helper_backend_used_and_not_degraded() {
    local py; py=$(_ts_python) || { echo "$TS_SKIP"; return 0; }
    local repo; repo=$(_swift_fixture)
    local helper; helper=$(_make_wrapper "$py" "$repo")
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    assert_exit_code 0 "$EXIT_CODE" "extract exits 0 with the real helper" || return 1
    assert_json_field "$OUTPUT" '.backend.swift' "tree-sitter" "swift via tree-sitter" || return 1
    assert_json_field "$OUTPUT" '.degraded' "false" "not degraded with the helper present" || return 1
    local ext
    ext=$(jq -r '.symbols[] | select(.name=="orchestrate") | .extraction' \
        "$repo/.atlas/structure/index.json")
    assert_eq "tree-sitter" "$ext" "swift symbol stamped tree-sitter provenance" || return 1
    cleanup_fixture_repo "$repo"
}

test_ts_helper_resolves_overloaded_cross_file_call() {
    local py; py=$(_ts_python) || { echo "$TS_SKIP"; return 0; }
    local repo; repo=$(_swift_fixture)
    local helper; helper=$(_make_wrapper "$py" "$repo")

    # Regex floor: `run` is defined in two types → the call is ambiguous.
    run_atlas "$repo" extract --backend regex
    local conf
    conf=$(jq -r '[.edges[] | select(.from|endswith("::orchestrate")) | select(.candidates!=null)][0].confidence' \
        "$repo/.atlas/structure/index.json")
    assert_eq "ambiguous" "$conf" "regex marks the overloaded call ambiguous" || return 1

    # Real helper: local-variable types resolve each call to its specific method,
    # so atlas emits a RESOLVED cross-module edge into Engine.swift.
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    local resolved
    resolved=$(jq -r '[.edges[] | select(.from|endswith("::orchestrate")) | select(.confidence=="resolved" and (.to|test("Engine.swift::run")))] | length' \
        "$repo/.atlas/structure/index.json")
    [ "$resolved" -ge 1 ] || {
        echo "    FAIL: expected a resolved orchestrate->Engine.run edge"
        jq -c '.edges[] | select(.from|endswith("::orchestrate"))' "$repo/.atlas/structure/index.json"
        return 1; }
    # And zero ambiguous edges remain from orchestrate (both calls resolved).
    local ambiguous
    ambiguous=$(jq -r '[.edges[] | select(.from|endswith("::orchestrate")) | select(.confidence=="ambiguous")] | length' \
        "$repo/.atlas/structure/index.json")
    assert_eq "0" "$ambiguous" "no ambiguous edges remain under tree-sitter" || return 1
    cleanup_fixture_repo "$repo"
}

test_ts_helper_symbol_ids_match_regex_backend() {
    local py; py=$(_ts_python) || { echo "$TS_SKIP"; return 0; }
    local repo; repo=$(_swift_fixture)
    local helper; helper=$(_make_wrapper "$py" "$repo")

    run_atlas "$repo" extract --backend regex
    local regex_ids
    regex_ids=$(jq -S '[.symbols[].id]' "$repo/.atlas/structure/index.json")
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    local ts_ids
    ts_ids=$(jq -S '[.symbols[].id]' "$repo/.atlas/structure/index.json")
    assert_eq "$regex_ids" "$ts_ids" "symbol ids identical across backends" || return 1
    cleanup_fixture_repo "$repo"
}

test_ts_helper_extracts_signature_and_visibility() {
    local py; py=$(_ts_python) || { echo "$TS_SKIP"; return 0; }
    local repo; repo=$(_swift_fixture)
    local helper; helper=$(_make_wrapper "$py" "$repo")
    ATLAS_TS_HELPER="$helper" run_atlas "$repo" extract --backend treesitter
    local idx="$repo/.atlas/structure/index.json"
    # The Engine class carries its real declaration signature + public visibility.
    assert_eq "public final class Engine" \
        "$(jq -r '.symbols[] | select(.name=="Engine") | .signature' "$idx")" \
        "Engine signature extracted from the parse" || return 1
    assert_eq "public" \
        "$(jq -r '.symbols[] | select(.name=="Engine") | .visibility' "$idx")" \
        "Engine visibility is public" || return 1
    cleanup_fixture_repo "$repo"
}

test_ts_helper_raw_contract_is_version_1() {
    local py; py=$(_ts_python) || { echo "$TS_SKIP"; return 0; }
    local repo; repo=$(_swift_fixture)
    # Drive the helper module directly and check the wire contract atlas requires.
    local out
    out=$(printf 'Sources/Engine/Engine.swift\n' \
        | "$py" "$TS_HELPER_MODULE" extract --root "$repo")
    assert_json_field "$out" '.version' "1" "contract version is 1" || return 1
    assert_json_field "$out" '.files["Sources/Engine/Engine.swift"].symbols | length' "4" \
        "Engine.swift yields 4 symbols (2 classes + 2 same-named run methods)" || return 1
    cleanup_fixture_repo "$repo"
}
