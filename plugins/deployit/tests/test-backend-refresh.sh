#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
echo '{"version":1,"builds":[]}' > "$ROOT/index/builds.json"

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

body=$(curl -sf -X POST "http://127.0.0.1:$PORT/deployit/_internal/refresh")
echo "$body" | grep -q '"ok": true' || { echo "FAIL: refresh body=$body"; exit 1; }
echo "$body" | grep -q 'last_pull'   || { echo "FAIL: no last_pull field: $body"; exit 1; }

# Unknown POST → 404
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/deployit/_internal/nope")
[[ "$status" == "404" ]] || { echo "FAIL: unknown POST expected 404, got $status"; exit 1; }

echo "PASS"
