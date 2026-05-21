#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
echo '{"version":1,"builds":[]}' > "$ROOT/index/builds.json"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

PORT=18729
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT

for _ in {1..50}; do
    if curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" > /dev/null; then
        break
    fi
    sleep 0.1
done

body=$(curl -sf "http://127.0.0.1:$PORT/deployit/_healthz")
echo "$body" | grep -q '"ok": true' || { echo "FAIL: body=$body"; cat "$ROOT/backend.log"; exit 1; }
echo "PASS"
