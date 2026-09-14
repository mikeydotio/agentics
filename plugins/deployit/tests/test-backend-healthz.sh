#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
echo '{"version":1,"builds":[]}' > "$ROOT/index/builds.json"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT"

body=$(curl -sf "http://127.0.0.1:$PORT/deployit/_healthz")
echo "$body" | grep -q '"ok": true' || { echo "FAIL: body=$body"; cat "$ROOT/backend.log"; exit 1; }
echo "PASS"
