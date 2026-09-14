#!/usr/bin/env bash
# Product history page lists all builds for one (bundle_id, platform) in
# desc order. Unknown products return 404. The /p/ prefix is not shadowed
# by the build-id route.
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
      "id": "lillist-ios-20260522-100000-def5678",
      "platform": "ios", "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0", "build_number": "17",
      "commit": "def5678",
      "timestamp": "2026-05-22T10:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"itms-services","manifest_url":"https://x/m.plist","ipa_url":"https://x/a.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    },
    {
      "id": "lillist-ios-20260521-153012-abc1234",
      "platform": "ios", "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0", "build_number": "16",
      "commit": "abc1234",
      "timestamp": "2026-05-21T15:30:12-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"itms-services","manifest_url":"https://x/m2.plist","ipa_url":"https://x/a2.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    },
    {
      "id": "other-macos-20260520-090000-other01",
      "platform": "macos", "project": "Other",
      "bundle_id": "io.mikeydotio.Other",
      "marketing_version": "1.0.0", "build_number": "3",
      "commit": "other01",
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

# Known product returns 200 and lists both builds in desc order
body=$(curl -sf "http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/ios/")
echo "$body" | grep -q "Lillist · iOS" \
    || { echo "FAIL: product header missing"; echo "$body"; exit 1; }
echo "$body" | grep -q "build 17" \
    || { echo "FAIL: build 17 missing"; echo "$body"; exit 1; }
echo "$body" | grep -q "build 16" \
    || { echo "FAIL: build 16 missing"; echo "$body"; exit 1; }
echo "$body" | grep -q "io.mikey.lillist" \
    || { echo "FAIL: bundle_id missing"; echo "$body"; exit 1; }
echo "$body" | grep -q "← all products" \
    || { echo "FAIL: back link missing"; echo "$body"; exit 1; }
# Build 17 must appear before build 16 (desc order)
pos17=$(echo "$body" | grep -n "build 17" | head -1 | cut -d: -f1)
pos16=$(echo "$body" | grep -n "build 16" | head -1 | cut -d: -f1)
[[ "$pos17" -lt "$pos16" ]] \
    || { echo "FAIL: build 17 should appear before build 16 ($pos17 vs $pos16)"; exit 1; }

# Unknown product returns 404
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/p/no.such.bundle/ios/")
[[ "$code" == "404" ]] \
    || { echo "FAIL: expected 404 for unknown product, got $code"; exit 1; }

# Macos route works too and does not leak iOS builds
body_mac=$(curl -sf "http://127.0.0.1:$PORT/deployit/p/io.mikeydotio.Other/macos/")
echo "$body_mac" | grep -q "build 3" \
    || { echo "FAIL: macos product build 3 missing"; echo "$body_mac"; exit 1; }
echo "$body_mac" | grep -q "build 17" \
    && { echo "FAIL: macos product should not contain iOS build 17"; exit 1; }

# /p/ route is not interpreted as a build-id (would otherwise 404 with bad_build_id)
# Visiting /deployit/p/ without bundle/platform should fall through to the build-id route
# and 404 — but importantly should NOT 200.
code_bad=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/")
[[ "$code_bad" == "404" ]] \
    || { echo "FAIL: malformed /p/ URL should 404, got $code_bad"; exit 1; }

echo "PASS"
