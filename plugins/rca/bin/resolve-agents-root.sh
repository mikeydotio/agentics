#!/usr/bin/env bash
# Resolve Agents with a finite deadline and owned cancellation.
# stdout: validated absolute root only. Failures retain diagnostics on stderr.
# Exits: 0 resolved; 1 unavailable; 2 invalid/failure; 124 deadline; 130/143 cancelled.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || {
  printf '%s\n' 'rca: python3 is required for bounded Agents resolution' >&2
  exit 2
}
exec python3 -B -S "$SCRIPT_DIR/resolve-agents-root.py" "$@"
