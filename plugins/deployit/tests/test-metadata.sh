#!/usr/bin/env bash
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

mkdir -p Apps/SampleApp
cat > Apps/SampleApp/project.yml <<YAML
name: SampleApp
targets:
  SampleApp-iOS:
    type: application
    platform: iOS
    settings:
      base:
        MARKETING_VERSION: "1.2.3"
        PRODUCT_BUNDLE_IDENTIFIER: "com.example.SampleApp"
YAML
mkdir -p SampleApp.xcworkspace
touch SampleApp.xcworkspace/contents.xcworkspacedata

out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" deploy --platform ios --__dump-metadata 2>&1 || true)
echo "$out" | grep -q '"project": "SampleApp"'              || { echo "FAIL: project"; echo "$out"; exit 1; }
echo "$out" | grep -q '"marketing_version": "1.2.3"'        || { echo "FAIL: version"; echo "$out"; exit 1; }
echo "$out" | grep -q '"bundle_id": "com.example.SampleApp"'|| { echo "FAIL: bundle"; echo "$out"; exit 1; }
echo "PASS"
