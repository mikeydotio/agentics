#!/usr/bin/env bash
# End-to-end test of the v2 `/atlas map` flow at the CLI layer (Wave 7):
#   scan -> partition -> extract -> judge-plan -> [judge] -> ingest -> project
#   -> index rebuild -> ledger finalize -> lint
# The only simulated step is the cartographer's cell output (mock DATA, never
# behavior) — every CLI step runs for real, proving the pipeline composes into a
# coherent, lint-clean map.

_mapflow_fixture() {
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
from src.auth.service import _sign

class ApiClient:
    def call(self):
        return _sign(2)
PY
    local i
    for i in 1 2 3 4 5 6 7; do
        seed_file "$repo" "src/auth/pad$i.txt"
        seed_file "$repo" "src/api/pad$i.txt"
    done
    commit_all "$repo"
    echo "$repo"
}

# Simulate the cartographer fan-out: give every missing cell a deterministic,
# kind-appropriate value so projected prose is distinguishable from placeholders.
_judge_all() {
    local repo="$1"
    (cd "$repo" && python3 "$CLI" judge-plan \
        | jq -c '[.missing_keys[] | {key, kind,
            value: ("JUDGED:" + .kind + ":" + ((.symbol // .module)))}]' \
        | python3 "$CLI" judgment ingest >/dev/null)
}

test_full_map_flow_produces_clean_map() {
    local repo; repo=$(_mapflow_fixture)

    # 0. preflight
    run_atlas "$repo" scan
    assert_json_field "$OUTPUT" '.ok' "true" "scan ok" || return 1
    run_atlas "$repo" partition
    assert_json_field "$OUTPUT" '.ok' "true" "partition ok" || return 1

    # 1. extract → structure index
    run_atlas "$repo" extract
    assert_json_field "$OUTPUT" '.ok' "true" "extract ok" || return 1
    assert_file_exists "$repo/.atlas/structure/index.json" "structure index" || return 1

    # 2. judge-plan → all missing on a fresh map
    run_atlas "$repo" judge-plan
    local total missing
    total=$(echo "$OUTPUT" | jq -r '.total_expected')
    missing=$(echo "$OUTPUT" | jq -r '.missing_count')
    assert_eq "$total" "$missing" "every cell missing initially" || return 1

    # 3. judge (simulated) + ingest
    _judge_all "$repo"

    # 4. project → docs
    run_atlas "$repo" project
    assert_json_field "$OUTPUT" '.placeholder_count' "0" "no placeholders after judging" || return 1

    # 5. ledger finalize (stamps final frontmatter) then 6. index rebuild
    # (reads it) — order is load-bearing.
    run_atlas "$repo" ledger finalize --refresh-hashes --generator "cartographer/4"
    assert_json_field "$OUTPUT" '.ledger_version' "2" "ledger is v2" || return 1
    run_atlas "$repo" index rebuild
    assert_json_field "$OUTPUT" '.ok' "true" "index rebuild ok" || return 1

    # 7. lint → clean, and the delta engine agrees nothing is left to do
    run_atlas "$repo" lint
    assert_json_field "$OUTPUT" '.ok' "true" "final map lints clean" || return 1
    run_atlas "$repo" judgment diff
    assert_json_field "$OUTPUT" '.clean' "true" "judgment diff is clean" || return 1

    # The map artifacts exist and carry judged prose.
    assert_file_exists "$repo/docs/atlas/INDEX.md" "INDEX written" || return 1
    grep -q 'JUDGED:module.purpose' "$repo/docs/atlas/modules/src-auth.md" \
        || { echo "    FAIL: judged purpose not in doc"; return 1; }
    cleanup_fixture_repo "$repo"
}

test_map_flow_is_fully_deterministic() {
    local repo; repo=$(_mapflow_fixture)
    _judge_all "$repo"
    run_atlas "$repo" project >/dev/null
    local h1; h1=$(shasum "$repo/docs/atlas/modules/src-auth.md" | awk '{print $1}')
    # Wipe derived docs + structure cache and replay from the same cache.
    rm -rf "$repo/docs/atlas/modules" "$repo/.atlas/structure"
    run_atlas "$repo" project >/dev/null
    local h2; h2=$(shasum "$repo/docs/atlas/modules/src-auth.md" | awk '{print $1}')
    assert_eq "$h1" "$h2" "re-projection from the same cache is byte-identical" || return 1
    cleanup_fixture_repo "$repo"
}

test_map_flow_cross_module_edge_rendered() {
    local repo; repo=$(_mapflow_fixture)
    _judge_all "$repo"
    run_atlas "$repo" project >/dev/null
    # ApiClient.call -> _sign (src-auth) is a resolved cross-module edge.
    grep -q 'src-api.* -> src-auth._sign (calls)' "$repo/docs/atlas/modules/src-api.md" \
        || { echo "    FAIL: cross-module edge missing"; cat "$repo/docs/atlas/modules/src-api.md"; return 1; }
    cleanup_fixture_repo "$repo"
}
