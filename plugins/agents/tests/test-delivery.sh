#!/usr/bin/env bash
# Run the delivery suites and generated-copy check inside the caller's isolated store.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

python3 -B -W error "$TESTS_DIR/test_delivery_mutations.py"
python3 -B -W error "$TESTS_DIR/test_delivery.py"
python3 -B "$REPO_ROOT/scripts/sync-agent-delivery.py" --check
