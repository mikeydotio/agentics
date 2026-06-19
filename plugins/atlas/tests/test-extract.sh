#!/usr/bin/env bash
# Tests for `atlas-cli extract` — the deterministic Structure Index (Wave 1,
# regex backend). The load-bearing properties: correct spans, the three
# orthogonal per-symbol hashes behave independently, symbol-set parity with
# `ground`, caching, and byte-for-byte determinism.

# A two-module fixture mirroring test-ground.sh so symbol-set parity is checkable.
_extract_fixture() {
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
    local i
    for i in 1 2 3 4 5 6 7; do
        seed_file "$repo" "src/auth/pad$i.txt"
        seed_file "$repo" "src/api/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

# Extract JSON for one symbol by name (reads the written index, not the
# summary). $1=repo $2=symbol-name → object on stdout.
_sym() {
    jq -c --arg n "$2" '.symbols[] | select(.name == $n)' \
        "$1/.atlas/structure/index.json"
}

test_extract_writes_index_and_reports_summary() {
    local repo
    repo=$(_extract_fixture)

    run_atlas "$repo" extract
    assert_exit_code 0 "$EXIT_CODE" "extract exits 0" || return 1
    assert_json_field "$OUTPUT" '.ok' "true" "ok" || return 1
    assert_json_field "$OUTPUT" '.cached' "false" "fresh build is not cached" || return 1
    assert_json_field "$OUTPUT" '.backend["*"]' "regex" "regex backend" || return 1
    assert_json_field "$OUTPUT" '.module_count' "2" "two modules" || return 1
    assert_file_exists "$repo/.atlas/structure/index.json" "index written" || return 1

    cleanup_fixture_repo "$repo"
}

test_extract_symbol_has_three_orthogonal_hashes() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract

    local sym
    sym=$(_sym "$repo" "AuthenticationService")
    assert_json_field "$sym" '.id' "src/auth/service.py::AuthenticationService" \
        "id is path::name" || return 1
    assert_json_field "$sym" '.kind' "class" "kind" || return 1
    assert_json_field "$sym" '.visibility' "public" "visibility" || return 1
    assert_json_field "$sym" '.extraction' "regex" "extraction backend" || return 1
    # All three hashes present and sha256-prefixed.
    local sh ph ih
    sh=$(echo "$sym" | jq -r '.signature_hash'); ph=$(echo "$sym" | jq -r '.span_hash')
    ih=$(echo "$sym" | jq -r '.incident_edge_digest')
    [[ "$sh" == sha256:* && "$ph" == sha256:* && "$ih" == sha256:* ]] || {
        echo "    FAIL: hashes not sha256-prefixed: $sh $ph $ih"; return 1; }
    [ "$sh" != "$ph" ] || { echo "    FAIL: signature_hash == span_hash"; return 1; }

    cleanup_fixture_repo "$repo"
}

test_extract_span_encloses_method() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract

    local sym start end
    sym=$(_sym "$repo" "AuthenticationService")
    start=$(echo "$sym" | jq -r '.span.start_line')
    end=$(echo "$sym" | jq -r '.span.end_line')
    # `class AuthenticationService:` is line 4; the next top-level def (`helper`)
    # is line 8, so the class span is 4..7 — enclosing its `login` method.
    assert_eq "4" "$start" "class starts at line 4" || return 1
    assert_eq "7" "$end" "class span ends before the next top-level def" || return 1

    cleanup_fixture_repo "$repo"
}

test_span_hash_stable_across_unrelated_edit() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract
    local before
    before=$(_sym "$repo" "AuthenticationService" | jq -r '.span_hash')

    # Edit a DIFFERENT file entirely.
    cat >> "$repo/src/api/client.py" <<'PY'

def unrelated_addition():
    return 42
PY
    commit_all "$repo" "unrelated"
    run_atlas "$repo" extract --force
    local after
    after=$(_sym "$repo" "AuthenticationService" | jq -r '.span_hash')

    assert_eq "$before" "$after" \
        "span_hash unchanged when an unrelated file changes" || return 1
    cleanup_fixture_repo "$repo"
}

test_span_hash_changes_on_body_edit_signature_stable() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract
    local sig_before span_before
    sig_before=$(_sym "$repo" "AuthenticationService" | jq -r '.signature_hash')
    span_before=$(_sym "$repo" "AuthenticationService" | jq -r '.span_hash')

    # Change the BODY of the class (the login method) but NOT its declaration.
    cat > "$repo/src/auth/service.py" <<'PY'
import os
from src.api import client

class AuthenticationService:
    def login(self):
        return client.send("login-v2-different-body")

def helper():
    return AuthenticationService()
PY
    commit_all "$repo" "body edit"
    run_atlas "$repo" extract --force
    local sig_after span_after
    sig_after=$(_sym "$repo" "AuthenticationService" | jq -r '.signature_hash')
    span_after=$(_sym "$repo" "AuthenticationService" | jq -r '.span_hash')

    assert_eq "$sig_before" "$sig_after" \
        "signature_hash STABLE across a pure body edit" || return 1
    [ "$span_before" != "$span_after" ] || {
        echo "    FAIL: span_hash should change when the body changes"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_signature_hash_changes_on_declaration_edit() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract
    local before
    before=$(_sym "$repo" "AuthenticationService" | jq -r '.signature_hash')

    # Change the DECLARATION (add a base class) — the interface changed.
    cat > "$repo/src/auth/service.py" <<'PY'
import os
from src.api import client

class AuthenticationService(object):
    def login(self):
        return client.send("login")

def helper():
    return AuthenticationService()
PY
    commit_all "$repo" "decl edit"
    run_atlas "$repo" extract --force
    local after
    after=$(_sym "$repo" "AuthenticationService" | jq -r '.signature_hash')

    [ "$before" != "$after" ] || {
        echo "    FAIL: signature_hash should change when the declaration changes"
        return 1; }
    cleanup_fixture_repo "$repo"
}

test_extract_symbol_set_parity_with_ground() {
    local repo
    repo=$(_extract_fixture)

    # The set of definition names extract finds for src-auth must match ground's.
    run_atlas "$repo" ground src-auth
    local ground_names
    ground_names=$(echo "$OUTPUT" | jq -S '[.symbols[].name] | unique')
    run_atlas "$repo" extract --module src-auth
    local extract_names
    extract_names=$(echo "$OUTPUT" | jq -S '[.symbols[].name] | unique')

    assert_eq "$ground_names" "$extract_names" \
        "extract finds the same symbol names as ground for src-auth" || return 1
    cleanup_fixture_repo "$repo"
}

test_extract_captures_external_deps() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract
    # `os` is imported in service.py; it must surface as an external dep.
    local deps
    deps=$(jq -c '.external_deps' "$repo/.atlas/structure/index.json")
    assert_json_contains "$deps" '.' "os" "external dep os captured" || return 1
    cleanup_fixture_repo "$repo"
}

test_extract_skips_markdown_defs() {
    local repo
    repo=$(_extract_fixture)
    cat > "$repo/src/auth/NOTES.md" <<'MD'
from the start, auth notes live here.
module docs describe the service.

```python
def fenced_example():
    pass
```
MD
    commit_all "$repo" "notes"
    run_atlas "$repo" extract --force
    local names
    names=$(jq -c '[.symbols[].name]' "$repo/.atlas/structure/index.json")
    assert_json_not_contains "$names" '.' "fenced_example" \
        "no symbols from markdown prose" || return 1
    assert_json_not_contains "$names" '.' "docs" \
        "prose 'module docs' is not a symbol" || return 1
    cleanup_fixture_repo "$repo"
}

test_extract_caches_when_unchanged() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract
    assert_json_field "$OUTPUT" '.cached' "false" "first build" || return 1
    run_atlas "$repo" extract
    assert_json_field "$OUTPUT" '.cached' "true" \
        "second build with no change is served from cache" || return 1
    cleanup_fixture_repo "$repo"
}

test_extract_is_byte_identical_across_runs() {
    local repo
    repo=$(_extract_fixture)
    run_atlas "$repo" extract --force
    local h1
    h1=$(shasum "$repo/.atlas/structure/index.json" | awk '{print $1}')
    run_atlas "$repo" extract --force
    local h2
    h2=$(shasum "$repo/.atlas/structure/index.json" | awk '{print $1}')
    assert_eq "$h1" "$h2" "index.json is byte-identical across forced rebuilds" || return 1
    cleanup_fixture_repo "$repo"
}

test_extract_requires_git_repo() {
    local dir
    dir=$(mktemp -d "/tmp/atlas-tests-XXXXXX")
    run_atlas "$dir" extract
    assert_exit_code 1 "$EXIT_CODE" "extract fails outside a git repo" || return 1
    assert_json_field "$OUTPUT" '.error' "not_a_git_repo" "error code" || return 1
    cleanup_fixture_repo "$dir"
}
