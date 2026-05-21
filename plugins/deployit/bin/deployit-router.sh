#!/usr/bin/env bash
# Router for the /deployit slash command.
# Delegates to bin/deployit-cli and surfaces its JSON response.
#
# Invoked by skills/deployit/SKILL.md with the user-supplied ARGUMENTS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$SCRIPT_DIR/deployit-cli"

if ! command -v python3 >/dev/null; then
    printf '{"ok": false, "display": "python3 not found on PATH"}\n'
    exit 1
fi

exec python3 "$CLI" --plugin-root "$(cd "$SCRIPT_DIR/.." && pwd)" "$@"
