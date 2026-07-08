#!/usr/bin/env bash
# Deploy publish under an active ruleset, auto_merge=false. The publisher should
# push the deploy/<id> branch, open a PR, and leave it OPEN — returning
# published=false with the PR URL and branch, never merging and never discarding
# the commit. Local main stays clean at origin/main.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
BASE="https://demo.tail.ts.net/deployit"

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

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export FAKE_GH_LOG="$ROOT/gh.log"
export FAKE_GH_PR_URL="https://github.com/mikeydotio/deployit-index/pull/9"

python3 - "$PLUGIN_ROOT" "$ROOT" "$BASE" <<'PY'
import importlib.machinery, importlib.util, pathlib, subprocess, sys
plugin_root, root, base = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

new_id = "app-ios-PENDING"
(root / "serve" / new_id).mkdir(parents=True, exist_ok=True)
entry = {
    "id": new_id, "platform": "ios", "project": "App",
    "bundle_id": "io.mikeydotio.App", "marketing_version": "1.2",
    "build_number": "211", "commit": "pend123",
    "timestamp": "2026-07-08T11:00:00-07:00",
    "origin_host": "demo.tail.ts.net", "origin_base_url": base,
    "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
    "size_bytes": 1, "archived": False, "notes": None,
}
idx = {"repo": "https://github.com/mikeydotio/deployit-index.git",
       "publish": "auto", "auto_merge": False}
result = mod._append_to_index(root, entry, idx=idx)

assert result["published"] is False, result
assert result["pr_url"] == "https://github.com/mikeydotio/deployit-index/pull/9", result
assert result["branch"] == f"deploy/{new_id}", result

log = (root / "gh.log").read_text()
assert "pr create" in log, log
assert "pr merge" not in log, "must NOT merge when auto_merge=false"

# Commit preserved on the origin's deploy branch.
ref = subprocess.run(["git", "-C", str(root / "remote.git"), "show-ref",
                      f"refs/heads/deploy/{new_id}"], capture_output=True, text=True)
assert ref.returncode == 0, "deploy branch missing on origin"

# Local main clean at origin/main.
local_head = subprocess.run(["git", "-C", str(root / "index"), "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()
origin_main = subprocess.run(["git", "-C", str(root / "remote.git"), "rev-parse", "main"],
                             capture_output=True, text=True, check=True).stdout.strip()
assert local_head == origin_main, (local_head, origin_main)
print("ok")
PY

echo "PASS"
