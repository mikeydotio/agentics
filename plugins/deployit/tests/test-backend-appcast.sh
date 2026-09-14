#!/usr/bin/env bash
# The Sparkle appcast endpoint (/deployit/p/<bundle>/macos/appcast.xml) serves
# application/xml listing only EdDSA-signed, non-archived macOS builds of the
# product, newest-first, with correct enclosure metadata. Unsigned builds,
# archived builds, and iOS builds are excluded. Unknown / zero-signed products
# 404. The product page surfaces an Auto-update block (SUFeedURL + SUPublicEDKey)
# for macOS products with signed builds, and nothing for iOS.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

ORIGIN="https://studio.tail-abc.ts.net/deployit"
cat > "$ROOT/index/builds.json" <<JSON
{
  "version": 1,
  "builds": [
    {
      "id": "lillist-macos-A", "platform": "macos", "project": "Lillist",
      "bundle_id": "io.mikey.lillist", "marketing_version": "0.2.0",
      "semver_version": null, "build_number": "7", "commit": "aaaaaaa",
      "timestamp": "2026-05-25T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net", "origin_base_url": "$ORIGIN",
      "install": {"kind":"direct-download","dmg_url":"$ORIGIN/lillist-macos-A/Lillist.dmg"},
      "sparkle": {"zip_artifact":"Lillist.zip","zip_url":"$ORIGIN/lillist-macos-A/Lillist.zip","zip_length":1000,"ed_signature":"SIGA==","short_version":"0.2.0","version":"7","public_ed_key":"PUBKEY=="},
      "size_bytes": 2000, "archived": false, "notes": null
    },
    {
      "id": "lillist-macos-B", "platform": "macos", "project": "Lillist",
      "bundle_id": "io.mikey.lillist", "marketing_version": "0.1.0",
      "semver_version": null, "build_number": "6", "commit": "bbbbbbb",
      "timestamp": "2026-05-24T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net", "origin_base_url": "$ORIGIN",
      "install": {"kind":"direct-download","dmg_url":"$ORIGIN/lillist-macos-B/Lillist.dmg"},
      "sparkle": {"zip_artifact":"Lillist.zip","zip_url":"$ORIGIN/lillist-macos-B/Lillist.zip","zip_length":900,"ed_signature":"SIGB==","short_version":"0.1.0","version":"6","public_ed_key":"PUBKEY=="},
      "size_bytes": 1800, "archived": false, "notes": null
    },
    {
      "id": "lillist-macos-C", "platform": "macos", "project": "Lillist",
      "bundle_id": "io.mikey.lillist", "marketing_version": "0.0.9",
      "semver_version": null, "build_number": "99", "commit": "ccccccc",
      "timestamp": "2026-05-23T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net", "origin_base_url": "$ORIGIN",
      "install": {"kind":"direct-download","dmg_url":"$ORIGIN/lillist-macos-C/Lillist.dmg"},
      "size_bytes": 1700, "archived": false, "notes": null
    },
    {
      "id": "lillist-macos-D", "platform": "macos", "project": "Lillist",
      "bundle_id": "io.mikey.lillist", "marketing_version": "0.0.8",
      "semver_version": null, "build_number": "8", "commit": "ddddddd",
      "timestamp": "2026-05-22T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net", "origin_base_url": "$ORIGIN",
      "install": {"kind":"direct-download","dmg_url":"$ORIGIN/lillist-macos-D/Lillist.dmg"},
      "sparkle": {"zip_artifact":"Lillist.zip","zip_url":"$ORIGIN/lillist-macos-D/Lillist.zip","zip_length":800,"ed_signature":"SIGD==","short_version":"0.0.8","version":"8","public_ed_key":"PUBKEY=="},
      "size_bytes": 1600, "archived": true, "notes": null
    },
    {
      "id": "lillist-ios-E", "platform": "ios", "project": "Lillist",
      "bundle_id": "io.mikey.lillist", "marketing_version": "0.2.0",
      "semver_version": null, "build_number": "20", "commit": "eeeeeee",
      "timestamp": "2026-05-21T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net", "origin_base_url": "$ORIGIN",
      "install": {"kind":"itms-services","manifest_url":"$ORIGIN/lillist-ios-E/manifest.plist","ipa_url":"$ORIGIN/lillist-ios-E/Lillist.ipa"},
      "size_bytes": 3000, "archived": false, "notes": null
    },
    {
      "id": "nosign-macos-F", "platform": "macos", "project": "NoSign",
      "bundle_id": "io.mikeydotio.NoSign", "marketing_version": "1.0.0",
      "semver_version": null, "build_number": "1", "commit": "fffffff",
      "timestamp": "2026-05-20T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net", "origin_base_url": "$ORIGIN",
      "install": {"kind":"direct-download","dmg_url":"$ORIGIN/nosign-macos-F/NoSign.dmg"},
      "size_bytes": 1500, "archived": false, "notes": null
    }
  ]
}
JSON

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

FEED="http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/macos/appcast.xml"

# --- Content-Type is application/xml ---
headers=$(curl -sf -o /dev/null -D - "$FEED")
printf '%s' "$headers" | grep -iq '^content-type: application/xml' \
    || { echo "FAIL: appcast content-type not application/xml"; printf '%s' "$headers"; exit 1; }

body=$(curl -sf "$FEED")

# --- Signed builds present with correct enclosure metadata ---
echo "$body" | grep -q 'sparkle:edSignature="SIGA=="' \
    || { echo "FAIL: build A signature missing"; echo "$body"; exit 1; }
echo "$body" | grep -q 'sparkle:edSignature="SIGB=="' \
    || { echo "FAIL: build B signature missing"; echo "$body"; exit 1; }
echo "$body" | grep -q '<sparkle:version>7</sparkle:version>' \
    || { echo "FAIL: build A sparkle:version missing"; echo "$body"; exit 1; }
echo "$body" | grep -q '<sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>' \
    || { echo "FAIL: build A shortVersionString missing"; echo "$body"; exit 1; }
echo "$body" | grep -q 'url="'"$ORIGIN"'/lillist-macos-A/Lillist.zip" length="1000"' \
    || { echo "FAIL: build A enclosure url/length wrong"; echo "$body"; exit 1; }

# --- Newest-first ordering: A before B ---
posA=$(echo "$body" | grep -n 'SIGA==' | head -1 | cut -d: -f1)
posB=$(echo "$body" | grep -n 'SIGB==' | head -1 | cut -d: -f1)
[[ "$posA" -lt "$posB" ]] \
    || { echo "FAIL: appcast not newest-first (A=$posA B=$posB)"; exit 1; }

# --- Exclusions: unsigned (C/build 99), archived (D/SIGD), iOS (build 20) ---
echo "$body" | grep -q 'SIGD' \
    && { echo "FAIL: archived signed build D leaked into appcast"; echo "$body"; exit 1; }
echo "$body" | grep -q '>99<' \
    && { echo "FAIL: unsigned build C leaked into appcast"; echo "$body"; exit 1; }
echo "$body" | grep -q '>20<' \
    && { echo "FAIL: iOS build leaked into appcast"; echo "$body"; exit 1; }

# --- XML well-formedness (catches template-escaping bugs) ---
echo "$body" | python3 -c "import sys, xml.dom.minidom as m; m.parseString(sys.stdin.read())" \
    || { echo "FAIL: appcast is not well-formed XML"; echo "$body"; exit 1; }

# --- 404s: unknown bundle, and a product with zero signed builds ---
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/p/no.such.bundle/macos/appcast.xml")
[[ "$code" == "404" ]] || { echo "FAIL: unknown bundle appcast should 404, got $code"; exit 1; }
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/p/io.mikeydotio.NoSign/macos/appcast.xml")
[[ "$code" == "404" ]] || { echo "FAIL: zero-signed product appcast should 404, got $code"; exit 1; }

# --- Product page Auto-update block (macOS with signed builds) ---
prod=$(curl -sf "http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/macos/")
echo "$prod" | grep -q "Auto-update (Sparkle)" \
    || { echo "FAIL: product page missing Sparkle block"; echo "$prod"; exit 1; }
echo "$prod" | grep -q "SUFeedURL" \
    || { echo "FAIL: product page missing SUFeedURL label"; echo "$prod"; exit 1; }
echo "$prod" | grep -q "$ORIGIN/p/io.mikey.lillist/macos/appcast.xml" \
    || { echo "FAIL: product page missing appcast URL"; echo "$prod"; exit 1; }
echo "$prod" | grep -q "PUBKEY==" \
    || { echo "FAIL: product page missing SUPublicEDKey"; echo "$prod"; exit 1; }

# --- iOS product page has NO Sparkle block ---
prod_ios=$(curl -sf "http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/ios/")
echo "$prod_ios" | grep -q "Auto-update" \
    && { echo "FAIL: iOS product page should not show Sparkle block"; echo "$prod_ios"; exit 1; }

echo "PASS"
