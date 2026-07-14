#!/usr/bin/env bash
# Backend renders the out-of-band post-deploy test status (issue #90): a badge on
# the build landing page and the listing row, keyed off <state>/posttest/<id>.json.
# A build with no status file (predates the feature) shows no badge.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve/bid1" "$ROOT/index" "$ROOT/logs" "$ROOT/posttest"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

META='{"id":"bid1","project":"Moshtail","platform":"ios","bundle_id":"io.mikey.moshtail","marketing_version":"1.0.0","build_number":"218","commit":"abcdef1234567","timestamp":"2026-07-14T00:00:00-07:00","origin_host":"mac.ts.net","origin_base_url":"https://mac.ts.net/deployit","primary_artifact":"Moshtail.ipa","install":{"kind":"itms-services","manifest_url":"https://mac.ts.net/deployit/bid1/manifest.plist"}}'
printf '{"version":1,"builds":[%s]}' "$META" > "$ROOT/index/builds.json"
printf '%s' "$META" > "$ROOT/serve/bid1/_meta.json"
# config.toml gives this machine's base_url so bid1 counts as a local build.
printf '[server]\nport = %s\nbase_url = "https://mac.ts.net/deployit"\n' "18740" > "$ROOT/config.toml"

PORT=18740
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --local-host mac.ts.net \
    --no-git-pull > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT

for _ in {1..50}; do
    curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" > /dev/null && break
    sleep 0.1
done

fail() { echo "FAIL: $1"; cat "$ROOT/backend.log"; exit 1; }

# failed status -> red badge on both landing and listing
printf '{"build_id":"bid1","status":"failed","exit_code":2}' > "$ROOT/posttest/bid1.json"
landing=$(curl -sf "http://127.0.0.1:$PORT/deployit/bid1/")
echo "$landing" | grep -q 'posttest-failed' || fail "landing missing failed badge"
echo "$landing" | grep -q 'Tests failed' || fail "landing missing failed label"
listing=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
echo "$listing" | grep -q 'posttest-inline posttest-failed' || fail "listing missing failed badge"

# not_configured -> neutral badge (loud, never blank-implying-pass)
printf '{"build_id":"bid1","status":"not_configured"}' > "$ROOT/posttest/bid1.json"
landing=$(curl -sf "http://127.0.0.1:$PORT/deployit/bid1/")
echo "$landing" | grep -q 'posttest-not_configured' || fail "landing missing not_configured badge"
echo "$landing" | grep -q 'No post-deploy tests' || fail "landing missing not_configured label"

# no status file -> no badge in the page body
rm -f "$ROOT/posttest/bid1.json"
landing=$(curl -sf "http://127.0.0.1:$PORT/deployit/bid1/")
body=${landing#*</style>}
echo "$body" | grep -q 'posttest-' && fail "absent status must render no badge"

echo "PASS"
