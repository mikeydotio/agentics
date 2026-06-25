#!/usr/bin/env bash
# deployit-release omits --target when the tag already exists on the remote.
# `gh release create` sets the tag at --target only when creating it; on an
# existing tag a divergent target_commitish is rejected with HTTP 422
# "Release.target_commitish is invalid" (e.g. semver tagged the release commit,
# then a build-number bump became HEAD and is handed in as the build --target).
# So: tag absent -> pass --target (gh creates the tag); tag present -> omit it.
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
mkdir -p "$ROOT/proj"   # no semver -> tag resolves to 1.5.0 via Info.plist

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export DEPLOYIT_SKIP_CODESIGN_VERIFY=1

run() {  # publishes; the release does not pre-exist, so the create path is taken
    python3 "$PLUGIN_ROOT/bin/deployit-release" --app "$app" --project-dir "$ROOT/proj" \
        --notes-file "$ROOT/notes.md" --repo me/Hello --target deadbeefcafe >/dev/null
}

# --- tag absent: --target IS passed so gh creates the tag ---
export FAKE_GH_LOG="$ROOT/absent.log"; : > "$FAKE_GH_LOG"
unset FAKE_GH_TAG_EXISTS
run
grep -q "release create 1.5.0" "$FAKE_GH_LOG" || { echo "FAIL: release create not invoked (tag absent)"; cat "$FAKE_GH_LOG"; exit 1; }
grep -q -- "--target deadbeefcafe" "$FAKE_GH_LOG" || { echo "FAIL: --target must be passed when the tag is absent"; cat "$FAKE_GH_LOG"; exit 1; }

# --- tag present: --target is OMITTED (would otherwise be HTTP 422) ---
export FAKE_GH_LOG="$ROOT/present.log"; : > "$FAKE_GH_LOG"
export FAKE_GH_TAG_EXISTS=1
run
grep -q "release create 1.5.0" "$FAKE_GH_LOG" || { echo "FAIL: release create not invoked (tag present)"; cat "$FAKE_GH_LOG"; exit 1; }
if grep -q -- "--target" "$FAKE_GH_LOG"; then
    echo "FAIL: --target must be omitted when the tag already exists"; cat "$FAKE_GH_LOG"; exit 1
fi

echo "PASS"
