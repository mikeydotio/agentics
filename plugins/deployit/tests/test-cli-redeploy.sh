#!/usr/bin/env bash
# /deployit redeploy re-points the stable symlinks at a target plugin dir,
# repairs a legacy hash-pinned plist, and (in tests) skips launchd/kickstart/
# verify but still updates symlinks correctly. The new plist body must
# reference the stable <state>/bin/deployit-backend path, NEVER the target's
# cache-hash path.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# Sandbox: state dir, fake launchctl, skip side effects
export DEPLOYIT_STATE_DIR="$ROOT/state"
export DEPLOYIT_TAILSCALE_BIN="$TESTS_DIR/fakes/tailscale"
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/true"
export DEPLOYIT_SKIP_LAUNCHD=1
export DEPLOYIT_SKIP_KICKSTART=1
export DEPLOYIT_SKIP_VERIFY=1
export DEPLOYIT_SKIP_TAILSCALE_SERVE=1
export DEPLOYIT_SKIP_INDEX_CLONE=1

# Bootstrap once against the real plugin root so config.toml exists and
# the layout is initialized.
python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap \
    > "$ROOT/bootstrap.log" 2>&1

# Sanity: bin/deployit-backend symlink installed by bootstrap
[[ -L "$ROOT/state/bin/deployit-backend" ]] \
    || { echo "FAIL: bootstrap did not create state/bin/deployit-backend symlink"; cat "$ROOT/bootstrap.log"; exit 1; }

# Build a "fake source" plugin dir representing a dev checkout the user
# wants to redeploy from. It needs a bin/deployit-backend AND a
# tests/verify-live.sh (the redeploy command checks for the former; verify
# is skipped via DEPLOYIT_SKIP_VERIFY so its contents don't matter).
FAKE="$ROOT/fake-plugin"
mkdir -p "$FAKE/bin" "$FAKE/tests"
echo '#!/usr/bin/env python3' > "$FAKE/bin/deployit-backend"
chmod +x "$FAKE/bin/deployit-backend"
echo '#!/usr/bin/env bash' > "$FAKE/tests/verify-live.sh"
chmod +x "$FAKE/tests/verify-live.sh"

# --- Case 1: redeploy --source <fake> points the symlinks at the fake.
out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" redeploy --source "$FAKE")
echo "$out" | grep -q '"ok": true' || { echo "FAIL: redeploy not ok: $out"; exit 1; }

resolve() { python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"; }
[[ "$(resolve "$ROOT/state/_plugin_root")" == "$(resolve "$FAKE")" ]] \
    || { echo "FAIL: _plugin_root not retargeted: $(readlink "$ROOT/state/_plugin_root")"; exit 1; }
[[ "$(resolve "$ROOT/state/bin/deployit-backend")" == "$(resolve "$FAKE/bin/deployit-backend")" ]] \
    || { echo "FAIL: bin/deployit-backend not retargeted: $(readlink "$ROOT/state/bin/deployit-backend")"; exit 1; }

# --- Case 2: install a LEGACY-style plist that pins a cache-hash path, then
# redeploy without --source. The plist must be rewritten to reference the
# stable <state>/bin/deployit-backend path.
#
# We need _install_launchd's plist-write branch to actually execute, so unset
# DEPLOYIT_SKIP_LAUNCHD and override HOME to a sandbox. The fake launchctl
# (fakes/true) keeps boot* calls inert.
unset DEPLOYIT_SKIP_LAUNCHD
export HOME="$ROOT/home"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$HOME/Library/LaunchAgents/com.mikeydotio.deployit.backend.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>python3</string>
    <string>/Users/x/.claude/plugins/cache/agentics/deployit/494f3cadc2d3/bin/deployit-backend</string>
  </array>
</dict></plist>
XML

out2=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" redeploy)
echo "$out2" | grep -q '"ok": true' || { echo "FAIL: redeploy (no --source) not ok: $out2"; exit 1; }
echo "$out2" | grep -q '"plist_rewritten": true' \
    || { echo "FAIL: legacy plist should have been rewritten: $out2"; exit 1; }

# The new plist body must NOT contain the old hash-pinned path, and MUST
# reference the stable state path.
new_plist="$HOME/Library/LaunchAgents/com.mikeydotio.deployit.backend.plist"
grep -q "494f3cadc2d3" "$new_plist" \
    && { echo "FAIL: rewritten plist still contains legacy hash path"; cat "$new_plist"; exit 1; }
grep -q "$ROOT/state/bin/deployit-backend" "$new_plist" \
    || { echo "FAIL: rewritten plist missing stable script path"; cat "$new_plist"; exit 1; }
grep -q "$ROOT/state/_plugin_root" "$new_plist" \
    || { echo "FAIL: rewritten plist missing stable --plugin-root"; cat "$new_plist"; exit 1; }

# Without --source, symlinks should point at the runtime plugin root.
[[ "$(resolve "$ROOT/state/_plugin_root")" == "$(resolve "$PLUGIN_ROOT")" ]] \
    || { echo "FAIL: default redeploy did not point at runtime plugin_root: $(readlink "$ROOT/state/_plugin_root")"; exit 1; }

# --- Case 3: redeploy idempotent — running again with the now-fixed plist
# should NOT rewrite it.
out3=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" redeploy)
echo "$out3" | grep -q '"plist_rewritten": false' \
    || { echo "FAIL: second redeploy should leave plist alone: $out3"; exit 1; }

# --- Case 4: --source must reject a path without bin/deployit-backend.
BAD="$ROOT/empty-dir"
mkdir -p "$BAD"
bad_out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" redeploy --source "$BAD" 2>&1 || true)
python3 -c "
import json, sys
d = json.loads('''$bad_out''')
assert d['ok'] is False, f'expected ok=false, got: {d}'
assert 'bin/deployit-backend' in d['display'], f'expected validation msg, got: {d}'
" || { echo "FAIL: missing-backend validation: $bad_out"; exit 1; }

echo "PASS"
