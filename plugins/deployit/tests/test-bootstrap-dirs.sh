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

# The `|| { ... }` is load-bearing, not defensive noise. deployit-cli's fail()
# prints its JSON diagnosis to STDOUT and exits 1, so an unguarded capture under
# `set -e` kills the script HERE with the diagnosis sealed inside $out and never
# printed — 0 bytes on stdout and stderr, and the runner reports a bare
# `FAIL (exit 1)` with an empty log. That is AGE-35: the reason the 2026-08-04
# failure was undiagnosable even from a full log. The grep below cannot cover it,
# because it is only reached when the CLI exits 0, and ok() always prints
# `"ok": true` when it does.
out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap) \
    || { echo "FAIL: bootstrap exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"ok": true' || { echo "FAIL: not ok: $out"; exit 1; }

[[ -d "$ROOT/serve" && -d "$ROOT/index" && -d "$ROOT/logs" && -d "$ROOT/bin" ]] \
    || { echo "FAIL: directory layout missing (serve/index/logs/bin)"; ls "$ROOT"; exit 1; }
[[ -f "$ROOT/config.toml" ]] || { echo "FAIL: config.toml missing"; exit 1; }
grep -q 'base_url = "https://studio.tail-abc.ts.net/deployit"' "$ROOT/config.toml" \
    || { echo "FAIL: base_url not derived"; cat "$ROOT/config.toml"; exit 1; }

# _plugin_root symlink created (CLI's responsibility, mirrors backend's --plugin-root)
[[ -L "$ROOT/_plugin_root" ]] \
    || { echo "FAIL: _plugin_root symlink missing"; exit 1; }

# bin/deployit-backend symlink created (stable indirection for launchd)
[[ -L "$ROOT/bin/deployit-backend" ]] \
    || { echo "FAIL: bin/deployit-backend symlink missing"; ls -l "$ROOT/bin/"; exit 1; }
[[ "$(readlink "$ROOT/bin/deployit-backend")" == "$PLUGIN_ROOT/bin/deployit-backend" ]] \
    || { echo "FAIL: bin/deployit-backend target wrong: $(readlink "$ROOT/bin/deployit-backend")"; exit 1; }

# Re-run is idempotent
out2=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap) \
    || { echo "FAIL: second bootstrap exited $? — the CLI said: $out2"; exit 1; }
echo "$out2" | grep -q '"ok": true' || { echo "FAIL: second run not ok: $out2"; exit 1; }

echo "PASS"
