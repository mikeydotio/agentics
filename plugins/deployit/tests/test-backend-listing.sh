#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

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
      "bundle_id": "io.mikey.lillist",
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

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

body=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
# Listing rows lead with a prominent product name; platform · version is a subline.
echo "$body" | grep -q 'class="name">Lillist' \
    || { echo "FAIL: product name not rendered"; echo "$body"; exit 1; }
echo "$body" | grep -q "iOS · build 16" \
    || { echo "FAIL: platform/version subline not rendered"; echo "$body"; exit 1; }
echo "$body" | grep -q 'itms-services' \
    || { echo "FAIL: install link missing"; echo "$body"; exit 1; }
echo "PASS"
