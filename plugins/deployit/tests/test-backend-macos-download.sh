#!/usr/bin/env bash
# macOS builds are first-class in the web UI: they render with a "Download"
# button pointing at the .dmg, show Apple's canonical "macOS" casing (not the
# lowercase index slug), and the per-build landing page carries a macOS-only
# Gatekeeper note instead of the iOS device-trust note.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
BUILD_ID="lillist-macos-20260520-090000-mac0001"
mkdir -p "$ROOT/serve/$BUILD_ID" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

cat > "$ROOT/index/builds.json" <<JSON
{
  "version": 1,
  "builds": [
    {
      "id": "$BUILD_ID",
      "platform": "macos", "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0", "build_number": "5", "commit": "mac0001",
      "timestamp": "2026-05-20T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"direct-download","dmg_url":"https://studio.tail-abc.ts.net/deployit/$BUILD_ID/Lillist.dmg"},
      "size_bytes": 12345678, "archived": false, "notes": null
    }
  ]
}
JSON

# _meta.json so the per-build landing page renders.
cat > "$ROOT/serve/$BUILD_ID/_meta.json" <<JSON
{"id":"$BUILD_ID","platform":"macos","project":"Lillist","bundle_id":"io.mikey.lillist","marketing_version":"0.1.0","build_number":"5","commit":"mac0001","timestamp":"2026-05-20T09:00:00-07:00","origin_host":"studio.tail-abc.ts.net","origin_base_url":"https://studio.tail-abc.ts.net/deployit","install":{"kind":"direct-download","dmg_url":"https://studio.tail-abc.ts.net/deployit/$BUILD_ID/Lillist.dmg"},"primary_artifact":"Lillist.dmg"}
JSON

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

# --- Listing: Download button + canonical macOS casing + .dmg href ---
listing=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
echo "$listing" | grep -q 'class="name">Lillist' \
    || { echo "FAIL: macOS product name not rendered"; echo "$listing"; exit 1; }
echo "$listing" | grep -q "macOS · build 5" \
    || { echo "FAIL: macOS row not rendered with canonical casing"; echo "$listing"; exit 1; }
echo "$listing" | grep -q ">Download</a>" \
    || { echo "FAIL: macOS row missing Download button"; echo "$listing"; exit 1; }
echo "$listing" | grep -q 'Lillist.dmg' \
    || { echo "FAIL: macOS row missing .dmg href"; echo "$listing"; exit 1; }

# --- Product page: Download + macOS header ---
product=$(curl -sf "http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/macos/")
echo "$product" | grep -q "Lillist · macOS" \
    || { echo "FAIL: product header not macOS"; echo "$product"; exit 1; }
echo "$product" | grep -q ">Download</a>" \
    || { echo "FAIL: product page missing Download button"; echo "$product"; exit 1; }

# --- Landing page: Download, macOS sub, Gatekeeper note, NO iOS trust note ---
landing=$(curl -sf "http://127.0.0.1:$PORT/deployit/$BUILD_ID/")
echo "$landing" | grep -q "macOS build" \
    || { echo "FAIL: landing sub not 'macOS build'"; echo "$landing"; exit 1; }
echo "$landing" | grep -q ">Download</a>" \
    || { echo "FAIL: landing missing Download button"; echo "$landing"; exit 1; }
echo "$landing" | grep -q "unidentified developer" \
    || { echo "FAIL: landing missing macOS Gatekeeper note"; echo "$landing"; exit 1; }
echo "$landing" | grep -q "Device Management" \
    && { echo "FAIL: iOS trust note leaked onto macOS landing"; echo "$landing"; exit 1; }

echo "PASS"
