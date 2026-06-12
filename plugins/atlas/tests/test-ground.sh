#!/usr/bin/env bash
# Tests for `atlas-cli ground` — deterministic grounding packs for mappers.

_ground_fixture() {
    local repo
    repo=$(create_fixture_repo)
    mkdir -p "$repo/src/auth" "$repo/src/api"
    cat > "$repo/src/auth/service.py" <<'PY'
import os
from src.api import client

class AuthenticationService:
    def login(self):
        return client.send("login")

def helper():
    return AuthenticationService()
PY
    cat > "$repo/src/auth/tokens.py" <<'PY'
class TokenStore:
    pass
PY
    cat > "$repo/src/api/client.py" <<'PY'
from src.auth.service import AuthenticationService

def send(kind):
    return AuthenticationService
PY
    # Pad both dirs so partition yields two distinct modules (>15 total files)
    local i
    for i in 1 2 3 4 5 6 7; do
        seed_file "$repo" "src/auth/pad$i.txt"
        seed_file "$repo" "src/api/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

test_ground_returns_module_pack() {
    local repo
    repo=$(_ground_fixture)

    run_atlas "$repo" ground src-auth
    assert_exit_code 0 "$EXIT_CODE" "ground exits 0" || return 1
    assert_json_field "$OUTPUT" '.module.id' "src-auth" "module id" || return 1
    assert_json_contains "$OUTPUT" '[.files[].path]' "src/auth/service.py" \
        "module files listed" || return 1
    assert_json_field "$OUTPUT" '.files[0].blob | length' "40" \
        "files carry blob hashes" || return 1

    cleanup_fixture_repo "$repo"
}

test_ground_captures_imports() {
    local repo
    repo=$(_ground_fixture)

    run_atlas "$repo" ground src-auth
    local import_count
    import_count=$(echo "$OUTPUT" | \
        jq -r '.imports["src/auth/service.py"] | length')
    if [ "$import_count" -lt 2 ]; then
        echo "    FAIL: expected import lines captured, got $import_count"
        return 1
    fi

    cleanup_fixture_repo "$repo"
}

test_ground_ranks_symbols_with_fan_in() {
    local repo
    repo=$(_ground_fixture)

    run_atlas "$repo" ground src-auth
    assert_json_contains "$OUTPUT" '[.symbols[].name]' "AuthenticationService" \
        "definition candidate found" || return 1
    local fan_in
    fan_in=$(echo "$OUTPUT" | \
        jq -r '.symbols[] | select(.name == "AuthenticationService") | .fan_in')
    if [ "$fan_in" -lt 1 ]; then
        echo "    FAIL: AuthenticationService is referenced from src/api — fan_in should be >= 1, got $fan_in"
        return 1
    fi
    local top
    top=$(echo "$OUTPUT" | jq -r '.symbols[0].name')
    assert_eq "AuthenticationService" "$top" \
        "well-named, externally-referenced symbol ranks first" || return 1

    cleanup_fixture_repo "$repo"
}

test_ground_unknown_module() {
    local repo
    repo=$(_ground_fixture)

    run_atlas "$repo" ground no-such-module
    assert_exit_code 1 "$EXIT_CODE" "unknown module fails" || return 1
    assert_json_field "$OUTPUT" '.error' "unknown_module" "error code" || return 1

    cleanup_fixture_repo "$repo"
}
