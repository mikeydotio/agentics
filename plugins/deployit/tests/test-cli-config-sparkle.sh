#!/usr/bin/env bash
# _read_config parses the [macos.sparkle] section. Under Python <3.11 (no
# tomllib) the regex fallback runs — which is what this Python (3.9.x) exercises
# — and under 3.11+ tomllib nests it natively. Either way the contract holds:
# cfg["macos"]["sparkle"] carries enabled + the three path/key fields, and a
# config WITHOUT the section degrades to safe defaults (enabled false).
#
# Case C (issue #117 self-review catch): the tomllib branch does ZERO
# normalization (`return tomllib.loads(text)` verbatim) — unlike the regex
# fallback, which always synthesizes the full macos.sparkle sub-dict with
# defaults even when the section is absent from the source text. So under
# tomllib (the real production interpreter — this project's own CLAUDE.md
# notes "macOS 26 ships 3.13"), a config.toml with [macos] but no
# [macos.sparkle] parses to a `cfg["macos"]` dict with NO "sparkle" key at
# all. Every sparkle_cfg read in cmd_deploy MUST use a .get() chain
# (`cfg.get("macos", {}).get("sparkle", {})`), never direct indexing
# (`cfg["macos"]["sparkle"]`) — the latter KeyErrors on exactly that
# tomllib-parsed, no-sparkle-section config. This Python (3.9.x) can't
# exercise the tomllib branch directly, so Case C simulates its
# unnormalized shape by hand and drives the exact guard expression
# cmd_deploy's Sparkle preflight uses.
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

# Case C — a raw tomllib-shaped cfg (macos present, sparkle key ABSENT — no
# normalization applied) must not KeyError through the exact expression
# cmd_deploy's Sparkle preflight uses.
c = {"macos": {"notarize": False, "notary_profile": ""}}
c_sparkle = c.get("macos", {}).get("sparkle", {})
assert c_sparkle == {}, f"C: expected {{}}, got {c_sparkle!r}"
assert c_sparkle.get("enabled") is None, "C: preflight guard must read False/None, never raise"

print(f"ok (python {sys.version_info.major}.{sys.version_info.minor}, "
      f"{'tomllib' if sys.version_info >= (3, 11) else 'regex-fallback'})")
PY

# Static regression guard: cmd_deploy must never index cfg["macos"]["sparkle"]
# directly — only the defended .get("macos", {}).get("sparkle", {}) chain
# (see Case C above). Direct indexing KeyErrors on a real tomllib-parsed
# config.toml that has [macos] but no [macos.sparkle].
if grep -n 'cfg\["macos"\]\["sparkle"\]' "$PLUGIN_ROOT/bin/deployit-cli"; then
    echo "FAIL: found unsafe direct indexing of cfg[\"macos\"][\"sparkle\"] above"
    exit 1
fi

echo "PASS"
