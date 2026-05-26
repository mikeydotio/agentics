#!/usr/bin/env bash
# Verify the backend serves PWA static assets (manifest + icons) with the
# right MIME types, the listing HTML advertises them, and per-build paths
# still work (regression).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
cat > "$ROOT/index/builds.json" <<'JSON'
{"version": 1, "builds": []}
JSON

PORT=18733
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true' EXIT

for _ in {1..50}; do
    curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break
    sleep 0.1
done

check() {
    local path="$1" expected_ctype="$2"
    local headers
    # Use GET with -D to capture headers — the backend only implements do_GET,
    # not do_HEAD, so `curl -I` would 501.
    headers=$(curl -sf -o /dev/null -D - "http://127.0.0.1:$PORT$path") \
        || { echo "FAIL: $path did not return 200"; exit 1; }
    echo "$headers" | grep -iFq "content-type: $expected_ctype" \
        || { echo "FAIL: $path content-type mismatch (wanted $expected_ctype)"; echo "$headers"; exit 1; }
    echo "$headers" | grep -iFq 'cache-control: public, max-age=86400' \
        || { echo "FAIL: $path missing Cache-Control"; echo "$headers"; exit 1; }
}

check /deployit/manifest.webmanifest             "application/manifest+json"
check /deployit/icon.svg                         "image/svg+xml"
check /deployit/apple-touch-icon.png             "image/png"
check /deployit/apple-touch-icon-precomposed.png "image/png"
check /deployit/icons/icon-192.png               "image/png"
check /deployit/icons/icon-512.png               "image/png"
check /deployit/icons/icon-maskable-512.png      "image/png"

# Listing HTML must reference the PWA bits so iOS Safari picks them up.
body=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
echo "$body" | grep -q 'rel="manifest"'                       || { echo "FAIL: listing missing manifest link"; exit 1; }
echo "$body" | grep -q 'rel="apple-touch-icon"'               || { echo "FAIL: listing missing apple-touch-icon"; exit 1; }
echo "$body" | grep -q 'name="apple-mobile-web-app-capable"'  || { echo "FAIL: listing missing apple-mobile-web-app-capable"; exit 1; }
echo "$body" | grep -q 'name="theme-color"'                   || { echo "FAIL: listing missing theme-color"; exit 1; }

# Unknown static path must NOT match a build-id and 404 cleanly.
status=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/does-not-exist.png")
[[ "$status" == "404" ]] || { echo "FAIL: unknown static path returned $status"; exit 1; }

# Static-asset routing must NOT shadow build-id paths. With no build registered,
# a fake build-id should still hit the build-id branch and return unknown_build.
status=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/some-build-id/")
[[ "$status" == "404" ]] || { echo "FAIL: build-id path regressed, got $status"; exit 1; }

echo "PASS"
