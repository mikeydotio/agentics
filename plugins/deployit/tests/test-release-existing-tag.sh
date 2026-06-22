#!/usr/bin/env bash
# deployit-release fails loudly when a release for the tag already exists, and
# replaces the asset (gh release upload --clobber) when --clobber is passed.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v ditto >/dev/null && command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: ditto/PlistBuddy unavailable (non-macOS)"; exit 0; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

app="$ROOT/Hello.app"; mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\necho hi\n' > "$app/Contents/MacOS/Hello"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.5.0" \
    "$app/Contents/Info.plist" >/dev/null
printf 'notes\n' > "$ROOT/notes.md"
mkdir -p "$ROOT/proj"

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export DEPLOYIT_SKIP_CODESIGN_VERIFY=1
export FAKE_GH_LOG="$ROOT/gh.log"
export FAKE_GH_RELEASE_EXISTS=1   # the release already exists

# --- default: existing tag -> fail loudly ---
set +e
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello); rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL: expected nonzero exit on existing tag"; exit 1; }
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert not d['ok'], d
assert 'already exists' in d['display'], d
"

# --- --clobber: replace the asset + notes ---
: > "$ROOT/gh.log"
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello --clobber)
echo "$out" | python3 -c "import sys, json; assert json.load(sys.stdin)['ok']"
grep -q "release upload 1.5.0" "$ROOT/gh.log" || { echo "FAIL: expected gh release upload"; cat "$ROOT/gh.log"; exit 1; }
grep -q -- "--clobber" "$ROOT/gh.log" || { echo "FAIL: missing --clobber"; cat "$ROOT/gh.log"; exit 1; }

echo "PASS"
