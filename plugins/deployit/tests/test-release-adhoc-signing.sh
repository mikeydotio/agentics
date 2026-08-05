#!/usr/bin/env bash
# deployit-release refuses to publish an app that isn't Developer-ID signed
# (default), and proceeds with --no-require-developer-id. Uses a real (unsigned)
# fake .app and real codesign for a deterministic verdict — no skip env here.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v codesign >/dev/null && command -v ditto >/dev/null \
    && command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: codesign/ditto/PlistBuddy unavailable (non-macOS)"; exit 0; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# An unsigned bundle: codesign --verify fails -> not Developer-ID.
app="$ROOT/Hello.app"; mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\necho hi\n' > "$app/Contents/MacOS/Hello"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.5.0" \
    "$app/Contents/Info.plist" >/dev/null
printf 'notes\n' > "$ROOT/notes.md"
mkdir -p "$ROOT/proj"
export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"   # unused on the fail path / dry-run

# --- default require -> fail loudly on an unsigned app ---
set +e
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello --dry-run); rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL: expected nonzero exit on un-signed app"; exit 1; }
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert not d['ok'], d
assert 'Developer-ID' in d['display'], d
"

# --- opt out -> proceeds (dry-run ok) ---
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello --no-require-developer-id --dry-run) \
    || { echo "FAIL: opt-out dry-run exited $? — it said: $out"; exit 1; }
echo "$out" | python3 -c "import sys, json; assert json.load(sys.stdin)['ok']"

echo "PASS"
