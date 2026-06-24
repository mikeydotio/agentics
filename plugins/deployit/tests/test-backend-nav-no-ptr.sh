#!/usr/bin/env bash
# Nav bar replaces pull-to-refresh. The listing and product pages carry a
# nav-bar Refresh button (id="refresh") and no longer carry the pull-to-refresh
# indicator (id="ptr"). The served app.js drives the button via _internal/refresh
# and no longer binds touch gestures; app.css no longer styles #ptr and gives the
# button a 44px touch target.
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
      "platform": "ios", "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0", "build_number": "16", "commit": "abc1234",
      "timestamp": "2026-05-21T15:30:12-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"itms-services","manifest_url":"https://x/m.plist","ipa_url":"https://x/a.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    },
    {
      "id": "lillist-macos-20260520-090000-mac0001",
      "platform": "macos", "project": "Lillist",
      "bundle_id": "io.mikey.lillist",
      "marketing_version": "0.1.0", "build_number": "5", "commit": "mac0001",
      "timestamp": "2026-05-20T09:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"direct-download","dmg_url":"https://x/app.dmg"},
      "size_bytes": 1, "archived": false, "notes": null
    }
  ]
}
JSON

PORT=18745
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT

for _ in {1..50}; do
    curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break
    sleep 0.1
done

# --- Listing: nav Refresh button present, pull-to-refresh gone ---
listing=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
echo "$listing" | grep -q 'id="refresh"' \
    || { echo "FAIL: listing missing nav Refresh button"; echo "$listing"; exit 1; }
echo "$listing" | grep -q 'aria-label="Refresh builds"' \
    || { echo "FAIL: refresh button missing aria-label"; echo "$listing"; exit 1; }
echo "$listing" | grep -q 'class="nav"' \
    || { echo "FAIL: listing missing nav bar"; echo "$listing"; exit 1; }
echo "$listing" | grep -q 'id="ptr"' \
    && { echo "FAIL: listing still has #ptr"; echo "$listing"; exit 1; }
echo "$listing" | grep -qi 'pull to refresh' \
    && { echo "FAIL: listing still says 'pull to refresh'"; echo "$listing"; exit 1; }

# --- Product page: nav Refresh + back link, pull-to-refresh gone ---
product=$(curl -sf "http://127.0.0.1:$PORT/deployit/p/io.mikey.lillist/ios/")
echo "$product" | grep -q 'id="refresh"' \
    || { echo "FAIL: product page missing nav Refresh button"; echo "$product"; exit 1; }
echo "$product" | grep -q '← all products' \
    || { echo "FAIL: product page missing back link"; echo "$product"; exit 1; }
echo "$product" | grep -q 'id="ptr"' \
    && { echo "FAIL: product page still has #ptr"; echo "$product"; exit 1; }

# --- Served app.js: button handler present, touch gestures gone ---
appjs=$(curl -sf "http://127.0.0.1:$PORT/deployit/app.js")
echo "$appjs" | grep -q '_internal/refresh' \
    || { echo "FAIL: app.js missing _internal/refresh"; exit 1; }
echo "$appjs" | grep -q 'location.reload' \
    || { echo "FAIL: app.js missing location.reload"; exit 1; }
echo "$appjs" | grep -q 'touchstart' \
    && { echo "FAIL: app.js still binds touchstart (pull-to-refresh)"; exit 1; }
echo "$appjs" | grep -q 'PTR_THRESHOLD' \
    && { echo "FAIL: app.js still has PTR constants"; exit 1; }

# --- Served app.css: #ptr gone, button has a 44px touch target ---
appcss=$(curl -sf "http://127.0.0.1:$PORT/deployit/app.css")
echo "$appcss" | grep -q '#ptr' \
    && { echo "FAIL: app.css still styles #ptr"; exit 1; }
echo "$appcss" | grep -q 'button#refresh' \
    || { echo "FAIL: app.css missing button#refresh rule"; exit 1; }
echo "$appcss" | grep -q 'min-height: 44px' \
    || { echo "FAIL: refresh button missing 44px touch target"; exit 1; }

# --- Swipe-to-delete: served app.js + app.css carry the new markers ---
echo "$appjs" | grep -q 'pointerdown' \
    || { echo "FAIL: app.js missing pointerdown swipe handler"; exit 1; }
echo "$appjs" | grep -q 'data-delete' \
    || { echo "FAIL: app.js missing data-delete handling"; exit 1; }
echo "$appjs" | grep -q 'method: "DELETE"' \
    || { echo "FAIL: app.js missing DELETE fetch"; exit 1; }
echo "$appjs" | grep -q 'confirm(' \
    || { echo "FAIL: app.js missing delete confirmation"; exit 1; }
echo "$appcss" | grep -q '.swipe-delete' \
    || { echo "FAIL: app.css missing .swipe-delete style"; exit 1; }
echo "$appcss" | grep -q '.swipe-content' \
    || { echo "FAIL: app.css missing .swipe-content style"; exit 1; }

# --- Swap layout: equal-width pill slot/track driven by one --action-w token ---
echo "$appcss" | grep -q -- '--action-w' \
    || { echo "FAIL: app.css missing --action-w pill-width token"; exit 1; }
echo "$appcss" | grep -q '.actions-slot' \
    || { echo "FAIL: app.css missing .actions-slot style"; exit 1; }
echo "$appcss" | grep -q '.action-track' \
    || { echo "FAIL: app.css missing .action-track style"; exit 1; }
# The slot width lives in CSS alone; app.js measures it instead of hardcoding 88.
echo "$appjs" | grep -q 'getBoundingClientRect' \
    || { echo "FAIL: app.js should measure the slot width, not hardcode it"; exit 1; }
echo "$appjs" | grep -Eq 'WIDTH *= *88' \
    && { echo "FAIL: app.js still hardcodes WIDTH=88 (must match CSS — removed)"; exit 1; } || true

echo "PASS"
