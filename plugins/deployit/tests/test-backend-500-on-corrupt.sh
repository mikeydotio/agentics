#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/backend-test-helper.sh"

ROOT=$(mktemp -d)
BUILD_ID="bogus-build"
mkdir -p "$ROOT/serve/$BUILD_ID" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
echo '{"version":1,"builds":[]}' > "$ROOT/index/builds.json"
# Missing required fields → render will KeyError
echo '{"id": "bogus-build"}' > "$ROOT/serve/$BUILD_ID/_meta.json"

BACKEND_PID=""
trap 'stop_backend "${BACKEND_PID:-}"; rm -rf "$ROOT"' EXIT
start_backend "$ROOT" --no-git-pull

RESPONSE_BODY="$ROOT/deployit-500.body"
status=$(curl -s -o "$RESPONSE_BODY" -w '%{http_code}' "http://127.0.0.1:$PORT/deployit/$BUILD_ID/")
[[ "$status" == "500" ]] || { echo "FAIL: expected 500, got $status; body=$(cat "$RESPONSE_BODY")"; exit 1; }
grep -q '"ok": false' "$RESPONSE_BODY" || { echo "FAIL: body not JSON: $(cat "$RESPONSE_BODY")"; exit 1; }
grep -q 'internal_error' "$RESPONSE_BODY" || { echo "FAIL: error code missing: $(cat "$RESPONSE_BODY")"; exit 1; }
echo "PASS"
