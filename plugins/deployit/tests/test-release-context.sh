#!/usr/bin/env bash
# `deployit release-context` returns the facts the SKILL turns into release notes:
# owner/repo, the previous release tag, commits since it (with commit URLs), and
# closed issues (with URLs). git is real (temp repo); gh is faked.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
repo="$ROOT/app"; mkdir -p "$repo"; cd "$repo"
git init -q
git config user.email t@t; git config user.name t
git remote add origin https://github.com/mikeydotio/App.git
echo a > a.txt; git add .; git commit -qm "feat: first commit"
git tag v1.0.0
echo b > b.txt; git add .; git commit -qm "fix: second thing closes #12"
echo c > c.txt; git add .; git commit -qm "feat: third thing"

export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export FAKE_GH_PREV_TAG="v1.0.0"
export FAKE_GH_ISSUES_JSON='[{"number":12,"title":"Crash on launch","url":"https://github.com/mikeydotio/App/issues/12","closedAt":"2026-06-01T00:00:00Z"}]'

out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" release-context) \
    || { echo "FAIL: release-context exited $? — the CLI said: $out"; exit 1; }
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['ok'], d
assert d['owner_repo'] == 'mikeydotio/App', d
assert d['prev_tag'] == 'v1.0.0', d
subs = [c['subject'] for c in d['commits']]
assert any('second thing' in s for s in subs), subs
assert any('third thing' in s for s in subs), subs
assert not any('first commit' in s for s in subs), 'commits before the tag must be excluded'
assert all(c['url'].startswith('https://github.com/mikeydotio/App/commit/') for c in d['commits']), d
iss = d['closed_issues']
assert iss and iss[0]['number'] == 12 and iss[0]['url'].endswith('/issues/12'), d
"

echo "PASS"
