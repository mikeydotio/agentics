#!/usr/bin/env bash
# Native metadata coverage is applicable only on macOS.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    echo "SKIP: macOS archive metadata is not applicable on this platform"
    exit 0
fi
export PYTHONDONTWRITEBYTECODE=1
exec python3 -W error "$(dirname "${BASH_SOURCE[0]}")/worktree_preservation.py" "$@"
