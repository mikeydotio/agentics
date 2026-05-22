#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Sandbox the bootstrap target to a tempdir so we don't touch the real machine.
ROOT=$(mktemp -d)
export DEPLOYIT_STATE_DIR="$ROOT"
export DEPLOYIT_TAILSCALE_BIN="$TESTS_DIR/fakes/tailscale"
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/true"
export DEPLOYIT_SKIP_LAUNCHD=1
export DEPLOYIT_SKIP_TAILSCALE_SERVE=1
export DEPLOYIT_SKIP_INDEX_CLONE=1
trap 'rm -rf "$ROOT"' EXIT

out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap)
echo "$out" | grep -q '"ok": true' || { echo "FAIL: not ok: $out"; exit 1; }

[[ -d "$ROOT/serve" && -d "$ROOT/index" && -d "$ROOT/logs" && -d "$ROOT/bin" ]] \
    || { echo "FAIL: directory layout missing (serve/index/logs/bin)"; ls "$ROOT"; exit 1; }
[[ -f "$ROOT/config.toml" ]] || { echo "FAIL: config.toml missing"; exit 1; }
grep -q 'base_url = "https://studio.tail-abc.ts.net/deployit"' "$ROOT/config.toml" \
    || { echo "FAIL: base_url not derived"; cat "$ROOT/config.toml"; exit 1; }

# _plugin_root symlink created (CLI's responsibility, mirrors backend's --plugin-root)
[[ -L "$ROOT/_plugin_root" ]] \
    || { echo "FAIL: _plugin_root symlink missing"; exit 1; }

# Re-run is idempotent
out2=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap)
echo "$out2" | grep -q '"ok": true' || { echo "FAIL: second run not ok"; exit 1; }

echo "PASS"
