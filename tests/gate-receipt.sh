#!/usr/bin/env bash
# The default suite uses private Make legs; an available writer adds real Git.
set -euo pipefail
exec python3 -W error "$(dirname "${BASH_SOURCE[0]}")/gate_receipt.py" "$@"
