#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export DEPLOYIT_STATE_DIR="$ROOT"
export DEPLOYIT_SKIP_GC_PUSH=1

BASE="https://demo.tail.ts.net/deployit"
mkdir -p "$ROOT/index" "$ROOT/serve"
cat > "$ROOT/config.toml" <<TOML
[server]
port = 8729
base_url = "$BASE"
[index]
repo = "https://example.invalid/repo.git"
[macos]
notarize = false
notary_profile = ""
TOML

# Seed 4 builds, all from this origin, none archived
mk_build() {
    local id="$1" ts="$2"
    mkdir -p "$ROOT/serve/$id"
    echo "fake" > "$ROOT/serve/$id/app.ipa"
    echo "{\"id\":\"$id\",\"timestamp\":\"$ts\"}" > "$ROOT/serve/$id/_meta.json"
    cat <<JSON
{"id":"$id","platform":"ios","project":"Lillist","bundle_id":"x","marketing_version":"1.0","build_number":"$id","commit":"$id","timestamp":"$ts","origin_host":"demo.tail.ts.net","origin_base_url":"$BASE","install":{"kind":"itms-services","manifest_url":"x","ipa_url":"y"},"size_bytes":1,"archived":false,"notes":null}
JSON
}

cat > "$ROOT/index/builds.json" <<JSON
{"version":1,"builds":[
$(mk_build "old4" "2026-05-04T10:00:00-07:00"),
$(mk_build "old3" "2026-05-03T10:00:00-07:00"),
$(mk_build "old2" "2026-05-02T10:00:00-07:00"),
$(mk_build "old1" "2026-05-01T10:00:00-07:00")
]}
JSON

# --keep 2: archive the 2 oldest, keep the 2 newest
out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" gc --keep 2) \
    || { echo "FAIL: gc --keep 2 exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"archived": 2' || { echo "FAIL: expected archived 2: $out"; exit 1; }
echo "$out" | grep -q '"removed_local": 2' || { echo "FAIL: expected removed_local 2: $out"; exit 1; }

# old4 + old3 remain on disk, old1 + old2 are gone
[[ -d "$ROOT/serve/old4" && -d "$ROOT/serve/old3" ]] || { echo "FAIL: newest survived: $(ls $ROOT/serve)"; exit 1; }
[[ ! -d "$ROOT/serve/old1" && ! -d "$ROOT/serve/old2" ]] || { echo "FAIL: oldest should be gone: $(ls $ROOT/serve)"; exit 1; }

# In the index, old1 + old2 marked archived
python3 -c "
import json
data = json.load(open('$ROOT/index/builds.json'))
by_id = {b['id']: b for b in data['builds']}
assert by_id['old4']['archived'] is False
assert by_id['old3']['archived'] is False
assert by_id['old2']['archived'] is True
assert by_id['old1']['archived'] is True
print('archived flags ok')
" || exit 1

# Running gc again with --keep 10 should be a no-op
out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" gc --keep 10) \
    || { echo "FAIL: gc --keep 10 exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"archived": 0' || { echo "FAIL: expected no-op: $out"; exit 1; }

# Missing required arg — capture stdout (pipefail would fire on exit 1 from gc itself)
gc_out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" gc 2>&1 || true)
python3 -c "
import json, sys
d = json.loads('''$gc_out''')
assert d['ok'] is False, f'expected ok=false, got: {d}'
print('bare gc returned ok=false as expected')
" || { echo "FAIL: bare gc should return JSON with ok=false; got: $gc_out"; exit 1; }

echo "PASS"
