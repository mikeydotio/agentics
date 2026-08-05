#!/usr/bin/env bash
# preflight: decides whether a deploy needs a semver version bump first, by
# comparing the project's current VERSION against the newest already-published
# build of the same (bundle_id, platform). No xcodebuild; index is seeded.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

REPO=$(mktemp -d)
STATE=$(mktemp -d)
trap 'rm -rf "$REPO" "$STATE"' EXIT

cd "$REPO"
git init -q
git config user.email "test@test"; git config user.name "test"

# Minimal single-app Xcode layout (matches _derive_metadata single-app shape).
cat > project.yml <<YAML
name: SampleApp
targets:
  SampleApp:
    settings:
      base:
        MARKETING_VERSION: "1.2.3"
        PRODUCT_BUNDLE_IDENTIFIER: "com.example.SampleApp"
YAML
mkdir -p SampleApp.xcodeproj
git add -A && git commit -q -m "init"

run_preflight() {
    DEPLOYIT_STATE_DIR="$STATE" DEPLOYIT_SKIP_INDEX_PULL=1 \
      python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" \
      preflight --platform ios 2>&1
}

seed_index() {  # $1 = builds-array contents (JSON)
    mkdir -p "$STATE/index"
    printf '{"version":1,"builds":[%s]}\n' "$1" > "$STATE/index/builds.json"
}

assert() {  # $1=output $2=needle $3=label
    echo "$1" | grep -q "$2" || { echo "FAIL: $3"; echo "$1"; exit 1; }
}
refute() {  # $1=output $2=needle $3=label
    echo "$1" | grep -q "$2" && { echo "FAIL: $3"; echo "$1"; exit 1; } || true
}

# --- Case 1: no .semver → semver inactive, no bump ---
seed_index ""
out=$(run_preflight) \
    || { echo "FAIL: preflight exited $? — the CLI said: $out"; exit 1; }
assert "$out" '"semver_active": false' "case1 semver_active false"
assert "$out" '"bump_needed": false'  "case1 bump_needed false"

# Activate semver for the remaining cases.
mkdir -p .semver
cat > .semver/config.yaml <<YAML
tracking: true
version_prefix: "v"
target_branch: "main"
YAML
echo "v2.0.0" > VERSION
git add -A && git commit -q -m "feat: enable semver"

# --- Case 2: active, no prior build for this product → no bump ---
seed_index ""
out=$(run_preflight) \
    || { echo "FAIL: preflight exited $? — the CLI said: $out"; exit 1; }
assert "$out" '"semver_active": true'   "case2 active"
assert "$out" '"version_changed": true' "case2 changed (no prior)"
assert "$out" '"bump_needed": false'    "case2 no bump"

# --- Case 3: active, latest published == current VERSION → bump needed ---
seed_index '{"id":"x","platform":"ios","project":"SampleApp","bundle_id":"com.example.SampleApp","semver_version":"v2.0.0","build_number":"3","timestamp":"2026-06-01T10:00:00-07:00","origin_base_url":"https://h/deployit"}'
out=$(run_preflight) \
    || { echo "FAIL: preflight exited $? — the CLI said: $out"; exit 1; }
assert "$out" '"bump_needed": true' "case3 bump needed"
assert "$out" '"v2.0.1"' "case3 patch candidate"
assert "$out" '"v2.1.0"' "case3 minor candidate"
assert "$out" '"v3.0.0"' "case3 major candidate"

# --- Case 4: active, latest published != current VERSION → no bump ---
seed_index '{"id":"y","platform":"ios","project":"SampleApp","bundle_id":"com.example.SampleApp","semver_version":"v1.9.0","build_number":"2","timestamp":"2026-06-01T10:00:00-07:00","origin_base_url":"https://h/deployit"}'
out=$(run_preflight) \
    || { echo "FAIL: preflight exited $? — the CLI said: $out"; exit 1; }
assert "$out" '"version_changed": true' "case4 changed"
assert "$out" '"bump_needed": false'    "case4 no bump"

echo "PASS"
