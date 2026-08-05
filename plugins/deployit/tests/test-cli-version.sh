#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" --version) \
    || { echo "FAIL: --version exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"version": "0.1.0"' || { echo "FAIL: no version field"; exit 1; }
echo "$out" | grep -q '"ok": true'         || { echo "FAIL: ok not true"; exit 1; }
echo "PASS"
