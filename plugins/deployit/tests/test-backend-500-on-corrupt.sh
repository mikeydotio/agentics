#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
BUILD_ID="bogus-build"
mkdir -p "$ROOT/serve/$BUILD_ID" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
echo '{"version":1,"builds":[]}' > "$ROOT/index/builds.json"
# Missing required fields → render will KeyError
echo '{"id": "bogus-build"}' > "$ROOT/serve/$BUILD_ID/_meta.json"

PORT=18733
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT
for _ in {1..50}; do curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break; sleep 0.1; done

status=$(curl -s -o /tmp/deployit-500.body -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/$BUILD_ID/")
[[ "$status" == "500" ]] || { echo "FAIL: expected 500, got $status; body=$(cat /tmp/deployit-500.body)"; exit 1; }
grep -q '"ok": false' /tmp/deployit-500.body || { echo "FAIL: body not JSON: $(cat /tmp/deployit-500.body)"; exit 1; }
grep -q 'internal_error' /tmp/deployit-500.body || { echo "FAIL: error code missing: $(cat /tmp/deployit-500.body)"; exit 1; }
echo "PASS"
