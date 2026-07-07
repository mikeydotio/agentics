#!/usr/bin/env bash
# Tests for `atlas-cli extract` edge resolution (Wave 2) — the confidence-tier
# engine the judgment-key model depends on. resolved (unique name) / ambiguous
# (>1 def) / unresolved (0 defs, dropped) / self-edge skip, and the
# resolved-only incident_edge_digest that keeps load-bearing keys stable.

# The well-known sha256 of the empty string — the incident digest of a symbol
# with no RESOLVED callers (every regex-only symbol, and any with only
# ambiguous callers).
EMPTY_DIGEST="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

_edge_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src"
    # A uniquely-named TYPE, constructed once → resolved (a type name can't shadow
    # a stdlib member). A uniquely-named FUNC → NOT resolved (a bare func name is a
    # guess: it can shadow an unseen stdlib member).
    cat > "$repo/src/a.py" <<'PY'
class UniqueType:
    pass

def unique_func(x):
    return x

def caller_one():
    return UniqueType()

def caller_func():
    return unique_func(1)
PY
    # `dup` defined in TWO files → a call to it is ambiguous.
    cat > "$repo/src/b.py" <<'PY'
def dup(v):
    return v
PY
    cat > "$repo/src/c.py" <<'PY'
def dup(v):
    return v + 1
PY
    cat > "$repo/src/d.py" <<'PY'
def caller_two():
    return dup(2)
PY
    # Self-recursion → no self edge. A call to an undefined name → dropped.
    cat > "$repo/src/e.py" <<'PY'
def recurse(n):
    return recurse(n - 1)

def uses_external():
    return totally_undefined_symbol(9)
PY
    # A symbol nobody calls — its incident digest is the empty-set baseline.
    cat > "$repo/src/lonely.py" <<'PY'
def never_called(z):
    return z
PY
    local i
    for i in 1 2 3 4 5 6 7 8; do seed_file "$repo" "src/pad$i.txt"; done
    commit_all "$repo"
    echo "$repo"
}

_edges() { jq -c '.edges' "$1/.atlas/structure/index.json"; }
_digest() {
    jq -r --arg n "$2" \
        '.symbols[] | select(.name==$n) | .incident_edge_digest' \
        "$1/.atlas/structure/index.json"
}

test_resolved_edge_for_unique_type_name() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    local edge
    edge=$(_edges "$repo" | jq -c \
        '.[] | select(.from=="src/a.py::caller_one" and .to=="src/a.py::UniqueType")')
    [ -n "$edge" ] || { echo "    FAIL: missing caller_one->UniqueType edge"; return 1; }
    assert_json_field "$edge" '.confidence' "resolved" "unique TYPE name is resolved" || return 1
    assert_json_field "$edge" '.kind' "calls" "kind is calls" || return 1
    cleanup_fixture_repo "$repo"
}

test_unique_func_name_not_resolved() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    # A corpus-unique FUNC name is not name-resolved — it could shadow an unseen
    # stdlib member, so asserting a `calls` edge would be a guess (issue #65).
    local hits
    hits=$(_edges "$repo" | jq -c '[.[] | select(.from=="src/a.py::caller_func")] | length')
    assert_eq "0" "$hits" "a unique FUNC name produces no resolved edge" || return 1
    cleanup_fixture_repo "$repo"
}

test_ambiguous_edge_lists_all_candidates() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    local edge
    edge=$(_edges "$repo" | jq -c \
        '.[] | select(.from=="src/d.py::caller_two" and .confidence=="ambiguous")')
    [ -n "$edge" ] || { echo "    FAIL: caller_two->dup should be ambiguous"; return 1; }
    assert_json_field "$edge" '.to' "null" "ambiguous edge has no single target" || return 1
    assert_json_field "$edge" '.candidates | length' "2" "two candidates" || return 1
    assert_json_contains "$edge" '.candidates' "src/b.py::dup" "candidate b" || return 1
    assert_json_contains "$edge" '.candidates' "src/c.py::dup" "candidate c" || return 1
    cleanup_fixture_repo "$repo"
}

test_unresolved_call_is_dropped() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    local hit
    hit=$(_edges "$repo" | jq -c '[.[] | select(.from=="src/e.py::uses_external")] | length')
    assert_eq "0" "$hit" "call to an undefined name produces no edge" || return 1
    cleanup_fixture_repo "$repo"
}

test_self_recursion_skipped() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    local hit
    hit=$(_edges "$repo" | jq -c \
        '[.[] | select(.from=="src/e.py::recurse" and .to=="src/e.py::recurse")] | length')
    assert_eq "0" "$hit" "self-recursion is not an edge" || return 1
    cleanup_fixture_repo "$repo"
}

test_incident_digest_nonempty_for_resolved_caller() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    local d
    d=$(_digest "$repo" "UniqueType")
    [ "$d" != "$EMPTY_DIGEST" ] || {
        echo "    FAIL: UniqueType has a resolved caller — digest should be non-empty"
        return 1; }
    cleanup_fixture_repo "$repo"
}

test_incident_digest_empty_with_only_ambiguous_callers() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    # `dup` is defined twice and only ever called ambiguously → the resolved-only
    # digest of BOTH definitions stays empty, so an unrelated same-named def
    # elsewhere can't thrash either one's load-bearing key.
    local all_empty
    all_empty=$(jq -r --arg e "$EMPTY_DIGEST" \
        '[.symbols[] | select(.name=="dup") | .incident_edge_digest]
         | length==2 and all(. == $e)' \
        "$repo/.atlas/structure/index.json")
    assert_eq "true" "$all_empty" "ambiguous-only callers leave digest empty" || return 1
    cleanup_fixture_repo "$repo"
}

test_incident_digest_empty_for_uncalled_symbol() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract
    local d
    d=$(_digest "$repo" "never_called")
    assert_eq "$EMPTY_DIGEST" "$d" "an uncalled symbol has the empty digest" || return 1
    cleanup_fixture_repo "$repo"
}

test_edges_are_deterministic() {
    local repo; repo=$(_edge_fixture)
    run_atlas "$repo" extract --force
    local h1; h1=$(_edges "$repo" | shasum | awk '{print $1}')
    run_atlas "$repo" extract --force
    local h2; h2=$(_edges "$repo" | shasum | awk '{print $1}')
    assert_eq "$h1" "$h2" "edge list is byte-identical across rebuilds" || return 1
    cleanup_fixture_repo "$repo"
}
