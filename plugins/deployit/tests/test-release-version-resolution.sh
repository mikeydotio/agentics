#!/usr/bin/env bash
# deployit-release resolves the release version+tag in the order:
# semver VERSION -> the built app's CFBundleShortVersionString -> fail loudly,
# normalising the tag with the semver version_prefix. Unit-loads the script
# module; no gh/network involved.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: PlistBuddy unavailable (non-macOS)"; exit 0; }

python3 - "$PLUGIN_ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, subprocess, sys, tempfile

plugin_root = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("drel", str(plugin_root / "bin" / "deployit-release"))
spec = importlib.util.spec_from_loader("drel", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)

# 1) semver active -> VERSION verbatim (already prefixed)
d = pathlib.Path(tempfile.mkdtemp())
(d / ".semver").mkdir()
(d / ".semver" / "config.yaml").write_text('tracking: true\nversion_prefix: "v"\n')
(d / "VERSION").write_text("v2.17.0\n")
assert m._resolve_version_and_tag(d, pathlib.Path("/nope.app")) == ("v2.17.0", "v2.17.0", "semver")

# 2) semver inactive -> Info.plist CFBundleShortVersionString, prefix applied
d2 = pathlib.Path(tempfile.mkdtemp())
(d2 / ".semver").mkdir()
(d2 / ".semver" / "config.yaml").write_text('tracking: false\nversion_prefix: "v"\n')
app = pathlib.Path(tempfile.mkdtemp()) / "App.app"
(app / "Contents").mkdir(parents=True)
subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Add :CFBundleShortVersionString string 3.4.5",
                str(app / "Contents" / "Info.plist")], check=True, capture_output=True)
assert m._resolve_version_and_tag(d2, app) == ("3.4.5", "v3.4.5", "info.plist")

# 3) neither semver nor Info.plist version -> fail loudly (exit 1)
d3 = pathlib.Path(tempfile.mkdtemp())
bare = pathlib.Path(tempfile.mkdtemp()) / "Bare.app"
(bare / "Contents").mkdir(parents=True)
subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Add :CFBundleName string Bare",
                str(bare / "Contents" / "Info.plist")], check=True, capture_output=True)
try:
    m._resolve_version_and_tag(d3, bare)
    raise AssertionError("expected fail() when no version source exists")
except SystemExit as e:
    assert e.code == 1, e

print("ok")
PY

echo "PASS"
