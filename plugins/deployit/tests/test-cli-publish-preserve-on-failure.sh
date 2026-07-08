#!/usr/bin/env bash
# When the direct push is blocked AND `gh pr create` fails, the commit must still
# be preserved: the deploy/<id> branch is already pushed (commit safe on origin),
# and the CLI fails with ok:false surfacing the branch + a manual PR-create URL —
# never a silent reset-and-drop. Also covers the auth path: a push rejected with
# an auth message preserves the commit on a local branch and does not open a PR.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
BASE="https://demo.tail.ts.net/deployit"

setup_index() {  # $1 = pre-receive hook body file
  rm -rf "$ROOT/remote.git" "$ROOT/index" "$ROOT/serve"
  git init --bare -q --initial-branch=main "$ROOT/remote.git"
  mkdir -p "$ROOT/index" "$ROOT/serve"
  git -C "$ROOT/index" init -q --initial-branch=main
  git -C "$ROOT/index" config user.email "test@example.invalid"
  git -C "$ROOT/index" config user.name "test"
  git -C "$ROOT/index" remote add origin "$ROOT/remote.git"
  printf '{\n  "version": 1,\n  "builds": []\n}\n' > "$ROOT/index/builds.json"
  git -C "$ROOT/index" add builds.json
  git -C "$ROOT/index" commit -q -m seed
  git -C "$ROOT/index" push -q --set-upstream origin main
  cp "$1" "$ROOT/remote.git/hooks/pre-receive"
  chmod +x "$ROOT/remote.git/hooks/pre-receive"
}

# Ruleset hook: reject main (GH013), allow deploy/*.
cat > "$ROOT/hook-ruleset" <<'HOOK'
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

# Auth hook: reject EVERY ref with an authentication-failure message.
cat > "$ROOT/hook-auth" <<'HOOK'
#!/usr/bin/env bash
echo "fatal: Authentication failed for 'https://github.com/mikeydotio/deployit-index.git/'" >&2
exit 1
HOOK

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"

# ---- case 1: pr create fails after the branch is pushed ----
setup_index "$ROOT/hook-ruleset"
FAKE_GH_LOG="$ROOT/gh1.log" FAKE_GH_PR_CREATE_FAIL=1 \
python3 - "$PLUGIN_ROOT" "$ROOT" "$BASE" "prcreate" <<'PY'
import contextlib, importlib.machinery, importlib.util, io, json, pathlib, subprocess, sys
plugin_root, root, base, mode = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
                                 sys.argv[3], sys.argv[4])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

new_id = "app-ios-PRFAIL"
(root / "serve" / new_id).mkdir(parents=True, exist_ok=True)
entry = {"id": new_id, "platform": "ios", "project": "App",
         "bundle_id": "io.mikeydotio.App", "marketing_version": "1.3",
         "build_number": "212", "commit": "prf1234",
         "timestamp": "2026-07-08T12:00:00-07:00",
         "origin_host": "demo.tail.ts.net", "origin_base_url": base,
         "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
         "size_bytes": 1, "archived": False, "notes": None}
idx = {"repo": "https://github.com/mikeydotio/deployit-index.git",
       "publish": "auto", "auto_merge": True}

buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    try:
        mod._append_to_index(root, entry, idx=idx)
        print('{"ok": true, "display": "unexpected success"}')
    except SystemExit:
        pass
out = json.loads(buf.getvalue())
assert out.get("ok") is False, out
assert out.get("branch") == f"deploy/{new_id}", out
assert "pr_create_url" in out, out
# Commit is safe on the origin branch despite the pr-create failure.
ref = subprocess.run(["git", "-C", str(root / "remote.git"), "show-ref",
                      f"refs/heads/deploy/{new_id}"], capture_output=True, text=True)
assert ref.returncode == 0, "deploy branch missing on origin"
print("ok1")
PY

# ---- case 2: auth failure preserves on a LOCAL branch, no PR opened ----
setup_index "$ROOT/hook-auth"
FAKE_GH_LOG="$ROOT/gh2.log" \
python3 - "$PLUGIN_ROOT" "$ROOT" "$BASE" "auth" <<'PY'
import contextlib, importlib.machinery, importlib.util, io, json, pathlib, subprocess, sys
plugin_root, root, base, mode = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
                                 sys.argv[3], sys.argv[4])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

new_id = "app-ios-AUTHFAIL"
(root / "serve" / new_id).mkdir(parents=True, exist_ok=True)
entry = {"id": new_id, "platform": "ios", "project": "App",
         "bundle_id": "io.mikeydotio.App", "marketing_version": "1.4",
         "build_number": "213", "commit": "auth123",
         "timestamp": "2026-07-08T13:00:00-07:00",
         "origin_host": "demo.tail.ts.net", "origin_base_url": base,
         "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
         "size_bytes": 1, "archived": False, "notes": None}
idx = {"repo": "https://github.com/mikeydotio/deployit-index.git",
       "publish": "auto", "auto_merge": True}

buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    try:
        mod._append_to_index(root, entry, idx=idx)
        print('{"ok": true, "display": "unexpected success"}')
    except SystemExit:
        pass
out = json.loads(buf.getvalue())
assert out.get("ok") is False, out
assert out.get("branch") == f"deploy/{new_id}-local", out
# No PR was attempted (auth fails before the PR fallback).
log = (root / "gh2.log")
assert (not log.exists()) or ("pr create" not in log.read_text()), "auth path must not call gh pr"
# Commit preserved on the LOCAL recovery branch; main reset clean.
lref = subprocess.run(["git", "-C", str(root / "index"), "rev-parse",
                       f"deploy/{new_id}-local"], capture_output=True, text=True)
assert lref.returncode == 0, "local recovery branch missing"
print("ok2")
PY

echo "PASS"
