#!/usr/bin/env bash
# issue #117: a Sparkle-enabled macOS deploy that CANNOT EdDSA-sign must not
# publish an unsigned GitHub release. `release=True` on _stage_macos means
# "this deploy will publish a release" — a signing failure on that path must
# be FATAL (SystemExit(1), nothing staged claims success), never a warn-and-
# continue. `release=False` keeps the pre-#117 tailnet degradation, covered
# by test-cli-stage-macos-no-sparkle-tools.sh.
#
# The stub also exits non-zero with EMPTY stdout/stderr and is marked
# quarantined — the exact Gatekeeper-kill signature from the issue's Lillist
# v0.19.0 postmortem — so this also covers AC 3 (name the resolved binary,
# identify quarantine/Gatekeeper as the cause).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v hdiutil >/dev/null && command -v ditto >/dev/null && command -v xattr >/dev/null \
    || { echo "SKIP: hdiutil/ditto/xattr not available (non-macOS)"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# A sign_update stub that fails exactly the way Gatekeeper kills a quarantined,
# adhoc-signed binary: non-zero exit, nothing on stdout OR stderr.
STUB="$ROOT/sign_update"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$STUB"
xattr -w com.apple.quarantine "0081;00000000;deployit-test;" "$STUB"

STDOUT_LOG="$ROOT/stdout.log"
STDERR_LOG="$ROOT/stderr.log"

set +e
DEPLOYIT_SPARKLE_SIGN_UPDATE="$STUB" \
python3 - "$PLUGIN_ROOT" "$ROOT" >"$STDOUT_LOG" 2>"$STDERR_LOG" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys

plugin_root = pathlib.Path(sys.argv[1])
state = pathlib.Path(sys.argv[2])

loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

(state / "serve").mkdir(parents=True, exist_ok=True)
app = state / "export" / "Lillist.app"
(app / "Contents" / "MacOS").mkdir(parents=True, exist_ok=True)
(app / "Contents" / "MacOS" / "Lillist").write_text("#!/bin/sh\necho hi\n")

meta = {
    "id": "lillist-macos-release-nosign", "platform": "macos", "project": "Lillist",
    "bundle_id": "io.mikey.lillist", "marketing_version": "0.19.0",
    "semver_version": None, "build_number": "9", "commit": "mac0002",
    "timestamp": "2026-07-29T09:00:00-07:00",
    "origin_host": "demo.tail.ts.net",
    "origin_base_url": "https://demo.tail.ts.net/deployit",
}

# release=True: this build is about to publish a GitHub release. Signing
# fails, so this call must never return — it should exit the process via
# fail() before staging anything that could be mistaken for a success.
mod._stage_macos(state, plugin_root, "lillist-macos-release-nosign", app, meta,
                 False, "", {"enabled": True}, release=True)
print("UNREACHABLE: _stage_macos returned despite a failed sign on a release deploy")
PY
STATUS=$?
set -e

[[ "$STATUS" -eq 1 ]] \
    || { echo "FAIL: expected exit 1, got $STATUS"; cat "$STDOUT_LOG" "$STDERR_LOG"; exit 1; }

grep -q "UNREACHABLE" "$STDOUT_LOG" \
    && { echo "FAIL: _stage_macos returned instead of failing the deploy"; exit 1; }

# fail() prints {"ok": false, "display": "..."} JSON to stdout.
python3 - "$STDOUT_LOG" "$STUB" <<'PY'
import json, sys
log, stub = sys.argv[1], sys.argv[2]
with open(log) as f:
    text = f.read()
payload = json.loads(text)
assert payload.get("ok") is False, payload
display = payload["display"]
assert "refusing to ship an unsigned release" in display, display
assert stub in display, f"resolved binary path not named in failure: {display!r}"
assert "quarantine" in display.lower(), f"quarantine cause not identified: {display!r}"
assert "xattr -d com.apple.quarantine" in display, f"fix not named: {display!r}"
print("ok")
PY

# Nothing was left claiming success: no dmg/serve dir survives a failed
# release-gated stage (the whole _stage_macos call aborted mid-way).
[[ ! -f "$ROOT/serve/lillist-macos-release-nosign/Lillist.dmg" ]] \
    || { echo "FAIL: a dmg was staged despite the fatal signing failure"; exit 1; }

echo "PASS"
