#!/usr/bin/env bash
# Run all bats test files for the forge plugin.
#
# Unlike semver/deployit (which use a custom `test_*`-function
# discovery harness), forge's suites are real bats files that live
# alongside the scripts they test in bin/ and hooks/ rather than in a
# dedicated tests/ directory — so this runner just points bats at both.
#
# Usage: bash tests/run-tests.sh [bats-args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v bats &>/dev/null; then
  echo "Error: bats-core is not installed. Install via: brew install bats-core" >&2
  exit 1
fi

bats "$PLUGIN_DIR/bin" "$PLUGIN_DIR/hooks" "$@"
