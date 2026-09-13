#!/usr/bin/env bash
# Fast production-policy regressions and targeted anti-vacuity mutations.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1
python3 -W error "$SCRIPT_DIR/test_liveness.py"
python3 -W error "$SCRIPT_DIR/test_mutations.py"
python3 -W error "$SCRIPT_DIR/test_packaging_preconditions.py"
