#!/usr/bin/env bash
# Auto-prune on deploy: after _append_to_index runs with PRUNE_KEEP_PER_PRODUCT=10
# pre-existing builds of the same (bundle_id, platform) on this origin, the
# new entry takes the cap to 11 and the oldest gets hard-deleted from both
# the index and serve/<id>/.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

BASE="https://demo.tail.ts.net/deployit"
OTHER_BASE="https://other.tail.ts.net/deployit"

# Set up a local bare git repo to act as origin
mkdir -p "$ROOT/remote.git"
git -C "$ROOT/remote.git" init --bare --quiet --initial-branch=main

# Set up the index repo
mkdir -p "$ROOT/index" "$ROOT/serve"
git -C "$ROOT/index" init --quiet --initial-branch=main
git -C "$ROOT/index" config user.email "test@example.invalid"
git -C "$ROOT/index" config user.name "test"
git -C "$ROOT/index" remote add origin "$ROOT/remote.git"

# Seed 10 existing builds of the SAME product on this origin (newest-first),
# plus 1 build from a different platform (should not be pruned), plus 1 build
# from another origin with same bundle/platform (should not be pruned).
python3 - "$ROOT" "$BASE" "$OTHER_BASE" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
base = sys.argv[2]
other = sys.argv[3]

builds = []
def mk(id_, base_url, platform, ts, build_no, bundle="io.mikeydotio.App"):
    d = root / "serve" / id_
    d.mkdir(parents=True, exist_ok=True)
    (d / "App.ipa").write_text("fake")
    (d / "_meta.json").write_text(json.dumps({"id": id_, "timestamp": ts}))
    return {
        "id": id_, "platform": platform, "project": "App",
        "bundle_id": bundle, "marketing_version": "1.0",
        "build_number": str(build_no), "commit": id_[:7],
        "timestamp": ts, "origin_host": "x",
        "origin_base_url": base_url,
        "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
        "size_bytes": 1, "archived": False, "notes": None,
    }

# 10 newest-first iOS builds on $BASE for App
for i in range(10):
    day = 10 - i
    builds.append(mk(f"app-ios-202605{day:02d}", base, "ios",
                     f"2026-05-{day:02d}T10:00:00-07:00", 100 + day))
# A macOS build of same App on $BASE — different product, must survive
builds.append(mk("app-macos-only", base, "macos", "2026-05-01T10:00:00-07:00", 1))
# An iOS build of same App on OTHER origin — must survive (origin scoping)
builds.append(mk("app-ios-other", other, "ios", "2026-05-01T10:00:00-07:00", 1))

(root / "index" / "builds.json").write_text(json.dumps({"version": 1, "builds": builds}, indent=2) + "\n")
PY

# Initial commit + push to origin with tracking
git -C "$ROOT/index" add builds.json
git -C "$ROOT/index" commit --quiet -m "seed"
git -C "$ROOT/index" push --quiet --set-upstream origin main

# Sanity: 12 entries total, 10 in target product, 11 serve dirs (12 minus shared overlap is 12, all unique)
python3 -c "
import json
d = json.load(open('$ROOT/index/builds.json'))
assert len(d['builds']) == 12, f'seed count: {len(d[\"builds\"])}'
"

# Now invoke _append_to_index directly via a small Python harness so we
# exercise the real function (including the prune path) without xcodebuild.
python3 - "$PLUGIN_ROOT" "$ROOT" "$BASE" <<'PY'
import importlib.util, importlib.machinery, json, sys, pathlib
plugin_root = pathlib.Path(sys.argv[1])
state = pathlib.Path(sys.argv[2])
base = sys.argv[3]

cli_path = plugin_root / "bin" / "deployit-cli"
loader = importlib.machinery.SourceFileLoader("dcli", str(cli_path))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

# Build a stub serve/<id>/ for the new build so prune can leave it alone
new_id = "app-ios-NEWEST"
new_dir = state / "serve" / new_id
new_dir.mkdir(parents=True, exist_ok=True)
(new_dir / "App.ipa").write_text("new")

entry = {
    "id": new_id, "platform": "ios", "project": "App",
    "bundle_id": "io.mikeydotio.App", "marketing_version": "1.1",
    "build_number": "200", "commit": "newest1",
    "timestamp": "2026-05-30T10:00:00-07:00",
    "origin_host": "demo.tail.ts.net",
    "origin_base_url": base,
    "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
    "size_bytes": 1, "archived": False, "notes": None,
}
mod._append_to_index(state, entry)

# Verify: target product (App / ios on $BASE) now has exactly 10 entries,
# the new one is present, and the oldest (day=01) is gone from both index and disk.
data = json.load(open(state / "index" / "builds.json"))
target = [b for b in data["builds"]
          if b["bundle_id"] == "io.mikeydotio.App"
          and b["platform"] == "ios"
          and b["origin_base_url"] == base]
assert len(target) == 10, f"target count: {len(target)}: {[b['id'] for b in target]}"
ids = {b["id"] for b in target}
assert new_id in ids, "new entry missing"
assert "app-ios-20260501" not in ids, "oldest should have been pruned"
# Other-platform and other-origin builds untouched
all_ids = {b["id"] for b in data["builds"]}
assert "app-macos-only" in all_ids, "macos sibling pruned by mistake"
assert "app-ios-other" in all_ids, "other-origin build pruned by mistake"

# Disk: oldest serve dir gone, new one present, untouched ones present
assert not (state / "serve" / "app-ios-20260501").exists(), "oldest serve dir not removed"
assert (state / "serve" / new_id).exists(), "new serve dir missing"
assert (state / "serve" / "app-macos-only").exists(), "macos serve dir removed by mistake"
assert (state / "serve" / "app-ios-other").exists(), "other-origin serve dir removed by mistake"
print("ok")
PY

echo "PASS"
