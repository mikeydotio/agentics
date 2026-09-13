#!/usr/bin/env bash
# Run the host contracts without requiring a third-party Python test framework.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -B -m unittest discover -s "$TESTS_DIR" -p 'codex_*_test.py' -v
