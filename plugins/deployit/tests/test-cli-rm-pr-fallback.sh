#!/usr/bin/env bash
# `deployit rm` under an active ruleset (the web UI's swipe-to-delete path). The
# on-disk delete must happen ONLY after the index removal lands on main:
#   A) auto_merge=false → removal is pending on an open PR → ok:true but the
#      serve/<id>/ dir is KEPT (removed_local=0) until the PR merges.
#   B) `gh pr create` fails (e.g. daemon can't reach gh) → ok:false, and the
#      serve/<id>/ dir is KEPT — a failed delete never orphans files.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
BASE="https://demo.tail.ts.net/deployit"
export DEPLOYIT_STATE_DIR="$ROOT"
export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"

write_config() {  # $1 = auto_merge (true|false)
  cat > "$ROOT/config.toml" <<TOML
[server]
port = 8733
base_url = "$BASE"
[index]
repo = "https://github.com/mikeydotio/deployit-index.git"
publish = "auto"
auto_merge = $1
[macos]
notarize = false
notary_profile = ""
TOML
}

seed_index() {
  rm -rf "$ROOT/remote.git" "$ROOT/index" "$ROOT/serve"
  git init --bare -q --initial-branch=main "$ROOT/remote.git"
  mkdir -p "$ROOT/index" "$ROOT/serve"
  git -C "$ROOT/index" init -q --initial-branch=main
  git -C "$ROOT/index" config user.email "test@example.invalid"
  git -C "$ROOT/index" config user.name "test"
  git -C "$ROOT/index" remote add origin "$ROOT/remote.git"
  python3 - "$ROOT" "$BASE" <<'PY'
import json, pathlib, sys
root, base = pathlib.Path(sys.argv[1]), sys.argv[2]
d = root / "serve" / "app-ios-rmtarget"
d.mkdir(parents=True, exist_ok=True)
(d / "App.ipa").write_text("fake")
(d / "_meta.json").write_text(json.dumps({"id": "app-ios-rmtarget", "timestamp": "t"}))
build = {"id": "app-ios-rmtarget", "platform": "ios", "project": "App",
         "bundle_id": "io.mikeydotio.App", "marketing_version": "1.0",
         "build_number": "1", "commit": "seed123", "timestamp": "2026-05-04T10:00:00-07:00",
         "origin_host": "x", "origin_base_url": base,
         "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
         "size_bytes": 1, "archived": False, "notes": None}
(root / "index" / "builds.json").write_text(
    json.dumps({"version": 1, "builds": [build]}, indent=2) + "\n")
PY
  git -C "$ROOT/index" add builds.json
  git -C "$ROOT/index" commit -q -m seed
  git -C "$ROOT/index" push -q --set-upstream origin main
  cat > "$ROOT/remote.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read -r old new ref; do
  if [ "$ref" = "refs/heads/main" ]; then
    echo "remote: error: GH013: Repository rule violations found for refs/heads/main." >&2
    echo "remote: - Changes must be made through a pull request." >&2
    exit 1
  fi
done
exit 0
HOOK
  chmod +x "$ROOT/remote.git/hooks/pre-receive"
}

CLI=("python3" "$PLUGIN_ROOT/bin/deployit-cli" "--plugin-root" "$PLUGIN_ROOT")

# ---- case A: auto_merge=false → pending PR, serve dir kept ----
write_config false
seed_index
out=$(FAKE_GH_LOG="$ROOT/ghA.log" FAKE_GH_PR_URL="https://github.com/x/y/pull/3" \
      "${CLI[@]}" rm --build app-ios-rmtarget) \
    || { echo "FAIL A: rm --build exited $? — the CLI said: $out"; exit 1; }
echo "$out" | grep -q '"ok": true'          || { echo "FAIL A: expected ok true; $out"; exit 1; }
echo "$out" | grep -q '"index_pending": true'|| { echo "FAIL A: expected index_pending; $out"; exit 1; }
echo "$out" | grep -q '"removed_local": 0'   || { echo "FAIL A: serve dir should be kept; $out"; exit 1; }
[[ -d "$ROOT/serve/app-ios-rmtarget" ]]      || { echo "FAIL A: serve dir wrongly deleted"; exit 1; }
grep -q "pr create" "$ROOT/ghA.log"          || { echo "FAIL A: pr create not invoked"; exit 1; }
grep -q "pr merge"  "$ROOT/ghA.log"          && { echo "FAIL A: must not merge"; exit 1; } || true

# ---- case B: gh pr create fails → ok:false, serve dir kept ----
write_config true
seed_index
out=$(FAKE_GH_LOG="$ROOT/ghB.log" FAKE_GH_PR_CREATE_FAIL=1 \
      "${CLI[@]}" rm --build app-ios-rmtarget 2>&1 || true)
echo "$out" | grep -q '"ok": false'     || { echo "FAIL B: expected ok false; $out"; exit 1; }
[[ -d "$ROOT/serve/app-ios-rmtarget" ]] || { echo "FAIL B: serve dir wrongly deleted on failure"; exit 1; }

echo "PASS"
