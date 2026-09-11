#!/usr/bin/env bash
# Keep the test entrypoint compatible with the repository's isolation guard.
set -euo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/retire-pre-push-hook.py"
