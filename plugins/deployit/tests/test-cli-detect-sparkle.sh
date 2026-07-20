#!/usr/bin/env bash
# Sparkle app detection (issue #111): deployit inspects the BUILT app for
# Sparkle.framework + SUFeedURL/SUPublicEDKey independent of [macos.sparkle]
# enabled, and warns on every config-vs-app mismatch rather than silently
# no-op'ing either direction. Detection is advisory only — `enabled` stays the
# sole actuator for producing/signing the appcast.
#
# Covers: _detect_sparkle_in_app (real PlistBuddy + filesystem probes against
# fixture .app bundles), _sparkle_mismatch_warnings (pure logic, all branches),
# and _stage_macos writing an unconditional `sparkle_detect` into _meta.json
# that survives to _stage_macos's output but is meant to be popped before the
# entry reaches the shared index (mirrors the existing release_zip pop).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v hdiutil >/dev/null && command -v ditto >/dev/null \
    && command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: hdiutil/ditto/PlistBuddy not available (non-macOS)"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, json, os, pathlib, sys

plugin_root = pathlib.Path(sys.argv[1])
state = pathlib.Path(sys.argv[2])

loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

(state / "serve").mkdir(parents=True, exist_ok=True)
BASE = "https://demo.tail.ts.net/deployit"
os.environ["DEPLOYIT_SKIP_SPARKLE_SIGN"] = "1"

import subprocess


def make_app(name, *, framework=False, feed_url=None, public_ed_key=None):
    app = state / "export" / name
    (app / "Contents" / "MacOS").mkdir(parents=True, exist_ok=True)
    (app / "Contents" / "MacOS" / name.replace(".app", "")).write_text("#!/bin/sh\necho hi\n")
    plist = app / "Contents" / "Info.plist"
    plist.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict/></plist>\n'
    )
    if feed_url:
        subprocess.run(["/usr/libexec/PlistBuddy", "-c",
                        f"Add :SUFeedURL string {feed_url}", str(plist)],
                       check=True, capture_output=True)
    if public_ed_key:
        subprocess.run(["/usr/libexec/PlistBuddy", "-c",
                        f"Add :SUPublicEDKey string {public_ed_key}", str(plist)],
                       check=True, capture_output=True)
    if framework:
        (app / "Contents" / "Frameworks" / "Sparkle.framework").mkdir(parents=True, exist_ok=True)
    return app


def meta_for(build_id):
    return {
        "id": build_id, "platform": "macos", "project": "Lillist",
        "bundle_id": "io.mikey.lillist", "marketing_version": "0.1.0",
        "semver_version": None, "build_number": "5", "commit": "mac0001",
        "timestamp": "2026-05-20T09:00:00-07:00",
        "origin_host": "demo.tail.ts.net", "origin_base_url": BASE,
    }


# --- _detect_sparkle_in_app: direct probes against real fixture bundles ---
wired = make_app("Wired.app", framework=True, feed_url="https://example.com/appcast.xml",
                 public_ed_key="PUBKEY==")
d = mod._detect_sparkle_in_app(wired)
assert d == {"framework": True, "feed_url": "https://example.com/appcast.xml",
            "public_ed_key": "PUBKEY=="}, d

bare = make_app("Bare.app", framework=False)
d = mod._detect_sparkle_in_app(bare)
assert d == {"framework": False, "feed_url": None, "public_ed_key": None}, d

# --- _sparkle_mismatch_warnings: pure logic, every branch ---
def warning_kinds(detect, enabled):
    return [w for w in mod._sparkle_mismatch_warnings(detect, enabled)]

# Agreement — no warnings either way.
assert mod._sparkle_mismatch_warnings({"framework": False, "feed_url": None}, False) == []
assert mod._sparkle_mismatch_warnings(
    {"framework": True, "feed_url": "https://x/appcast.xml"}, True) == []

# enabled=true, app has no framework.
w = warning_kinds({"framework": False, "feed_url": None}, True)
assert len(w) == 1 and "no way to check it" in w[0], w

# enabled=false, app IS wired — the #111 silent-failure case. Feed URL surfaces.
w = warning_kinds({"framework": True, "feed_url": "https://x/appcast.xml"}, False)
assert len(w) == 1 and "silently not work" in w[0] and "https://x/appcast.xml" in w[0], w

# enabled=true, framework present, no SUFeedURL.
w = warning_kinds({"framework": True, "feed_url": None}, True)
assert len(w) == 1 and "no SUFeedURL" in w[0], w

# --- _stage_macos: unconditional detection lands in _meta.json regardless of
#     `enabled`, using the real PlistBuddy/filesystem probe on the staged app
#     (staging_app, not the pre-move app_src) ---
bid_a = "lillist-macos-20260520-090000-mismatch-a"
mod._stage_macos(state, plugin_root, bid_a,
                 make_app("Lillist.app", framework=True, feed_url="https://x/appcast.xml"),
                 meta_for(bid_a), False, "", {"enabled": False})
meta_a = json.loads((state / "serve" / bid_a / "_meta.json").read_text())
assert meta_a["sparkle_detect"] == {
    "framework": True, "feed_url": "https://x/appcast.xml", "public_ed_key": None,
}, meta_a["sparkle_detect"]
assert "sparkle" not in meta_a, "enabled=False must not produce a signed sparkle zip"

bid_b = "lillist-macos-20260520-090000-mismatch-b"
mod._stage_macos(state, plugin_root, bid_b, make_app("Lillist.app", framework=False),
                 meta_for(bid_b), False, "", {"enabled": True})
meta_b = json.loads((state / "serve" / bid_b / "_meta.json").read_text())
assert meta_b["sparkle_detect"] == {"framework": False, "feed_url": None, "public_ed_key": None}, \
    meta_b["sparkle_detect"]
assert meta_b.get("sparkle"), "enabled=True must still sign a zip even without a framework"

# --- Read-back: sparkle_detect must be POPPED before the entry reaches the
#     shared index (mirrors cmd_deploy's release_zip pop) — advisory local
#     detail, not part of the cross-machine builds.json contract. ---
entry = json.loads((state / "serve" / bid_a / "_meta.json").read_text())
entry.pop("primary_artifact")
entry["size_bytes"], entry["archived"], entry["notes"] = 1, False, None
entry.pop("release_zip", None)
sparkle_detect = entry.pop("sparkle_detect", None)
assert sparkle_detect is not None, "sparkle_detect should have been captured before popping"
assert "sparkle_detect" not in entry, "sparkle_detect leaked into the would-be index entry"

print("ok")
PY

echo "PASS"
