#!/usr/bin/env bash
# _read_config parses the [macos.sparkle] section. Under Python <3.11 (no
# tomllib) the regex fallback runs — which is what this Python (3.9.x) exercises
# — and under 3.11+ tomllib nests it natively. Either way the contract holds:
# cfg["macos"]["sparkle"] carries enabled + the three path/key fields, and a
# config WITHOUT the section degrades to safe defaults (enabled false).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# Case A: full [macos.sparkle] section, enabled.
mkdir -p "$ROOT/a"
cat > "$ROOT/a/config.toml" <<'TOML'
[server]
port = 8729
base_url = "https://demo.tail.ts.net/deployit"

[macos]
notarize = false
notary_profile = ""

[macos.sparkle]
enabled = true
sign_update_path = "/opt/sparkle/bin/sign_update"
private_key_path = "/Users/mikey/Enderchest/deployit/sparkle_ed_priv.key"
public_ed_key = "ABC123pubkey=="
TOML

# Case B: no [macos.sparkle] section at all (pre-Sparkle config).
mkdir -p "$ROOT/b"
cat > "$ROOT/b/config.toml" <<'TOML'
[server]
port = 8729
base_url = "https://demo.tail.ts.net/deployit"

[macos]
notarize = false
notary_profile = ""
TOML

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys

plugin_root = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])

loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

# Case A — enabled section parses fully.
a = mod._read_config(root / "a")
sp = a.get("macos", {}).get("sparkle", {})
assert sp.get("enabled") is True, f"A: enabled should be True, got {sp!r}"
assert sp.get("sign_update_path") == "/opt/sparkle/bin/sign_update", f"A: sign_update_path {sp!r}"
assert sp.get("private_key_path") == "/Users/mikey/Enderchest/deployit/sparkle_ed_priv.key", f"A: private_key_path {sp!r}"
assert sp.get("public_ed_key") == "ABC123pubkey==", f"A: public_ed_key {sp!r}"
# notarize sibling still parses alongside the sub-table.
assert a["macos"]["notarize"] is False, f"A: notarize {a['macos']!r}"

# Case B — no section → safe defaults, never raises.
b = mod._read_config(root / "b")
spb = b.get("macos", {}).get("sparkle", {})
assert spb.get("enabled", False) is False, f"B: enabled should default False, got {spb!r}"
assert b["server"]["port"] == 8729, f"B: port {b['server']!r}"

print(f"ok (python {sys.version_info.major}.{sys.version_info.minor}, "
      f"{'tomllib' if sys.version_info >= (3, 11) else 'regex-fallback'})")
PY

echo "PASS"
