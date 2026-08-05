#!/usr/bin/env bash
# `deployit rm` deletes a local build (--build ID) or a whole local product
# (--product BUNDLE --platform P): it removes the matching index entries, rmtrees
# their serve/<id>/ dirs, and pushes the index — but only ever for builds this
# machine owns (origin_base_url == base_url). Foreign-origin builds and other
# platforms are left untouched. Exercises the real push against a local bare repo.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# This file asserts a REAL push to the bare origin created below. Inheriting
# DEPLOYIT_SKIP_GC_PUSH short-circuits _commit_and_push_index to a purely local
# write, and two tests in this same directory export it (test-backend-delete.sh,
# test-gc.sh), so the leak path is real. Refuse to run rather than measure
# nothing.
#
# ⚠ The claim this comment used to make — that a leak would make "every
# assertion here pass while nothing was pushed" — is MEASURED FALSE, and AGE-48
# corrected it. With the variable set and this guard removed, the run fails
# loudly at `origin_published` with "FAIL: rm not pushed to origin", because
# that assertion reads the bare origin's committed builds.json rather than the
# CLI's own report. So the guard is not what stands between this file and a
# vacuous green — `origin_published` is. What the guard still earns is naming
# the cause at line 1 instead of leaving a reader to infer it from a push
# assertion that failed for an environmental reason. Keep it, but do not credit
# it with soundness it does not supply.
[[ -z "${DEPLOYIT_SKIP_GC_PUSH:-}" ]] \
    || { echo "FAIL: DEPLOYIT_SKIP_GC_PUSH is set; this test cannot verify a push"; exit 1; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export DEPLOYIT_STATE_DIR="$ROOT"

BASE="https://demo.tail.ts.net/deployit"
OTHER="https://other.tail.ts.net/deployit"

# config.toml (base_url scopes "local"). The port is used ONLY by the post-rm
# local-backend refresh, which runs after the index push and only when it
# published (deployit-cli:2607). Nothing listens on it, so that refresh always
# fails and prints `warning: local backend refresh failed` — on every PASSING run
# of this file. It cannot affect any assertion below, and no assertion here
# depends on a running backend. AGE-21 was filed on the theory that it did; that
# was measured false.
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

# Assert the rm reached origin: the tip of the bare origin repo carries a commit
# whose subject contains $1, AND origin's committed builds.json no longer lists
# build $2.
#
# The pushed CONTENT is the property under test. A subject match on its own is a
# decoration: a publisher that commits the right message with nothing staged
# (`--allow-empty`) satisfies it, measured — the subject-only form returns 0 on
# exactly that bug while the content check returns 1.
#
# Both reads consume git's output to completion via command substitution. Never
# reintroduce the previous form,
#     git -C "$ROOT/remote.git" log --oneline | grep -q "$1"
# in this file, which runs under `set -o pipefail`: `grep -q` exits on its first
# match, `git log` — which interleaves revision-walking with per-commit writes —
# is then killed by SIGPIPE mid-walk, and pipefail reports the pipeline as 141
# even though the commit IS present. Measured at 9-46% of reads idle and 82%
# under CPU load, always status 141 (AGE-21). This is a property of the
# pipeline's SHAPE, so retrying it cannot make it sound; the 50-iteration poll
# that used to wrap this call only lowered the odds.
#
# A failed git read is not a missing commit. It exits **2**, not 1: "I could not
# verify this" and "the rm was not pushed" are different findings, and reporting
# a broken read as the latter is the same lie this function exists to remove.
origin_published() {
    local subject index rc
    subject=$(git -C "$ROOT/remote.git" log -1 --format=%s refs/heads/main) || {
        rc=$?; echo "FATAL: cannot read origin's tip (git exited $rc)" >&2; exit 2; }
    index=$(git -C "$ROOT/remote.git" show refs/heads/main:builds.json) || {
        rc=$?; echo "FATAL: cannot read builds.json at origin's tip (git exited $rc)" >&2; exit 2; }
    [[ "$subject" == *"$1"* ]] \
        || { echo "  origin tip subject: $subject"; return 1; }
    [[ "$index" != *"\"$2\""* ]] \
        || { echo "  origin's index still lists $2"; return 1; }
}

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
out=$("${CLI[@]}" rm --build app-ios-local1) \
    || { echo "FAIL: rm --build exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"removed": 1' || { echo "FAIL: expected removed 1: $out"; exit 1; }
echo "$out" | grep -q '"removed_local": 1' || { echo "FAIL: expected removed_local 1: $out"; exit 1; }
has app-ios-local1 && { echo "FAIL: app-ios-local1 still in index"; exit 1; } || true
[[ ! -d "$ROOT/serve/app-ios-local1" ]] || { echo "FAIL: serve dir not removed"; exit 1; }
has app-ios-local2 || { echo "FAIL: app-ios-local2 wrongly removed"; exit 1; }
has app-macos-local || { echo "FAIL: macos build wrongly removed"; exit 1; }
origin_published 'rm build app-ios-local1' app-ios-local1 \
    || { echo "FAIL: rm not pushed to origin"; exit 1; }

# --- rm --product: removes remaining LOCAL ios builds, leaves foreign + macos ---
out=$("${CLI[@]}" rm --product io.mikeydotio.App --platform ios) \
    || { echo "FAIL: rm --product exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"removed": 1' || { echo "FAIL: product rm expected removed 1: $out"; exit 1; }
has app-ios-local2 && { echo "FAIL: app-ios-local2 not removed by product rm"; exit 1; } || true
[[ ! -d "$ROOT/serve/app-ios-local2" ]] || { echo "FAIL: local2 serve dir not removed"; exit 1; }
has app-ios-foreign || { echo "FAIL: foreign ios build removed by product rm"; exit 1; }
has app-macos-local || { echo "FAIL: macos build removed by product rm"; exit 1; }
# The product path pushes too, and nothing asserted that until now — the local
# index and serve dirs above are all reachable without origin ever being written.
origin_published 'rm product io.mikeydotio.App ios' app-ios-local2 \
    || { echo "FAIL: product rm not pushed to origin"; exit 1; }

echo "PASS"
