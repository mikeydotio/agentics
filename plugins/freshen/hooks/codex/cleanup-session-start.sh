#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adapter-lib.sh"

INPUT="$(cat 2>/dev/null || true)"
codex_run_shared_hook cleanup-session-start.sh "$INPUT" >/dev/null || true
