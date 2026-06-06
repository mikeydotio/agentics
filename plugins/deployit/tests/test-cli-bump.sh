#!/usr/bin/env bash
# `deployit bump` drives a non-interactive semver bump (auto-include) via the
# discovered semver CLI. Verifies CLI discovery, the version increment, and that
# uncommitted changes are folded into the chore(release) commit.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SEMVER_CLI="$(cd "$PLUGIN_ROOT/.." && pwd)/semver/bin/semver-cli"

if [[ ! -f "$SEMVER_CLI" ]]; then
    echo "SKIP: semver-cli not found at $SEMVER_CLI"; exit 0
fi

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"
git init -q; git config user.email "t@t"; git config user.name "t"
git commit --allow-empty -q -m "init"

mkdir -p .semver
cat > .semver/config.yaml <<YAML
tracking: true
auto_bump: false
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
YAML
echo "v1.0.0" > VERSION
git add -A && git commit -q -m "feat: enable semver"

# A dirty change that "auto-include" must fold into the release commit.
echo "app change" > app.txt

out=$(DEPLOYIT_SEMVER_CLI="$SEMVER_CLI" \
      python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" \
      bump --component patch 2>&1)

echo "$out" | grep -q '"ok": true' \
    || { echo "FAIL: bump not ok"; echo "$out"; exit 1; }
echo "$out" | grep -q '"new_version": "v1.0.1"' \
    || { echo "FAIL: wrong new_version"; echo "$out"; exit 1; }

[[ "$(cat VERSION)" == "v1.0.1" ]] \
    || { echo "FAIL: VERSION not updated: $(cat VERSION)"; exit 1; }

git log -1 --pretty=%s | grep -q "chore(release): v1.0.1" \
    || { echo "FAIL: release commit missing"; git log --oneline | head -5; exit 1; }
git show --name-only --pretty=format: HEAD | grep -qx "app.txt" \
    || { echo "FAIL: dirty app.txt not folded into release commit"; git show --stat HEAD; exit 1; }
[[ -z "$(git status --porcelain)" ]] \
    || { echo "FAIL: tree not clean after include"; git status --porcelain; exit 1; }

# Discovery failure is graceful: bogus override → ok:false with guidance.
out2=$(DEPLOYIT_SEMVER_CLI="/no/such/semver-cli" \
       python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" \
       bump --component patch 2>&1 || true)
echo "$out2" | grep -q '"ok": false' \
    || { echo "FAIL: missing semver CLI should fail gracefully"; echo "$out2"; exit 1; }

echo "PASS"
