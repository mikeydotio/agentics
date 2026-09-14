#!/usr/bin/env bash
# Backend fixtures must use kernel-assigned ports and per-fixture files.

set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
ROOT_A=$(mktemp -d)
ROOT_B=$(mktemp -d)
PID_A=""
PID_B=""

cleanup() {
    [[ -z "$PID_A" ]] || kill "$PID_A" 2>/dev/null || true
    [[ -z "$PID_B" ]] || kill "$PID_B" 2>/dev/null || true
    [[ -z "$PID_A" ]] || wait "$PID_A" 2>/dev/null || true
    [[ -z "$PID_B" ]] || wait "$PID_B" 2>/dev/null || true
    rm -rf "$ROOT_A" "$ROOT_B"
}
trap cleanup EXIT

prepare_root() {
    local root="$1"
    mkdir -p "$root/serve" "$root/index" "$root/logs"
    ln -sf "$PLUGIN_ROOT" "$root/_plugin_root"
    printf '%s\n' '{"version":1,"builds":[]}' > "$root/index/builds.json"
}

reported_port() {
    sed -n 's/^backend: listening on 127\.0\.0\.1:\([0-9][0-9]*\), root=.*/\1/p' "$1" \
        | head -n 1
}

prepare_root "$ROOT_A"
prepare_root "$ROOT_B"

python3 "$PLUGIN_ROOT/bin/deployit-backend" --port 0 --root "$ROOT_A" --no-git-pull \
    > "$ROOT_A/backend.log" 2>&1 &
PID_A=$!
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port 0 --root "$ROOT_B" --no-git-pull \
    > "$ROOT_B/backend.log" 2>&1 &
PID_B=$!

PORT_A=""
PORT_B=""
for _ in {1..50}; do
    kill -0 "$PID_A" 2>/dev/null \
        || { echo "FAIL: first backend exited"; cat "$ROOT_A/backend.log"; exit 1; }
    kill -0 "$PID_B" 2>/dev/null \
        || { echo "FAIL: second backend exited"; cat "$ROOT_B/backend.log"; exit 1; }
    PORT_A=$(reported_port "$ROOT_A/backend.log")
    PORT_B=$(reported_port "$ROOT_B/backend.log")
    if [[ "$PORT_A" =~ ^[1-9][0-9]*$ && "$PORT_B" =~ ^[1-9][0-9]*$ ]]; then
        curl -sf "http://127.0.0.1:$PORT_A/deployit/_healthz" >/dev/null \
            && curl -sf "http://127.0.0.1:$PORT_B/deployit/_healthz" >/dev/null \
            && break
    fi
    sleep 0.1
done

[[ "$PORT_A" =~ ^[1-9][0-9]*$ ]] \
    || { echo "FAIL: first backend did not report its assigned port"; cat "$ROOT_A/backend.log"; exit 1; }
[[ "$PORT_B" =~ ^[1-9][0-9]*$ ]] \
    || { echo "FAIL: second backend did not report its assigned port"; cat "$ROOT_B/backend.log"; exit 1; }
[[ "$PORT_A" != "$PORT_B" ]] \
    || { echo "FAIL: concurrent backends reported the same port: $PORT_A"; exit 1; }
curl -sf "http://127.0.0.1:$PORT_A/deployit/_healthz" >/dev/null \
    || { echo "FAIL: first backend is not healthy on $PORT_A"; exit 1; }
curl -sf "http://127.0.0.1:$PORT_B/deployit/_healthz" >/dev/null \
    || { echo "FAIL: second backend is not healthy on $PORT_B"; exit 1; }

fixture_count=0
for fixture in "$TESTS_DIR"/test-backend-*.sh; do
    [[ "$fixture" == "$TESTS_DIR/test-backend-isolation.sh" ]] && continue
    ((fixture_count += 1))
    grep -q '^source "$TESTS_DIR/backend-test-helper.sh"$' "$fixture" \
        || { echo "FAIL: $(basename "$fixture") does not source the shared helper"; exit 1; }
    grep -q '^start_backend "$ROOT"' "$fixture" \
        || { echo "FAIL: $(basename "$fixture") does not use start_backend"; exit 1; }
    if grep -Eq '^PORT=[0-9]+' "$fixture"; then
        echo "FAIL: $(basename "$fixture") retains a fixed port"
        exit 1
    fi
done

[[ "$fixture_count" -eq 14 ]] \
    || { echo "FAIL: expected 14 backend fixtures, found $fixture_count"; exit 1; }
shared_tmp="/tmp"
shared_body="$shared_tmp/deployit-500.body"
! grep -Fq "$shared_body" "$TESTS_DIR/test-backend-500-on-corrupt.sh" \
    || { echo "FAIL: corrupt-index response still uses the shared /tmp path"; exit 1; }

echo "PASS"
