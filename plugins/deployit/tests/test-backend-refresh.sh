#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
echo '{"version":1,"builds":[]}' > "$ROOT/index/builds.json"

PORT=18732
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT
for _ in {1..50}; do curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break; sleep 0.1; done

body=$(curl -sf -X POST "http://127.0.0.1:$PORT/deployit/_internal/refresh")
echo "$body" | grep -q '"ok": true' || { echo "FAIL: refresh body=$body"; exit 1; }
echo "$body" | grep -q 'last_pull'   || { echo "FAIL: no last_pull field: $body"; exit 1; }

# Unknown POST → 404
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/deployit/_internal/nope")
[[ "$status" == "404" ]] || { echo "FAIL: unknown POST expected 404, got $status"; exit 1; }

echo "PASS"
