#!/usr/bin/env bash
# Version label: when a build recorded a semver_version at deploy time the UI
# shows it (e.g. "v2.16.1 (build 20)"); otherwise it falls back to the app's
# build number ("build 7") and the marketing_version is NOT shown. Covers both
# the listing rows and the per-build landing page.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

SEMVER_ID="lillist-ios-20260601-100000-sem1234"
PLAIN_ID="other-ios-20260601-110000-pln5678"

cat > "$ROOT/index/builds.json" <<JSON
{
  "version": 1,
  "builds": [
    {
      "id": "$SEMVER_ID",
      "platform": "ios", "project": "Lillist",
      "bundle_id": "io.mikeydotio.Lillist",
      "marketing_version": "0.1.0", "semver_version": "v2.16.1",
      "build_number": "20", "commit": "sem1234",
      "timestamp": "2026-06-01T10:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"itms-services","manifest_url":"https://x/m.plist","ipa_url":"https://x/a.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    },
    {
      "id": "$PLAIN_ID",
      "platform": "ios", "project": "Other",
      "bundle_id": "io.mikeydotio.Other",
      "marketing_version": "1.2.3", "semver_version": null,
      "build_number": "7", "commit": "pln5678",
      "timestamp": "2026-06-01T11:00:00-07:00",
      "origin_host": "studio.tail-abc.ts.net",
      "origin_base_url": "https://studio.tail-abc.ts.net/deployit",
      "install": {"kind":"itms-services","manifest_url":"https://y/m.plist","ipa_url":"https://y/a.ipa"},
      "size_bytes": 1, "archived": false, "notes": null
    }
  ]
}
JSON

# Per-build _meta.json so the landing pages render.
mkdir -p "$ROOT/serve/$SEMVER_ID" "$ROOT/serve/$PLAIN_ID"
cat > "$ROOT/serve/$SEMVER_ID/_meta.json" <<JSON
{"id":"$SEMVER_ID","platform":"ios","project":"Lillist","bundle_id":"io.mikeydotio.Lillist","marketing_version":"0.1.0","semver_version":"v2.16.1","build_number":"20","commit":"sem1234","timestamp":"2026-06-01T10:00:00-07:00","origin_host":"studio.tail-abc.ts.net","origin_base_url":"https://studio.tail-abc.ts.net/deployit","install":{"kind":"itms-services","manifest_url":"https://x/m.plist","ipa_url":"https://x/a.ipa"}}
JSON
cat > "$ROOT/serve/$PLAIN_ID/_meta.json" <<JSON
{"id":"$PLAIN_ID","platform":"ios","project":"Other","bundle_id":"io.mikeydotio.Other","marketing_version":"1.2.3","semver_version":null,"build_number":"7","commit":"pln5678","timestamp":"2026-06-01T11:00:00-07:00","origin_host":"studio.tail-abc.ts.net","origin_base_url":"https://studio.tail-abc.ts.net/deployit","install":{"kind":"itms-services","manifest_url":"https://y/m.plist","ipa_url":"https://y/a.ipa"}}
JSON

PORT=18743
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT

for _ in {1..50}; do
    curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break
    sleep 0.1
done

# --- Listing rows ---
listing=$(curl -sf "http://127.0.0.1:$PORT/deployit/")
echo "$listing" | grep -q "Lillist · iOS · v2.16.1 (build 20)" \
    || { echo "FAIL: semver row label wrong"; echo "$listing"; exit 1; }
echo "$listing" | grep -q "Other · iOS · build 7" \
    || { echo "FAIL: non-semver row label wrong"; echo "$listing"; exit 1; }
echo "$listing" | grep -q "0.1.0" \
    && { echo "FAIL: marketing_version 0.1.0 leaked into semver row"; echo "$listing"; exit 1; }
echo "$listing" | grep -q "1.2.3" \
    && { echo "FAIL: marketing_version 1.2.3 leaked into non-semver row"; echo "$listing"; exit 1; }

# --- Per-build landing pages (Version <dd>) ---
sem_landing=$(curl -sf "http://127.0.0.1:$PORT/deployit/$SEMVER_ID/")
echo "$sem_landing" | grep -q "<dd>v2.16.1 (build 20)</dd>" \
    || { echo "FAIL: semver landing label wrong"; echo "$sem_landing"; exit 1; }
plain_landing=$(curl -sf "http://127.0.0.1:$PORT/deployit/$PLAIN_ID/")
echo "$plain_landing" | grep -q "<dd>build 7</dd>" \
    || { echo "FAIL: non-semver landing label wrong"; echo "$plain_landing"; exit 1; }

echo "PASS"
