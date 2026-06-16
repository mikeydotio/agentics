#!/usr/bin/env bash
# Graceful degradation: when Sparkle is enabled but signing can't proceed (tool
# missing or sign_update fails), the deploy must NOT fail — it still produces the
# .dmg, drops the unsigned .zip, writes no `sparkle` key, and warns on stderr.
# We force the failure deterministically (host-independent) by pointing
# DEPLOYIT_SPARKLE_SIGN_UPDATE at a stub that exits non-zero.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v hdiutil >/dev/null && command -v ditto >/dev/null \
    || { echo "SKIP: hdiutil/ditto not available (non-macOS)"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# A failing sign_update stub — stands in for "tool present but cannot sign"
# (and exercises the same None-return path as "tool not found").
STUB="$ROOT/sign_update"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
echo "stub sign_update: no key configured" >&2
exit 1
SH
chmod +x "$STUB"

STDERR_LOG="$ROOT/stderr.log"
DEPLOYIT_SPARKLE_SIGN_UPDATE="$STUB" \
python3 - "$PLUGIN_ROOT" "$ROOT" 2>"$STDERR_LOG" <<'PY'
import importlib.machinery, importlib.util, json, pathlib, sys

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
    "id": "lillist-macos-nosign", "platform": "macos", "project": "Lillist",
    "bundle_id": "io.mikeydotio.Lillist", "marketing_version": "0.1.0",
    "semver_version": None, "build_number": "5", "commit": "mac0001",
    "timestamp": "2026-05-20T09:00:00-07:00",
    "origin_host": "demo.tail.ts.net",
    "origin_base_url": "https://demo.tail.ts.net/deployit",
}

# Must not raise even though signing fails.
mod._stage_macos(state, plugin_root, "lillist-macos-nosign", app, meta,
                 False, "", {"enabled": True})

serve = state / "serve" / "lillist-macos-nosign"
assert (serve / "Lillist.dmg").is_file(), "dmg must still be produced"
assert not (serve / "Lillist.zip").exists(), "unsigned zip must be discarded"
assert "sparkle" not in json.loads((serve / "_meta.json").read_text()), \
    "no sparkle key when signing fails"
print("ok")
PY

grep -qi "skipping Sparkle" "$STDERR_LOG" \
    || { echo "FAIL: expected a 'skipping Sparkle' warning on stderr"; cat "$STDERR_LOG"; exit 1; }

echo "PASS"
