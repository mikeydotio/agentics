#!/usr/bin/env bash
# _stage_macos with Sparkle enabled produces BOTH artifacts (.dmg for the web
# Download + .zip as Sparkle's enclosure), EdDSA-signs the zip, and records a
# `sparkle` object in _meta.json that survives the read-back into the index
# entry (the cross-machine constraint). With Sparkle disabled it behaves exactly
# as before: .dmg only, no `sparkle` key. The real signer is stubbed via
# DEPLOYIT_SKIP_SPARKLE_SIGN; hdiutil + ditto run for real.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v hdiutil >/dev/null && command -v ditto >/dev/null \
    || { echo "SKIP: hdiutil/ditto not available (non-macOS)"; exit 0; }

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

def make_app():
    app = state / "export" / "Lillist.app"
    (app / "Contents" / "MacOS").mkdir(parents=True, exist_ok=True)
    (app / "Contents" / "MacOS" / "Lillist").write_text("#!/bin/sh\necho hi\n")
    (app / "Contents" / "Info.plist").write_text("<plist/>")
    return app

def meta_for(build_id):
    return {
        "id": build_id, "platform": "macos", "project": "Lillist",
        "bundle_id": "io.mikey.lillist", "marketing_version": "0.1.0",
        "semver_version": None, "build_number": "5", "commit": "mac0001",
        "timestamp": "2026-05-20T09:00:00-07:00",
        "origin_host": "demo.tail.ts.net", "origin_base_url": BASE,
    }

# --- Enabled: both artifacts present, sparkle meta complete ---
os.environ["DEPLOYIT_SKIP_SPARKLE_SIGN"] = "1"
bid = "lillist-macos-20260520-090000-enabled"
mod._stage_macos(state, plugin_root, bid, make_app(), meta_for(bid),
                 False, "", {"enabled": True})
serve = state / "serve" / bid
assert (serve / "Lillist.dmg").is_file(), "dmg missing"
assert (serve / "Lillist.zip").is_file(), "zip missing — both-artifacts requirement"
meta = json.loads((serve / "_meta.json").read_text())
sp = meta.get("sparkle")
assert sp, f"sparkle meta missing: {meta}"
assert sp["zip_artifact"] == "Lillist.zip", sp
assert sp["ed_signature"] == "TEST-ED-SIGNATURE-DO-NOT-SHIP==", sp
assert sp["short_version"] == "0.1.0", sp
assert sp["version"] == "5", sp
assert sp["zip_url"].endswith(f"/{bid}/Lillist.zip"), sp
assert sp["zip_length"] == (serve / "Lillist.zip").stat().st_size, \
    f"zip_length {sp['zip_length']} != actual {(serve/'Lillist.zip').stat().st_size}"
# primary_artifact stays the dmg (the web Download button)
assert meta["primary_artifact"] == "Lillist.dmg", meta

# --- Read-back propagation: sparkle survives the exact transform cmd_deploy
#     applies before _append_to_index (json load, pop primary_artifact, add
#     size/archived/notes). _append_to_index then appends the entry verbatim
#     (covered by test-cli-deploy-autoprune.sh). ---
entry = json.loads((serve / "_meta.json").read_text())
entry.pop("primary_artifact")
entry["size_bytes"], entry["archived"], entry["notes"] = 1, False, None
assert entry.get("sparkle", {}).get("ed_signature") == "TEST-ED-SIGNATURE-DO-NOT-SHIP==", \
    "sparkle dropped on the way into the index entry"

# --- Disabled: no zip, no sparkle key, dmg still produced (backward-compat) ---
bid2 = "lillist-macos-20260520-090000-disabled"
mod._stage_macos(state, plugin_root, bid2, make_app(), meta_for(bid2),
                 False, "", {"enabled": False})
serve2 = state / "serve" / bid2
assert (serve2 / "Lillist.dmg").is_file(), "dmg missing on disabled path"
assert not (serve2 / "Lillist.zip").exists(), "zip must not exist when Sparkle disabled"
assert "sparkle" not in json.loads((serve2 / "_meta.json").read_text()), \
    "sparkle key must be absent when disabled"

print("ok")
PY

echo "PASS"
