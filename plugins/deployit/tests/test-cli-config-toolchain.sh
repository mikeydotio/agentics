#!/usr/bin/env bash
# _read_project_config + _resolve_toolchain_developer_dir: a project's
# .deployit/config.toml [toolchain] table pins the Xcode used for
# archive/export. Motivating case: mikeydotio/lillist#70 — a project whose
# build needs a newer Xcode/SDK than the machine's xcode-select default.
# Covers: no config (None, unchanged behavior), explicit developer_dir
# (wins outright, and fails loudly if it doesn't exist), min_sdk selecting
# the newest matching /Applications/Xcode*.app (portable — survives an
# install moving/being renamed), and min_sdk failing loudly when nothing
# on disk satisfies it (the silent-toolchain-drop guard).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: PlistBuddy unavailable (non-macOS)"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# --- Fixture: fake /Applications with three Xcode installs of different
#     versions, so min_sdk selection has something real to scan. ---
APPS="$ROOT/Applications"
make_xcode() {  # $1=app name  $2=CFBundleShortVersionString
    local app="$APPS/$1"
    mkdir -p "$app/Contents/Developer"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $2" \
        -c "Add :CFBundleIdentifier string com.apple.dt.Xcode" \
        "$app/Contents/version.plist" >/dev/null
}
make_xcode "Xcode.app" "26.6"
make_xcode "Xcode-beta.app" "27.0"
make_xcode "Xcode_26.3.app" "26.3"
# Non-Xcode .app should never be considered a candidate.
mkdir -p "$APPS/Calculator.app/Contents"

# --- Project A: no .deployit/config.toml at all ---
mkdir -p "$ROOT/a"

# --- Project B: [toolchain] min_sdk = "27" ---
mkdir -p "$ROOT/b/.deployit"
cat > "$ROOT/b/.deployit/config.toml" <<'TOML'
[toolchain]
min_sdk = "27"
TOML

# --- Project C: [toolchain] developer_dir = <explicit, existing path> ---
mkdir -p "$ROOT/c/.deployit"
cat > "$ROOT/c/.deployit/config.toml" <<TOML
[toolchain]
developer_dir = "$APPS/Xcode-beta.app/Contents/Developer"
TOML

# --- Project D: [toolchain] developer_dir = <explicit, MISSING path> ---
mkdir -p "$ROOT/d/.deployit"
cat > "$ROOT/d/.deployit/config.toml" <<'TOML'
[toolchain]
developer_dir = "/nonexistent/Xcode.app/Contents/Developer"
TOML

# --- Project E: [toolchain] min_sdk = "99" (nothing on disk satisfies it) ---
mkdir -p "$ROOT/e/.deployit"
cat > "$ROOT/e/.deployit/config.toml" <<'TOML'
[toolchain]
min_sdk = "99"
TOML

# --- Project F: empty [toolchain] table (neither key set) ---
mkdir -p "$ROOT/f/.deployit"
cat > "$ROOT/f/.deployit/config.toml" <<'TOML'
[toolchain]
TOML

DEPLOYIT_APPLICATIONS_DIR="$APPS" python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys

plugin_root = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])

loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

# A — no config file → {} → resolver returns None (unchanged behavior).
cfg_a = mod._read_project_config(root / "a")
assert cfg_a == {}, f"A: expected {{}}, got {cfg_a!r}"
assert mod._resolve_toolchain_developer_dir(cfg_a) is None, "A: expected None"

# B — min_sdk="27" picks the newest Xcode*.app whose version >= 27,
#     i.e. Xcode-beta.app (27.0), not Xcode.app (26.6) or Xcode_26.3.app.
cfg_b = mod._read_project_config(root / "b")
assert cfg_b.get("toolchain", {}).get("min_sdk") == "27", f"B: parsed min_sdk {cfg_b!r}"
resolved_b = mod._resolve_toolchain_developer_dir(cfg_b)
assert resolved_b == str(root / "Applications" / "Xcode-beta.app" / "Contents" / "Developer"), \
    f"B: resolved {resolved_b!r}"

# C — explicit developer_dir wins outright and is returned verbatim.
cfg_c = mod._read_project_config(root / "c")
resolved_c = mod._resolve_toolchain_developer_dir(cfg_c)
assert resolved_c == str(root / "Applications" / "Xcode-beta.app" / "Contents" / "Developer"), \
    f"C: resolved {resolved_c!r}"

# D — explicit developer_dir that doesn't exist on disk → fail() → SystemExit.
cfg_d = mod._read_project_config(root / "d")
try:
    mod._resolve_toolchain_developer_dir(cfg_d)
    raise AssertionError("D: expected failure for a nonexistent developer_dir")
except SystemExit:
    pass

# E — min_sdk that nothing on disk satisfies → fail() → SystemExit (the
#     silent-toolchain-drop guard: never silently fall back).
cfg_e = mod._read_project_config(root / "e")
try:
    mod._resolve_toolchain_developer_dir(cfg_e)
    raise AssertionError("E: expected failure when no install satisfies min_sdk")
except SystemExit:
    pass

# F — [toolchain] present but empty → treated the same as no config at all.
cfg_f = mod._read_project_config(root / "f")
assert mod._resolve_toolchain_developer_dir(cfg_f) is None, "F: expected None for an empty [toolchain] table"

print(f"ok (python {sys.version_info.major}.{sys.version_info.minor}, "
      f"{'tomllib' if sys.version_info >= (3, 11) else 'regex-fallback'})")
PY

echo "PASS"
