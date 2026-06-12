#!/usr/bin/env bash
# Shared test fixtures and assertion helpers for atlas tests.

# Paths to key executables under test
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$PLUGIN_ROOT/bin/atlas-cli"

# --- Fixture Helpers ---

# Create a throwaway git repo under /tmp (NOT $TMPDIR — Spotlight indexes it on
# macOS and file-heavy fixtures eventually stall test runs; /tmp is exempt).
create_fixture_repo() {
    local repo
    repo=$(mktemp -d "/tmp/atlas-tests-XXXXXX")

    git -C "$repo" init -q
    git -C "$repo" config user.name "Test"
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config commit.gpgsign false

    echo "$repo"
}

# seed_file <repo> <relpath> [bytes]
# Creates a file with deterministic content of approximately <bytes> length
# (default 100). Content is plain text — never triggers the binary sniff.
seed_file() {
    local repo="$1" relpath="$2" bytes="${3:-100}"
    local dir
    dir="$(dirname "$repo/$relpath")"
    mkdir -p "$dir"
    # Deterministic filler: repeat the path until the size is reached.
    python3 - "$repo/$relpath" "$bytes" <<'PY'
import sys
path, size = sys.argv[1], int(sys.argv[2])
unit = (path + "\n")
data = (unit * (size // len(unit) + 1))[:size]
with open(path, "w") as f:
    f.write(data)
PY
}

commit_all() {
    local repo="$1" msg="${2:-test commit}"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "$msg"
}

# write_config <repo> reads config body from stdin into docs/atlas/config.yaml
write_config() {
    local repo="$1"
    mkdir -p "$repo/docs/atlas"
    cat > "$repo/docs/atlas/config.yaml"
}

# run_atlas <repo> <args...>
# Runs atlas-cli from inside the repo. Sets OUTPUT and EXIT_CODE.
run_atlas() {
    local repo="$1"
    shift
    set +e
    OUTPUT=$(cd "$repo" && python3 "$CLI" "$@" 2>/dev/null)
    EXIT_CODE=$?
    set -e
}

cleanup_fixture_repo() {
    local repo="$1"
    if [ -n "$repo" ] && [ -d "$repo" ] && [[ "$repo" == /tmp/atlas-tests-* ]]; then
        rm -rf "$repo"
    fi
}

# write_module_doc <repo> <doc-id> <module-path> <refs-csv> <source-path...>
# Creates docs/atlas/modules/<doc-id>.md with frontmatter (sources without
# blobs — `ledger finalize --refresh-hashes` fills them) and a minimal body.
# <refs-csv> is a comma-separated references_modules list, or "" for none.
write_module_doc() {
    local repo="$1" doc_id="$2" module="$3" refs_csv="$4"
    shift 4
    local doc="$repo/docs/atlas/modules/$doc_id.md"
    mkdir -p "$(dirname "$doc")"
    {
        echo "---"
        echo "module: $module"
        echo "summary: \"${ATLAS_TEST_SUMMARY:-Test module $doc_id}\""
        echo "read_when: \"${ATLAS_TEST_READ_WHEN:-Touching $module}\""
        echo "sources:"
        local src
        for src in "$@"; do
            echo "  - path: $src"
        done
        if [ -n "$refs_csv" ]; then
            echo "references_modules: [$refs_csv]"
        fi
        echo "generator: cartographer/1 model=test"
        echo "---"
        echo ""
        echo "# Module: $module"
        echo ""
        echo "## Purpose"
        echo "Test fixture doc."
    } > "$doc"
}

# write_overview_doc <repo> <doc-id> <scope-dir> <doc-source-relpath...>
# Overview docs draw from module docs (path sources) and directory scopes
# (tree-SHA invalidation).
write_overview_doc() {
    local repo="$1" doc_id="$2" scope_dir="$3"
    shift 3
    local doc="$repo/docs/atlas/overview/$doc_id.md"
    mkdir -p "$(dirname "$doc")"
    {
        echo "---"
        echo "module: overview/$doc_id"
        echo "summary: \"Test overview $doc_id\""
        echo "sources:"
        local src
        for src in "$@"; do
            echo "  - path: $src"
        done
        if [ -n "$scope_dir" ]; then
            echo "scopes:"
            echo "  - tree: $scope_dir"
        fi
        echo "generator: cartographer/1 model=test"
        echo "---"
        echo ""
        echo "# Architecture"
        echo ""
        echo "Test fixture overview."
        echo ""
        echo "<!-- atlas:index-facts -->"
        echo "- Fixture fact: everything flows through the core module."
        echo "<!-- /atlas:index-facts -->"
    } > "$doc"
}

# write_full_module_doc <repo> <doc-id> <module> <symbol> <source-path> \
#                       [refs-csv] [extra-source...]
# A module doc with the COMPLETE canonical skeleton (passes lint L1) and a
# Public API table row claiming <symbol> at <source-path>:1. Optional
# [refs-csv] fills references_modules; optional extra sources join the
# frontmatter sources list (body only references the first source).
write_full_module_doc() {
    local repo="$1" doc_id="$2" module="$3" symbol="$4" src="$5"
    local refs_csv="${6:-}"
    shift 5
    [ $# -gt 0 ] && shift   # drop refs-csv; the rest are extra sources
    local doc="$repo/docs/atlas/modules/$doc_id.md"
    mkdir -p "$(dirname "$doc")"
    {
        echo "---"
        echo "module: $module"
        echo "summary: \"Test module $doc_id\""
        echo "read_when: \"Touching $module\""
        echo "sources:"
        echo "  - path: $src"
        local extra
        for extra in "$@"; do
            echo "  - path: $extra"
        done
        if [ -n "$refs_csv" ]; then
            echo "references_modules: [$refs_csv]"
        fi
        echo "generator: cartographer/1 model=test"
        echo "---"
        echo ""
        echo "# Module: $module"
        echo ""
        echo "## Purpose"
        echo ""
        echo "Handles $module concerns for the fixture."
        echo ""
        echo "## Public API"
        echo ""
        echo "| Symbol | Kind | Location | Contract |"
        echo "| --- | --- | --- | --- |"
        echo "| \`$symbol\` | class | \`$src:1\` | Does fixture things |"
        echo ""
        echo "## Load-bearing internals"
        echo ""
        echo "| Symbol | Kind | Location | Why it matters |"
        echo "| --- | --- | --- | --- |"
        echo ""
        echo "## Relationships"
        echo ""
        echo "- \`$doc_id.$symbol -> external.none (calls)\`"
        echo ""
        echo "## Type notes"
        echo ""
        echo "$symbol owns the fixture lifecycle."
        echo ""
        echo "## External deps"
        echo ""
        echo "- none"
    } > "$doc"
}

# backdate_lock <repo> <seconds-ago>
# Rewrites .atlas/lock/lock.json heartbeat to N seconds in the past.
backdate_lock() {
    local repo="$1" ago="$2"
    python3 - "$repo/.atlas/lock/lock.json" "$ago" <<'PY'
import json, sys, time
path, ago = sys.argv[1], int(sys.argv[2])
with open(path) as f:
    lock = json.load(f)
lock["heartbeat_at"] = time.time() - ago
lock["acquired_at"] = time.time() - ago
with open(path, "w") as f:
    json.dump(lock, f)
PY
}

# --- Assertion Helpers ---

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo "    FAIL: $msg"
        echo "      expected: $expected"
        echo "      actual:   $actual"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="${3:-assert_exit_code}"
    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo "    FAIL: $msg — expected exit code $expected, got $actual"
        return 1
    fi
}

# assert_json_field <json> <jq-filter> <expected> [msg]
assert_json_field() {
    local json="$1" field="$2" expected="$3" msg="${4:-assert_json_field}"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "    FAIL: $msg — field $field"
        echo "      expected: $expected"
        echo "      actual:   $actual"
        return 1
    fi
}

# assert_json_contains <json> <jq-filter> <value> [msg]
# Passes when <jq-filter> (an array filter) contains <value>.
assert_json_contains() {
    local json="$1" field="$2" value="$3" msg="${4:-assert_json_contains}"
    local found
    found=$(echo "$json" | jq -r "$field | index(\"$value\") != null" 2>/dev/null)
    if [ "$found" = "true" ]; then
        return 0
    else
        echo "    FAIL: $msg — $value not found in $field"
        echo "      json: $(echo "$json" | jq -c "$field" 2>/dev/null)"
        return 1
    fi
}

assert_json_not_contains() {
    local json="$1" field="$2" value="$3" msg="${4:-assert_json_not_contains}"
    local found
    found=$(echo "$json" | jq -r "$field | index(\"$value\") != null" 2>/dev/null)
    if [ "$found" = "false" ]; then
        return 0
    else
        echo "    FAIL: $msg — $value unexpectedly present in $field"
        return 1
    fi
}

assert_file_exists() {
    local file="$1" msg="${2:-assert_file_exists}"
    if [ -f "$file" ]; then
        return 0
    else
        echo "    FAIL: $msg — file not found: $file"
        return 1
    fi
}
