#!/usr/bin/env bash
# verify-live.sh — assert the running deployit backend is serving the expected
# new-code markers. Exits 0 on full pass, 1 on any failure.
#
# Usage:
#   verify-live.sh [--port N]
#
# Defaults: port from $DEPLOYIT_STATE_DIR/config.toml (else
# ~/Library/Application Support/deployit/config.toml). The state dir's
# index/builds.json (if present) is used to derive the expected product count.
set -uo pipefail

PORT=""
STATE_DIR="${DEPLOYIT_STATE_DIR:-$HOME/Library/Application Support/deployit}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2;;
        --state-dir) STATE_DIR="$2"; shift 2;;
        *) echo "verify-live: unknown arg: $1" >&2; exit 2;;
    esac
done

if [[ -z "$PORT" ]]; then
    cfg="$STATE_DIR/config.toml"
    if [[ ! -f "$cfg" ]]; then
        echo "verify-live: no --port and no config at $cfg" >&2
        exit 2
    fi
    PORT=$(python3 -c "
import sys
try:
    import tomllib as t
except ImportError:
    import tomli as t
print(t.loads(open('$cfg').read())['server']['port'])
") || { echo 'verify-live: failed to parse port from config'; exit 2; }
fi

BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

# 1. healthz
body=$(curl -sf "$BASE/deployit/_healthz" 2>/dev/null) \
    && [[ "$body" == *'"ok": true'* || "$body" == *'"ok":true'* ]] \
    && pass "GET /deployit/_healthz returns ok:true" \
    || fail "GET /deployit/_healthz" "got: ${body:-<connection failed>}"

# 2. static assets present
check_static() {
    local path="$1" ctype_prefix="$2"
    local headers status
    headers=$(curl -sf -o /dev/null -D - "$BASE$path" 2>/dev/null) \
        || { fail "GET $path (200)" "non-200 or connection failed"; return; }
    status=$(printf '%s' "$headers" | head -1)
    if printf '%s' "$headers" | grep -iq "^content-type: ${ctype_prefix}"; then
        pass "GET $path serves $ctype_prefix*"
    else
        fail "GET $path content-type" "expected ${ctype_prefix}*, got headers: $(printf '%s' "$headers" | grep -i content-type)"
    fi
}
check_static /deployit/app.css "text/css"
check_static /deployit/app.js  "application/javascript"

# 3. listing HTML carries the nav-bar markers (pull-to-refresh removed)
listing=$(curl -sf "$BASE/deployit/" 2>/dev/null) \
    || { fail "GET /deployit/" "non-200 or connection failed"; listing=""; }
if [[ -n "$listing" ]]; then
    grep -q 'href="/deployit/app.css"' <<<"$listing" \
        && pass "listing references app.css" \
        || fail "listing references app.css" "missing <link rel=stylesheet ...app.css>"
    grep -q 'src="/deployit/app.js"' <<<"$listing" \
        && pass "listing references app.js" \
        || fail "listing references app.js" "missing <script src=...app.js>"
    grep -q 'id="refresh"' <<<"$listing" \
        && pass "listing has nav Refresh button" \
        || fail "listing has #refresh" "missing nav-bar refresh button"
    grep -q 'id="ptr"' <<<"$listing" \
        && fail "listing still has #ptr" "pull-to-refresh should be removed" \
        || pass "listing has no #ptr (pull-to-refresh removed)"
fi

# 3b. served app.js is the nav-bar version (no pull-to-refresh gesture)
appjs=$(curl -sf "$BASE/deployit/app.js" 2>/dev/null || true)
if [[ -n "$appjs" ]]; then
    grep -q '_internal/refresh' <<<"$appjs" \
        && pass "app.js posts to _internal/refresh" \
        || fail "app.js refresh handler" "served app.js missing _internal/refresh"
    grep -q 'touchstart' <<<"$appjs" \
        && fail "app.js still has pull-to-refresh" "touchstart present in served app.js" \
        || pass "app.js has no pull-to-refresh (touchstart gone)"
fi

# 4. data-href + row-count vs distinct products
builds_json="$STATE_DIR/index/builds.json"
if [[ -f "$builds_json" && -n "$listing" ]]; then
    expected_products=$(python3 -c "
import json
d = json.load(open('$builds_json'))
seen = set()
for b in d.get('builds', []):
    seen.add((b.get('bundle_id'), b.get('platform')))
print(len(seen))
")
    actual_rows=$(grep -c '<li ' <<<"$listing" || true)
    actual_dh=$(grep -c 'data-href="/deployit/p/' <<<"$listing" || true)

    if (( expected_products == 0 )); then
        (( actual_rows == 0 )) && pass "empty index → 0 rows" \
            || fail "empty index" "expected 0 rows, got $actual_rows"
    else
        (( actual_rows == expected_products )) \
            && pass "row count = $expected_products distinct products" \
            || fail "row count mismatch" "expected $expected_products, got $actual_rows"
        (( actual_dh >= 1 )) \
            && pass "rows carry data-href to product pages" \
            || fail "data-href missing" "no row had data-href=/deployit/p/..."

        # First product page must 200 and carry the back link
        first_path=$(grep -o 'data-href="/deployit/p/[^"]*"' <<<"$listing" \
            | head -1 | sed -E 's/data-href="([^"]+)"/\1/')
        if [[ -n "$first_path" ]]; then
            pbody=$(curl -sf "$BASE$first_path" 2>/dev/null) \
                && grep -q '← all products' <<<"$pbody" \
                && pass "product page $first_path returns 200 + back link" \
                || fail "product page" "GET $first_path failed or missing back link"
        fi
    fi
fi

printf '\nverify-live: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
