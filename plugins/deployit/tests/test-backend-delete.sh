#!/usr/bin/env bash
# Backend DELETE routes. DELETE /deployit/<id>/ deletes a build and
# DELETE /deployit/p/<bundle>/<platform>/ deletes a product, by shelling out to
# the CLI `rm`. Only local builds (origin_base_url == base_url) are deletable;
# rows carry data-delete + a swipe-delete button only when local. Malformed ids
# 404 before shelling out; unknown/foreign targets 409 (the CLI refuses them).
#
# DEPLOYIT_SKIP_GC_PUSH makes the shelled-out CLI mutate the index in place
# without a git remote, so this test needs no network or git repo.
set -euo pipefail
export DEPLOYIT_SKIP_GC_PUSH=1
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

BASE="https://demo.tail.ts.net/deployit"
OTHER="https://other.tail.ts.net/deployit"

ROOT=$(mktemp -d)
mkdir -p "$ROOT/serve" "$ROOT/index" "$ROOT/logs"
ln -sf "$PLUGIN_ROOT" "$ROOT/_plugin_root"
cat > "$ROOT/config.toml" <<TOML
[server]
port = 18748
base_url = "$BASE"
[index]
repo = "https://example.invalid/repo.git"
[macos]
notarize = false
notary_profile = ""
TOML

# ProductA (App/ios): two LOCAL builds. ProductB (Foreign/ios): one FOREIGN build.
mk_dir() { mkdir -p "$ROOT/serve/$1"; echo fake > "$ROOT/serve/$1/App.ipa"; }
mk_dir app-ios-1
mk_dir app-ios-2
cat > "$ROOT/index/builds.json" <<JSON
{
  "version": 1,
  "builds": [
    {"id":"app-ios-1","platform":"ios","project":"App","bundle_id":"io.mikeydotio.App",
     "marketing_version":"1.0","build_number":"2","commit":"aaaaaaa",
     "timestamp":"2026-05-04T10:00:00-07:00","origin_host":"demo.tail.ts.net",
     "origin_base_url":"$BASE","install":{"kind":"itms-services","manifest_url":"x","ipa_url":"y"},
     "size_bytes":1,"archived":false,"notes":null},
    {"id":"app-ios-2","platform":"ios","project":"App","bundle_id":"io.mikeydotio.App",
     "marketing_version":"1.0","build_number":"1","commit":"bbbbbbb",
     "timestamp":"2026-05-03T10:00:00-07:00","origin_host":"demo.tail.ts.net",
     "origin_base_url":"$BASE","install":{"kind":"itms-services","manifest_url":"x","ipa_url":"y"},
     "size_bytes":1,"archived":false,"notes":null},
    {"id":"app-ios-foreign","platform":"ios","project":"Foreign","bundle_id":"io.mikeydotio.Foreign",
     "marketing_version":"1.0","build_number":"1","commit":"ccccccc",
     "timestamp":"2026-05-02T10:00:00-07:00","origin_host":"other.tail.ts.net",
     "origin_base_url":"$OTHER","install":{"kind":"itms-services","manifest_url":"x","ipa_url":"y"},
     "size_bytes":1,"archived":false,"notes":null}
  ]
}
JSON

PORT=18748
python3 "$PLUGIN_ROOT/bin/deployit-backend" --port "$PORT" --root "$ROOT" --no-git-pull \
    > "$ROOT/backend.log" 2>&1 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true; rm -rf "$ROOT"' EXIT
for _ in {1..50}; do
    curl -sf "http://127.0.0.1:$PORT/deployit/_healthz" >/dev/null && break
    sleep 0.1
done
B="http://127.0.0.1:$PORT"

has() { python3 -c "
import json,sys
d=json.load(open('$ROOT/index/builds.json'))
sys.exit(0 if any(b['id']==sys.argv[1] for b in d['builds']) else 1)
" "$1"; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

# --- Local rows carry the delete affordance; foreign rows do not ---
listing=$(curl -sf "$B/deployit/")
echo "$listing" | grep -q 'data-delete="/deployit/p/io.mikeydotio.App/ios/"' \
    || { echo "FAIL: local product row missing data-delete"; echo "$listing"; exit 1; }
echo "$listing" | grep -q 'class="swipe-delete"' \
    || { echo "FAIL: local product row missing swipe-delete button"; echo "$listing"; exit 1; }
echo "$listing" | grep -q 'data-delete="/deployit/p/io.mikeydotio.Foreign/ios/"' \
    && { echo "FAIL: foreign product row should not be deletable"; echo "$listing"; exit 1; } || true

# --- Swap structure: Install + Delete are equal-width pills sharing one fixed
#     .actions-slot via a two-button .action-track (Delete swaps into Install's
#     rectangle on swipe), not a full-height bar revealed behind .swipe-content ---
echo "$listing" | grep -q 'class="actions-slot"' \
    || { echo "FAIL: listing row missing .actions-slot"; echo "$listing"; exit 1; }
echo "$listing" | grep -Eq '<div class="action-track"><a class="install"[^>]*>[^<]*</a><button type="button" class="swipe-delete"' \
    || { echo "FAIL: local row Install + Delete not siblings inside .action-track"; echo "$listing"; exit 1; }
# Foreign row: Install pill alone in the track, no Delete button after it.
echo "$listing" | grep -Eq 'class="install"[^>]*>Install</a></div></div>' \
    || { echo "FAIL: foreign row should be Install-only inside .action-track"; echo "$listing"; exit 1; }

prod=$(curl -sf "$B/deployit/p/io.mikeydotio.App/ios/")
echo "$prod" | grep -q 'data-delete="/deployit/app-ios-1/"' \
    || { echo "FAIL: local build row missing data-delete"; echo "$prod"; exit 1; }
echo "$prod" | grep -Eq '<div class="action-track"><a class="install"[^>]*>[^<]*</a><button type="button" class="swipe-delete"' \
    || { echo "FAIL: local build row Install + Delete not siblings inside .action-track"; echo "$prod"; exit 1; }
foreign_prod=$(curl -sf "$B/deployit/p/io.mikeydotio.Foreign/ios/")
echo "$foreign_prod" | grep -q 'data-delete' \
    && { echo "FAIL: foreign build row should not be deletable"; echo "$foreign_prod"; exit 1; } || true

# --- Bad targets: 404 before shelling out ---
[[ "$(status -X DELETE "$B/deployit/app.css")" == "404" ]] \
    || { echo "FAIL: DELETE reserved word should 404"; exit 1; }
[[ "$(status -X DELETE "$B/deployit/p/io.mikeydotio.App/")" == "404" ]] \
    || { echo "FAIL: DELETE malformed product (no platform) should 404"; exit 1; }

# --- Unknown / foreign: 409 (CLI refuses), nothing removed ---
[[ "$(status -X DELETE "$B/deployit/app-ios-nope/")" == "409" ]] \
    || { echo "FAIL: DELETE unknown build should 409"; exit 1; }
[[ "$(status -X DELETE "$B/deployit/app-ios-foreign/")" == "409" ]] \
    || { echo "FAIL: DELETE foreign build should 409"; exit 1; }
has app-ios-foreign || { echo "FAIL: foreign build wrongly removed"; exit 1; }

# --- Happy path: DELETE a local build ---
code=$(curl -s -o "$ROOT/del.json" -w '%{http_code}' -X DELETE "$B/deployit/app-ios-1/")
[[ "$code" == "200" ]] || { echo "FAIL: DELETE local build expected 200, got $code: $(cat "$ROOT/del.json")"; exit 1; }
grep -q '"ok": true' "$ROOT/del.json" || { echo "FAIL: DELETE body not ok:true: $(cat "$ROOT/del.json")"; exit 1; }
has app-ios-1 && { echo "FAIL: app-ios-1 still in index"; exit 1; } || true
[[ ! -d "$ROOT/serve/app-ios-1" ]] || { echo "FAIL: serve dir not removed"; exit 1; }
has app-ios-2 || { echo "FAIL: app-ios-2 wrongly removed"; exit 1; }

# --- Happy path: DELETE the rest of the product ---
[[ "$(status -X DELETE "$B/deployit/p/io.mikeydotio.App/ios/")" == "200" ]] \
    || { echo "FAIL: DELETE product expected 200"; exit 1; }
has app-ios-2 && { echo "FAIL: app-ios-2 not removed by product delete"; exit 1; } || true
[[ ! -d "$ROOT/serve/app-ios-2" ]] || { echo "FAIL: app-ios-2 serve dir not removed"; exit 1; }

# --- GET and POST still behave ---
[[ "$(status "$B/deployit/")" == "200" ]] || { echo "FAIL: listing GET regressed"; exit 1; }

echo "PASS"
