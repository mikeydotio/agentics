#!/usr/bin/env bash
# The test runner must keep Python's import cache out of the source checkout.

set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CACHE_DIR="$PLUGIN_ROOT/bin/__pycache__"

[[ ! -e "$CACHE_DIR" ]] \
    || { echo "FAIL: bytecode cache existed before the probe: $CACHE_DIR"; exit 1; }

python3 "$PLUGIN_ROOT/bin/deployit-backend" --help >/dev/null

[[ ! -e "$CACHE_DIR" ]] \
    || { echo "FAIL: Python wrote bytecode into the source checkout: $CACHE_DIR"; exit 1; }

echo "PASS"
