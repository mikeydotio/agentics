#!/usr/bin/env bash
# deployit-release: --dry-run prints the gh command without touching gh; a real
# run (fake gh) invokes `gh release create <tag> <zip> --notes-file ... --target`
# and reports the release URL. codesign verification is stubbed.
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
printf '## Notes\n- did things\n' > "$ROOT/notes.md"
mkdir -p "$ROOT/proj"   # project-dir without semver -> resolves via Info.plist

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export DEPLOYIT_SKIP_CODESIGN_VERIFY=1
export FAKE_GH_LOG="$ROOT/gh.log"

# --- dry-run: JSON only, no gh calls ---
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello --target deadbeefcafe --dry-run)
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['ok'], d
assert d['tag'] == '1.5.0', d
cmd = d['commands'][0]
assert cmd[1:4] == ['release', 'create', '1.5.0'], cmd
assert '--target' in cmd and 'deadbeefcafe' in cmd, cmd
assert '--notes-file' in cmd, cmd
"
[ ! -s "$ROOT/gh.log" ] || { echo "FAIL: dry-run must not call gh"; cat "$ROOT/gh.log"; exit 1; }

# --- real run via fake gh ---
out=$(python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello --target deadbeefcafe)
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['ok'], d
assert d['release_url'].endswith('/tag/1.5.0'), d
"
grep -q "release create 1.5.0" "$ROOT/gh.log" || { echo "FAIL: gh release create not invoked"; cat "$ROOT/gh.log"; exit 1; }
grep -q "notes.md" "$ROOT/gh.log" || { echo "FAIL: notes file not passed to gh"; exit 1; }
grep -q "Hello.zip" "$ROOT/gh.log" || { echo "FAIL: zip asset not passed to gh"; exit 1; }

echo "PASS"
