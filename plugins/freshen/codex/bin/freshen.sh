#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FRESHEN_HOST=codex
exec bash "$SCRIPT_DIR/../../bin/freshen.sh" "$@"
