#!/usr/bin/env bash
# Listing endpoint groups builds by (bundle_id, platform), showing only the
# newest build per product. Older builds of the same product surface via a
# "+N older" indicator and a data-href to the product page.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

# Three builds:
#  - Lillist iOS build 17 (newest, newest of its product)
#  - Lillist iOS build 16 (older of same product)
#  - Lillist macOS build 5 (different product, single build)
cat > "$ROOT/index/builds.json" <<JSON
{
  "version": 1,
  "builds": [
    {
      "id": "lillist-ios-20260522-100000-def5678",
      "platform": "ios",
      "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0",
      "build_number": "17",
      "commit": "def5678",
      "timestamp": "2026-05-22T10:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"itms-services","manifest_url":"https://x/m.plist","ipa_url":"https://x/a.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    },
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
      "install": {"kind":"itms-services","manifest_url":"https://x/m2.plist","ipa_url":"https://x/a2.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    },
    {
      "id": "lillist-macos-20260520-090000-mac0001",
      "platform": "macos",
      "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0",
      "build_number": "5",
      "commit": "mac0001",
      "timestamp": "2026-05-20T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"direct-download","dmg_url":"https://x/app.dmg"},
      "size_bytes": 1, "archived": false, "notes": null
    }
  ]
}
JSON

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

body=$(curl -sf "http://127.0.0.1:$PORT/deployit/")

echo "$body" | grep -q 'class="name">Lillist' \
    || { echo "FAIL: product name not rendered"; echo "$body"; exit 1; }
echo "$body" | grep -q "iOS · build 17" \
    || { echo "FAIL: newest iOS build not rendered"; echo "$body"; exit 1; }
echo "$body" | grep -q "macOS · build 5" \
    || { echo "FAIL: macOS build not rendered"; echo "$body"; exit 1; }
echo "$body" | grep -q "build 16" \
    && { echo "FAIL: older iOS build 16 should be hidden"; echo "$body"; exit 1; }

echo "$body" | grep -q "+1 older" \
    || { echo "FAIL: '+1 older' indicator missing"; echo "$body"; exit 1; }

echo "$body" | grep -q 'data-href="/deployit/p/io.mikey.lillist/ios/"' \
    || { echo "FAIL: ios product data-href missing"; echo "$body"; exit 1; }
echo "$body" | grep -q 'data-href="/deployit/p/io.mikey.lillist/macos/"' \
    || { echo "FAIL: macos product data-href missing"; echo "$body"; exit 1; }

echo "$body" | grep -q "2 products" \
    || { echo "FAIL: product count not rendered"; echo "$body"; exit 1; }

echo "PASS"
