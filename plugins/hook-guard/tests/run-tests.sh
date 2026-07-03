#!/usr/bin/env bash
# Run all bats test files for the hook-guard plugin.
#
# Follows forge's tests/run-tests.sh convention: real bats files live
# alongside the scripts they test (lib/, hooks/) rather than in this
# dedicated tests/ directory — this runner just points bats at both.
#
# Usage: bash tests/run-tests.sh [bats-args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v bats &>/dev/null; then
  echo "Error: bats-core is not installed. Install via: brew install bats-core" >&2
  exit 1
fi

bats "$PLUGIN_DIR/lib" "$PLUGIN_DIR/hooks" "$@"
