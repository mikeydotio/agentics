#!/usr/bin/env bash
# Shared lifecycle for backend fixtures that need a real loopback server.

start_backend() {
    local root="$1"
    shift
    local candidate=""

    PORT=""
    python3 "$PLUGIN_ROOT/bin/deployit-backend" --port 0 --root "$root" "$@" \
        > "$root/backend.log" 2>&1 &
    BACKEND_PID=$!

    for _ in {1..50}; do
        if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
            echo "FAIL: backend exited before it became healthy"
            cat "$root/backend.log"
            wait "$BACKEND_PID" 2>/dev/null || true
            return 1
        fi

        candidate=$(sed -n \
            's/^backend: listening on 127\.0\.0\.1:\([0-9][0-9]*\), root=.*/\1/p' \
            "$root/backend.log" | head -n 1)
        if [[ "$candidate" =~ ^[1-9][0-9]*$ ]] \
            && (( candidate <= 65535 )) \
            && curl -sf "http://127.0.0.1:$candidate/deployit/_healthz" >/dev/null; then
            # Output for the sourcing fixture, which uses this global in URLs.
            # shellcheck disable=SC2034
            PORT="$candidate"
            return 0
        fi
        sleep 0.1
    done

    echo "FAIL: backend did not report a healthy assigned port"
    cat "$root/backend.log"
    stop_backend "$BACKEND_PID"
    BACKEND_PID=""
    return 1
}

stop_backend() {
    local pid="${1:-}"
    [[ -n "$pid" ]] || return 0
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}
