#!/usr/bin/env bash
# Production delivery status and all-host standalone-entry contracts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -B -W error "$SCRIPT_DIR/delivery_test.py"
