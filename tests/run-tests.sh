#!/usr/bin/env bash
# Run all bats test files in the tests/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

if ! command -v bats &>/dev/null; then
  echo "Error: bats-core is not installed. Install via: sudo apt-get install bats" >&2
  exit 1
fi

bats "$SCRIPT_DIR"/*.bats "$@"
