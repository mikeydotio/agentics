#!/usr/bin/env bash
# _read_archive_build_number must resolve CFBundleVersion from BOTH archive
# layouts: iOS/visionOS put Info.plist at the .app bundle root, macOS nests it
# under Contents/. The macOS path was a latent bug — every macOS deploy failed
# at the build-number read ("built Info.plist not found") because only the iOS
# path was checked. Caught by the first real Lillist macOS deploy.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: PlistBuddy unavailable (non-macOS)"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# iOS/visionOS layout: <archive>/Products/Applications/<App>.app/Info.plist
mkdir -p "$ROOT/ios.xcarchive/Products/Applications/Lillist.app"
cat > "$ROOT/ios.xcarchive/Products/Applications/Lillist.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleVersion</key><string>4242</string></dict></plist>
PLIST

# macOS layout: <archive>/Products/Applications/<App>.app/Contents/Info.plist
mkdir -p "$ROOT/macos.xcarchive/Products/Applications/Lillist.app/Contents"
cat > "$ROOT/macos.xcarchive/Products/Applications/Lillist.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleVersion</key><string>20260516</string></dict></plist>
PLIST

# A bundle with NO Info.plist in either place must still fail clearly.
mkdir -p "$ROOT/empty.xcarchive/Products/Applications/Lillist.app"

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys
plugin_root = pathlib.Path(sys.argv[1]); root = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

ios = mod._read_archive_build_number(root / "ios.xcarchive", "Lillist")
assert ios == "4242", f"iOS-layout build number: {ios!r}"

mac = mod._read_archive_build_number(root / "macos.xcarchive", "Lillist")
assert mac == "20260516", f"macOS-layout build number: {mac!r}"

# Missing Info.plist → _read_archive_build_number calls fail() → SystemExit.
try:
    mod._read_archive_build_number(root / "empty.xcarchive", "Lillist")
    raise AssertionError("expected failure when no Info.plist exists")
except SystemExit:
    pass

print(f"ok: iOS={ios} macOS={mac}")
PY

echo "PASS"
