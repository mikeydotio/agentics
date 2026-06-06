#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
cat > "$ROOT/index/builds.json" <<JSON
{
  "version": 1,
  "builds": [
    {
      "id": "lillist-ios-20260521-153012-abc1234",
      "platform": "ios",
      "project": "Lillist",
      "bundle_id": "io.mikeydotio.Lillist",
      "marketing_version": "0.1.0",
      "build_number": "16",
      "commit": "abc1234",
      "timestamp": "2026-05-21T15:30:12-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {
        "kind": "itms-services",
        "manifest_url": "https://studio.tail-abc.ts.net/deployit/lillist-ios-20260521-153012-abc1234/manifest.plist",
        "ipa_url":      "https://studio.tail-abc.ts.net/deployit/lillist-ios-20260521-153012-abc1234/Lillist.ipa"
      },
      "size_bytes": 12345678,
      "archived": false,
      "notes": null
    }
  ]
}
JSON

PORT=18730
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT

for _ in {1..50}; do
    curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break
    sleep 0.1
done

body=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
echo "$body" | grep -q "Lillist · ios · build 16" \
    || { echo "FAIL: row not rendered"; echo "$body"; exit 1; }
echo "$body" | grep -q 'itms-services' \
    || { echo "FAIL: install link missing"; echo "$body"; exit 1; }
echo "PASS"
