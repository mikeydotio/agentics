#!/usr/bin/env bash
# issue #117: _resolve_sparkle_sign_update's discovery ladder.
#
#   1. DEPLOYIT_SPARKLE_SIGN_UPDATE / macos.sparkle.sign_update_path are
#      explicit operator intent — set-but-missing is a HARD ERROR naming the
#      configured value (AC 2), never a silent fall-through to a different
#      binary (the root cause of the Lillist v0.19.0 incident: a deleted
#      Caskroom pin silently substituted a freshly-quarantined one).
#   2. PATH, then the SwiftPM artifact bundle, then the deprecated Homebrew
#      cask (AC 4) — the cask emits a deprecation warning when chosen.
#   3. Multiple glob hits sort by parsed VERSION, newest wins, not
#      lexicographically (AC 5): 2.9.10 must beat 2.9.4 and 2.9.3.
#   4. A quarantined resolved binary always warns, naming the fix (AC 3).
#
# HOME and the module's SPARKLE_CASK_ROOTS/SPARKLE_SPM_DERIVED_DATA_GLOBS
# constants are patched per-case so this never touches the real filesystem
# outside $ROOT.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v xattr >/dev/null || { echo "SKIP: xattr not available (non-macOS)"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, json, pathlib, subprocess, sys

plugin_root = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])

def load_module():
    loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
    spec = importlib.util.spec_from_loader("dcli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod

# --- Case A: explicit config path missing -> hard error naming the path ---
mod = load_module()
missing = root / "nowhere" / "sign_update"
try:
    mod._resolve_sparkle_sign_update({"sign_update_path": str(missing)}, "Lillist")
    raise AssertionError("expected SystemExit for a missing configured sign_update_path")
except SystemExit as exc:
    assert exc.code == 1, exc.code

# --- Case B: explicit env override missing -> hard error naming the path ---
import os
mod = load_module()
missing_env = str(root / "nowhere2" / "sign_update")
os.environ["DEPLOYIT_SPARKLE_SIGN_UPDATE"] = missing_env
try:
    mod._resolve_sparkle_sign_update({}, "Lillist")
    raise AssertionError("expected SystemExit for a missing DEPLOYIT_SPARKLE_SIGN_UPDATE")
except SystemExit as exc:
    assert exc.code == 1, exc.code
finally:
    del os.environ["DEPLOYIT_SPARKLE_SIGN_UPDATE"]

# --- Case C: SwiftPM artifact wins over the deprecated Caskroom (AC 4) ---
mod = load_module()
mod.SPARKLE_CASK_ROOTS = [root / "cask"]
mod.SPARKLE_SPM_DERIVED_DATA_GLOBS = [
    str(root / "derived" / "{project}-*" / "SourcePackages" / "artifacts" / "*" / "Sparkle" / "bin" / "sign_update"),
    str(root / "derived" / "*" / "SourcePackages" / "artifacts" / "*" / "Sparkle" / "bin" / "sign_update"),
]
spm_tool = root / "derived" / "Lillist-abc123" / "SourcePackages" / "artifacts" / "sparkle" / "Sparkle" / "bin" / "sign_update"
cask_tool = root / "cask" / "2.9.4" / "bin" / "sign_update"
for t in (spm_tool, cask_tool):
    t.parent.mkdir(parents=True, exist_ok=True)
    t.write_text("#!/bin/sh\n"); t.chmod(0o755)
result = mod._resolve_sparkle_sign_update({}, "Lillist")
assert result["path"] == spm_tool, f"expected SwiftPM artifact, got {result}"
assert result["source"] == "SwiftPM artifact bundle", result
assert not result["warnings"], f"SwiftPM pick should not warn: {result['warnings']}"

# --- Case D: no SwiftPM hit -> falls through to Caskroom, warns deprecated ---
spm_tool.unlink()
mod = load_module()
mod.SPARKLE_CASK_ROOTS = [root / "cask"]
mod.SPARKLE_SPM_DERIVED_DATA_GLOBS = [
    str(root / "derived" / "{project}-*" / "SourcePackages" / "artifacts" / "*" / "Sparkle" / "bin" / "sign_update"),
    str(root / "derived" / "*" / "SourcePackages" / "artifacts" / "*" / "Sparkle" / "bin" / "sign_update"),
]
result = mod._resolve_sparkle_sign_update({}, "Lillist")
assert result["path"] == cask_tool, f"expected Caskroom fallback, got {result}"
assert any("deprecated" in w for w in result["warnings"]), result["warnings"]

# --- Case E: version-sorted glob (newest wins), not lexicographic (AC 5) ---
mod = load_module()
mod.SPARKLE_CASK_ROOTS = [root / "cask2"]
mod.SPARKLE_SPM_DERIVED_DATA_GLOBS = []
for v in ("2.9.3", "2.9.4", "2.9.10"):
    t = root / "cask2" / v / "bin" / "sign_update"
    t.parent.mkdir(parents=True, exist_ok=True)
    t.write_text("#!/bin/sh\n"); t.chmod(0o755)
result = mod._resolve_sparkle_sign_update({}, "")
assert result["path"] == root / "cask2" / "2.9.10" / "bin" / "sign_update", \
    f"expected 2.9.10 (newest by version, not string sort), got {result['path']}"

# --- Case F: quarantined binary always warns, names the fix (AC 3) ---
mod = load_module()
mod.SPARKLE_CASK_ROOTS = []
mod.SPARKLE_SPM_DERIVED_DATA_GLOBS = []
q_tool = root / "explicit" / "sign_update"
q_tool.parent.mkdir(parents=True, exist_ok=True)
q_tool.write_text("#!/bin/sh\n"); q_tool.chmod(0o755)
subprocess.run(["xattr", "-w", "com.apple.quarantine", "0081;00000000;deployit-test;", str(q_tool)],
               check=True)
result = mod._resolve_sparkle_sign_update({"sign_update_path": str(q_tool)}, "")
assert result["path"] == q_tool, result
assert any("com.apple.quarantine" in w and "xattr -d" in w for w in result["warnings"]), result["warnings"]

print("ok")
PY

echo "PASS"
