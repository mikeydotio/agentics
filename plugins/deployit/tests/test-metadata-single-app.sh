#!/usr/bin/env bash
# Single-app layout: <Name>.xcodeproj + ./project.yml at the repo root, with
# unquoted PRODUCT_BUNDLE_IDENTIFIER. Mirrors test-metadata.sh for the
# Lillist-style monorepo layout.

set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
cd "$REPO"
git init -q
git config user.email "test@test"
git config user.name  "test"
git commit --allow-empty -q -m "init"

mkdir -p moshtail.xcodeproj
touch moshtail.xcodeproj/project.pbxproj
cat > project.yml <<YAML
name: moshtail
targets:
  moshtail:
    type: application
    platform: iOS
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.example.moshtail
        MARKETING_VERSION: "1.0.0"
YAML

out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" deploy --platform ios --__dump-metadata 2>&1 || true)
echo "$out" | grep -q '"project": "moshtail"'                || { echo "FAIL: project";              echo "$out"; exit 1; }
echo "$out" | grep -q '"marketing_version": "1.0.0"'         || { echo "FAIL: version";              echo "$out"; exit 1; }
echo "$out" | grep -q '"bundle_id": "io.example.moshtail"'   || { echo "FAIL: bundle (unquoted)";    echo "$out"; exit 1; }
echo "$out" | grep -q '"xcode_container_flag": "-project"'   || { echo "FAIL: container flag";       echo "$out"; exit 1; }
echo "$out" | grep -q '"default_scheme": "moshtail"'         || { echo "FAIL: default scheme";       echo "$out"; exit 1; }
echo "$out" | grep -q '"project_yml": ".*/project.yml"'      || { echo "FAIL: project_yml path";     echo "$out"; exit 1; }
echo "PASS"
