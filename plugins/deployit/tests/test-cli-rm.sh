#!/usr/bin/env bash
# `deployit rm` deletes a local build (--build ID) or a whole local product
# (--product BUNDLE --platform P): it removes the matching index entries, rmtrees
# their serve/<id>/ dirs, and pushes the index — but only ever for builds this
# machine owns (origin_base_url == base_url). Foreign-origin builds and other
# platforms are left untouched. Exercises the real push against a local bare repo.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export DEPLOYIT_STATE_DIR="$ROOT"

BASE="https://demo.tail.ts.net/deployit"
OTHER="https://other.tail.ts.net/deployit"

# config.toml (base_url scopes "local"; port is only used for the post-rm refresh,
# which harmlessly fails here with no backend running).
cat > "$ROOT/config.toml" <<TOML
[server]
port = 8731
base_url = "$BASE"
[index]
repo = "https://example.invalid/repo.git"
[macos]
notarize = false
notary_profile = ""
TOML

# Bare origin + index repo with tracking (so the real pull/commit/push path runs).
mkdir -p "$ROOT/remote.git" "$ROOT/index" "$ROOT/serve"
git -C "$ROOT/remote.git" init --bare --quiet --initial-branch=main
git -C "$ROOT/index" init --quiet --initial-branch=main
git -C "$ROOT/index" config user.email "test@example.invalid"
git -C "$ROOT/index" config user.name "test"
git -C "$ROOT/index" remote add origin "$ROOT/remote.git"

# Seed: two local iOS builds of App, one foreign iOS build of App (other origin),
# one local macOS build of App (other platform). Local builds get serve dirs.
python3 - "$ROOT" "$BASE" "$OTHER" <<'PY'
import json, sys, pathlib
root, base, other = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

def mk(id_, base_url, platform, ts, local=True):
    if local:
        d = root / "serve" / id_
        d.mkdir(parents=True, exist_ok=True)
        (d / "App.ipa").write_text("fake")
        (d / "_meta.json").write_text(json.dumps({"id": id_, "timestamp": ts}))
    return {
        "id": id_, "platform": platform, "project": "App",
        "bundle_id": "io.mikeydotio.App", "marketing_version": "1.0",
        "build_number": id_[-1], "commit": id_[:7], "timestamp": ts,
        "origin_host": "x", "origin_base_url": base_url,
        "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
        "size_bytes": 1, "archived": False, "notes": None,
    }

builds = [
    mk("app-ios-local1", base,  "ios",   "2026-05-04T10:00:00-07:00"),
    mk("app-ios-local2", base,  "ios",   "2026-05-03T10:00:00-07:00"),
    mk("app-ios-foreign", other, "ios",  "2026-05-02T10:00:00-07:00", local=False),
    mk("app-macos-local", base, "macos", "2026-05-01T10:00:00-07:00"),
]
(root / "index" / "builds.json").write_text(json.dumps({"version": 1, "builds": builds}, indent=2) + "\n")
PY

git -C "$ROOT/index" add builds.json
git -C "$ROOT/index" commit --quiet -m "seed"
git -C "$ROOT/index" push --quiet --set-upstream origin main

CLI=("python3" "$PLUGIN_ROOT/bin/deployit-cli" "--plugin-root" "$PLUGIN_ROOT")

has() { python3 -c "
import json,sys
d=json.load(open('$ROOT/index/builds.json'))
sys.exit(0 if any(b['id']==sys.argv[1] for b in d['builds']) else 1)
" "$1"; }

# --- Argument validation (no state change, no git) ---
for args in "rm" "rm --build x --product io.mikeydotio.App" "rm --product io.mikeydotio.App"; do
    out=$("${CLI[@]}" $args 2>&1 || true)
    echo "$out" | grep -q '"ok": false' \
        || { echo "FAIL: '$args' should be ok:false; got: $out"; exit 1; }
done
out=$("${CLI[@]}" rm --build 'bad id!' 2>&1 || true)
echo "$out" | grep -q '"ok": false' \
    || { echo "FAIL: invalid build id should be ok:false; got: $out"; exit 1; }

# --- Foreign build: refused, nothing removed ---
out=$("${CLI[@]}" rm --build app-ios-foreign 2>&1 || true)
echo "$out" | grep -q '"ok": false' \
    || { echo "FAIL: foreign rm should be ok:false; got: $out"; exit 1; }
has app-ios-foreign || { echo "FAIL: foreign build wrongly removed"; exit 1; }

# --- rm --build: removes only that local build (index + disk), pushes ---
out=$("${CLI[@]}" rm --build app-ios-local1)
echo "$out" | grep -q '"removed": 1' || { echo "FAIL: expected removed 1: $out"; exit 1; }
echo "$out" | grep -q '"removed_local": 1' || { echo "FAIL: expected removed_local 1: $out"; exit 1; }
has app-ios-local1 && { echo "FAIL: app-ios-local1 still in index"; exit 1; } || true
[[ ! -d "$ROOT/serve/app-ios-local1" ]] || { echo "FAIL: serve dir not removed"; exit 1; }
has app-ios-local2 || { echo "FAIL: app-ios-local2 wrongly removed"; exit 1; }
has app-macos-local || { echo "FAIL: macos build wrongly removed"; exit 1; }
git -C "$ROOT/remote.git" log --oneline | grep -q 'rm build app-ios-local1' \
    || { echo "FAIL: rm not pushed to origin"; exit 1; }

# --- rm --product: removes remaining LOCAL ios builds, leaves foreign + macos ---
out=$("${CLI[@]}" rm --product io.mikeydotio.App --platform ios)
echo "$out" | grep -q '"removed": 1' || { echo "FAIL: product rm expected removed 1: $out"; exit 1; }
has app-ios-local2 && { echo "FAIL: app-ios-local2 not removed by product rm"; exit 1; } || true
[[ ! -d "$ROOT/serve/app-ios-local2" ]] || { echo "FAIL: local2 serve dir not removed"; exit 1; }
has app-ios-foreign || { echo "FAIL: foreign ios build removed by product rm"; exit 1; }
has app-macos-local || { echo "FAIL: macos build removed by product rm"; exit 1; }

echo "PASS"
