#!/usr/bin/env bash
# Run all bats test files for the greenlight plugin.
#
# Follows forge's/hook-guard's tests/run-tests.sh convention.
#
# Usage: bash tests/run-tests.sh [bats-args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats &>/dev/null; then
  echo "Error: bats-core is not installed. Install via: brew install bats-core" >&2
  exit 1
fi

bats "$SCRIPT_DIR" "$@"
