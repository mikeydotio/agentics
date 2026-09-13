#!/usr/bin/env bash
# Production-CLI regressions; the Make target evaluates candidate source afterward.
# Release/install-source preflight: bash scripts/check-plugin-content.sh (strict).
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo 'ERROR: python3 is required' >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -W error "$SCRIPT_DIR/plugin_content_drift.py" "$@"
