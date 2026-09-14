#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
BUILD_ID="lillist-ios-20260521-153012-abc1234"
mkdir -p "$ROOT/serve/$BUILD_ID" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
echo "fake-ipa" > "$ROOT/serve/$BUILD_ID/Lillist.ipa"
echo "<plist/>" > "$ROOT/serve/$BUILD_ID/manifest.plist"
cat > "$ROOT/serve/$BUILD_ID/_meta.json" <<JSON
{
  "id": "$BUILD_ID",
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
    "manifest_url": "https://studio.tail-abc.ts.net/deployit/$BUILD_ID/manifest.plist",
    "ipa_url":      "https://studio.tail-abc.ts.net/deployit/$BUILD_ID/Lillist.ipa"
  },
  "primary_artifact": "Lillist.ipa"
}
JSON

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

# Landing page
body=$(curl -sf "http://127.0.0.1:$PORT/deployit/$BUILD_ID/")
echo "$body" | grep -q 'Lillist' || { echo "FAIL: landing missing title"; exit 1; }
echo "$body" | grep -q 'itms-services' || { echo "FAIL: install link missing"; exit 1; }

# Manifest
manifest=$(curl -sf "http://127.0.0.1:$PORT/deployit/$BUILD_ID/manifest.plist")
[[ "$manifest" == "<plist/>" ]] || { echo "FAIL: manifest body wrong"; exit 1; }

# IPA
ipa=$(curl -sf "http://127.0.0.1:$PORT/deployit/$BUILD_ID/Lillist.ipa")
[[ "$ipa" == "fake-ipa" ]] || { echo "FAIL: ipa body wrong"; exit 1; }

# Unknown artifact → 404
status=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/$BUILD_ID/nope.bin")
[[ "$status" == "404" ]] || { echo "FAIL: expected 404, got $status"; exit 1; }

# Path traversal → 404 (use --path-as-is so curl doesn't normalize)
status=$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "http://127.0.0.1:$PORT/deployit/$BUILD_ID/../../etc/passwd")
[[ "$status" == "404" ]] || { echo "FAIL: traversal not blocked: $status"; exit 1; }

echo "PASS"
