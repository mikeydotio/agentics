#!/usr/bin/env bash
# deployit-release --appcast-signature (issue #111): publishes a single-item
# Sparkle appcast.xml alongside the zip asset, with an <enclosure> pointing at
# the tag-pinned release download and a stable
# releases/latest/download/appcast.xml feed URL. Covers: _build_appcast_asset
# content (unit-tested directly — the CLI's own tempdir is cleaned up before a
# separate process could read it back, so content assertions live here rather
# than against a `--dry-run` subprocess); GitHub's asset-name normalization
# (spaces -> '.') is matched on our side so the enclosure URL is never wrong;
# the appcast asset flows through both create and clobber; and --app (not
# --zip) is refused, since --app re-archives via ditto and the signature was
# computed over --zip's exact bytes.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v ditto >/dev/null && command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: ditto/PlistBuddy unavailable (non-macOS)"; exit 0; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# --- _build_appcast_asset + _github_asset_name: direct unit coverage of the
#     rendered content and the filename-normalization contract. ---
python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, subprocess, sys

plugin_root = pathlib.Path(sys.argv[1]); root = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("drel", str(plugin_root / "bin" / "deployit-release"))
spec = importlib.util.spec_from_loader("drel", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

app = root / "Hello.app"
(app / "Contents" / "MacOS").mkdir(parents=True)
subprocess.run(["/usr/libexec/PlistBuddy", "-c",
                "Add :CFBundleShortVersionString string 1.5.0", str(app / "Contents" / "Info.plist")],
               check=True, capture_output=True)
subprocess.run(["/usr/libexec/PlistBuddy", "-c",
                "Add :CFBundleVersion string 42", str(app / "Contents" / "Info.plist")],
               check=True, capture_output=True)

tmpd = root / "tmpd"; tmpd.mkdir()
appcast_path, enclosure_url = mod._build_appcast_asset(
    app, "me/Hello", "1.5.0", "Hello.zip", 12345, "SIGA==", "1.5.0", tmpd)
assert appcast_path == tmpd / "appcast.xml", appcast_path
assert enclosure_url == "https://github.com/me/Hello/releases/download/1.5.0/Hello.zip", enclosure_url

text = appcast_path.read_text()
assert 'sparkle:edSignature="SIGA=="' in text, text
assert "<sparkle:version>42</sparkle:version>" in text, text
assert "<sparkle:shortVersionString>1.5.0</sparkle:shortVersionString>" in text, text
assert 'url="https://github.com/me/Hello/releases/download/1.5.0/Hello.zip"' in text, text
assert 'length="12345"' in text, text

import xml.dom.minidom as minidom
minidom.parseString(text)

# Filename normalization: spaces (and any other unsafe char) become '.', and
# the result is idempotent under a second pass (already-safe names untouched).
assert mod._github_asset_name("My App.zip") == "My.App.zip"
assert mod._github_asset_name("Hello.zip") == "Hello.zip"
assert mod._github_asset_name("a(b)c.zip") == "a.b.c.zip"
norm = mod._github_asset_name("My App.zip")
assert mod._github_asset_name(norm) == norm, "normalization must be idempotent"

print("ok")
PY

# --- CLI wiring: dry-run appends appcast.xml to the create-command assets and
#     reports the enclosure/feed URLs; content is covered above (this process's
#     tempdir is torn down before we could read the file back). ---
make_zip() {  # make_zip <app-dir-name> <zip-path>
    local app="$ROOT/$1"
    mkdir -p "$app/Contents/MacOS"
    printf '#!/bin/sh\necho hi\n' > "$app/Contents/MacOS/App"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.5.0" \
        "$app/Contents/Info.plist" >/dev/null
    ditto -c -k --sequesterRsrc --keepParent "$app" "$2"
}

printf '## Notes\n- did things\n' > "$ROOT/notes.md"
mkdir -p "$ROOT/proj"   # project-dir without semver -> resolves via Info.plist

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export DEPLOYIT_SKIP_CODESIGN_VERIFY=1
export FAKE_GH_LOG="$ROOT/gh.log"

make_zip "Hello2.app" "$ROOT/Hello.zip"
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --zip "$ROOT/Hello.zip" \
        --project-dir "$ROOT/proj" --notes-file "$ROOT/notes.md" --repo me/Hello \
        --target deadbeefcafe --appcast-signature 'SIGA==' --dry-run) \
    || { echo "FAIL: appcast dry-run exited $? — it said: $out"; exit 1; }
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['ok'], d
cmd = d['commands'][0]
assert cmd[1:4] == ['release', 'create', '1.5.0'], cmd
assert any(a.endswith('appcast.xml') for a in cmd), f'appcast.xml not in assets: {cmd}'
assert d['appcast_url'] == 'https://github.com/me/Hello/releases/latest/download/appcast.xml', d
assert d['appcast_enclosure_url'] == 'https://github.com/me/Hello/releases/download/1.5.0/Hello.zip', d
"
[ ! -s "$ROOT/gh.log" ] || { echo "FAIL: dry-run must not call gh"; cat "$ROOT/gh.log"; exit 1; }

# --- real run with --clobber: appcast.xml uploaded alongside the zip ---
export FAKE_GH_RELEASE_EXISTS=1
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --zip "$ROOT/Hello.zip" \
        --project-dir "$ROOT/proj" --notes-file "$ROOT/notes.md" --repo me/Hello \
        --appcast-signature 'SIGA==' --clobber) \
    || { echo "FAIL: appcast --clobber exited $? — it said: $out"; exit 1; }
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['ok'], d
assert d['appcast_url'].endswith('/releases/latest/download/appcast.xml'), d
"
grep -q "release upload 1.5.0" "$ROOT/gh.log" || { echo "FAIL: gh release upload not invoked"; cat "$ROOT/gh.log"; exit 1; }
upload_line=$(grep "release upload 1.5.0" "$ROOT/gh.log")
echo "$upload_line" | grep -q "appcast.xml" || { echo "FAIL: appcast.xml missing from clobber upload: $upload_line"; exit 1; }
echo "$upload_line" | grep -q -- "--clobber" || { echo "FAIL: --clobber missing from upload: $upload_line"; exit 1; }
unset FAKE_GH_RELEASE_EXISTS

# --- spaced asset name: the enclosure URL must match what actually uploads ---
: > "$ROOT/gh.log"
make_zip "My App.app" "$ROOT/My App.zip"
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --zip "$ROOT/My App.zip" \
        --project-dir "$ROOT/proj" --notes-file "$ROOT/notes.md" --repo me/Hello \
        --target deadbeefcafe --appcast-signature 'SIGA==' --dry-run) \
    || { echo "FAIL: appcast spaced-name dry-run exited $? — it said: $out"; exit 1; }
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['ok'], d
assert d['appcast_enclosure_url'] == 'https://github.com/me/Hello/releases/download/1.5.0/My.App.zip', d
cmd = d['commands'][0]
uploaded_zip = next(a for a in cmd if a.endswith('.zip'))
assert uploaded_zip.endswith('My.App.zip'), f'normalized asset not uploaded: {cmd}'
"

# --- --app + --appcast-signature: hard fail (ditto re-archiving invalidates
#     the signature; only --zip's exact bytes may be signed) ---
app_dir="$ROOT/Bare.app"; mkdir -p "$app_dir/Contents/MacOS"
printf '#!/bin/sh\necho hi\n' > "$app_dir/Contents/MacOS/Bare"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" \
    "$app_dir/Contents/Info.plist" >/dev/null
set +e
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app_dir" \
        --project-dir "$ROOT/proj" --notes-file "$ROOT/notes.md" --repo me/Hello \
        --appcast-signature 'SIGA==' --dry-run 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || { echo "FAIL: --app + --appcast-signature must fail"; echo "$out"; exit 1; }
echo "$out" | grep -qi -- "--zip" || { echo "FAIL: error should mention --zip requirement: $out"; exit 1; }

echo "PASS"
