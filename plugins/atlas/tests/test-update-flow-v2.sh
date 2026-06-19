#!/usr/bin/env bash
# End-to-end test of the v2 `/atlas update` flow at the CLI layer (Wave 7):
#   extract -> judgment diff -> [judge ONLY the delta] -> ingest -> project
#   -> finalize -> lint
# Proves the headline economics: a pure body edit re-judges nothing; a real
# structural change re-judges only the affected cells while every other cached
# cell — and the doc it renders — is reused untouched.

_update_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth" "$repo/src/api"
    cat > "$repo/src/auth/service.py" <<'PY'
class AuthService:
    def login(self):
        return _sign(1)

def _sign(payload):
    return payload
PY
    cat > "$repo/src/api/client.py" <<'PY'
class ApiClient:
    def call(self):
        return 1
PY
    local i
    for i in 1 2 3 4 5 6 7; do
        seed_file "$repo" "src/auth/pad$i.txt"
        seed_file "$repo" "src/api/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

_judge_all() {
    (cd "$1" && python3 "$CLI" judge-plan \
        | jq -c '[.missing_keys[] | {key, kind, value:"judged"}]' \
        | python3 "$CLI" judgment ingest >/dev/null)
}

# Judge only the cells judgment diff reports as missing; echo how many.
_judge_delta() {
    local repo="$1" n
    n=$(cd "$repo" && python3 "$CLI" judgment diff | jq -r '.missing_count')
    (cd "$repo" && python3 "$CLI" judgment diff \
        | jq -c '[.missing_keys[] | {key, kind, value:"rejudged"}]' \
        | python3 "$CLI" judgment ingest >/dev/null)
    echo "$n"
}

_full_map() {
    local repo="$1"
    _judge_all "$repo"
    _reproject "$repo"
    commit_all "$repo" "atlas map"
}

# The deterministic tail of every flow: render, refresh the ledger (stamps final
# frontmatter), then rebuild the INDEX from that finalized frontmatter — order is
# load-bearing, exactly as the v1 protocol's finalize-then-index step.
_reproject() {
    local repo="$1"
    run_atlas "$repo" project >/dev/null
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/3" >/dev/null
    run_atlas "$repo" index rebuild >/dev/null
}

test_update_body_edit_rejudges_nothing() {
    local repo; repo=$(_update_fixture); _full_map "$repo"
    # Edit a body; signatures unchanged.
    cat > "$repo/src/auth/service.py" <<'PY'
class AuthService:
    def login(self):
        return _sign(987)

def _sign(payload):
    return payload + 0
PY
    commit_all "$repo" edit
    local n; n=$(_judge_delta "$repo")
    assert_eq "0" "$n" "a pure body edit re-judges ZERO cells" || return 1
    # Re-project + lint stays clean (pure re-projection at most).
    _reproject "$repo"
    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '.ok' "true" "map stays clean after body edit" || return 1
    cleanup_fixture_repo "$repo"
}

test_update_new_capability_rejudges_only_delta() {
    local repo; repo=$(_update_fixture); _full_map "$repo"
    local total_cells
    total_cells=$(cd "$repo" && python3 "$CLI" judge-plan | jq -r '.total_expected')

    # Add a new public method to ApiClient — a real structural change.
    cat > "$repo/src/api/client.py" <<'PY'
class ApiClient:
    def call(self):
        return 1

    def health(self):
        return "ok"
PY
    commit_all "$repo" feature
    local n; n=$(_judge_delta "$repo")
    # Some cells re-judge, but far fewer than a full remap.
    [ "$n" -ge 1 ] || { echo "    FAIL: a new capability should need judgment"; return 1; }
    [ "$n" -lt "$total_cells" ] || {
        echo "    FAIL: update judged $n of $total_cells — not a delta"; return 1; }

    run_atlas "$repo" project >/dev/null
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/3" >/dev/null
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.clean' "true" "clean again after updating the delta" || return 1
    cleanup_fixture_repo "$repo"
}

test_update_unrelated_doc_stays_byte_identical() {
    local repo; repo=$(_update_fixture); _full_map "$repo"
    local before; before=$(shasum "$repo/docs/atlas/modules/src-auth.md" | awk '{print $1}')

    # Change only the api module; auth is untouched.
    cat > "$repo/src/api/client.py" <<'PY'
class ApiClient:
    def call(self):
        return 1

    def health(self):
        return "ok"
PY
    commit_all "$repo" feature
    _judge_delta "$repo" >/dev/null
    run_atlas "$repo" project >/dev/null
    local after; after=$(shasum "$repo/docs/atlas/modules/src-auth.md" | awk '{print $1}')
    assert_eq "$before" "$after" "the unrelated auth doc is byte-identical" || return 1
    cleanup_fixture_repo "$repo"
}

test_update_signature_change_rejudges_one_contract() {
    local repo; repo=$(_update_fixture); _full_map "$repo"
    cat > "$repo/src/auth/service.py" <<'PY'
class AuthService:
    def login(self, mfa):
        return _sign(1)

def _sign(payload):
    return payload
PY
    commit_all "$repo" sig
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.missing_count' "1" "one cell re-judges" || return 1
    assert_json_field "$OUTPUT" '.by_kind["symbol.contract"]' "1" "and it is login's contract" || return 1
    cleanup_fixture_repo "$repo"
}
