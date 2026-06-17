#!/usr/bin/env bash
# atlas-router.sh — Route /atlas arguments to atlas-cli subcommands.
# Usage: bash atlas-router.sh [arguments...]
# All output is JSON to stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="python3 ${SCRIPT_DIR}/atlas-cli"

usage_json() {
    cat <<'EOF'
{"ok": false, "error": "usage", "display": "/atlas                  — Map status and staleness tier\n/atlas status            — Same, explicit\n/atlas map               — Generate a full codebase map (orchestrated)\n/atlas update            — Incremental update of stale map docs (orchestrated)\n/atlas verify            — Lint + verification sweep without regeneration\n/atlas init              — Inject the CLAUDE.md block and gitignore entry\n/atlas remove            — Remove the CLAUDE.md block"}
EOF
}

run_cli() {
    set +e
    $CLI "$@"
    set -e
}

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
    ""|status)
        run_cli status
        ;;
    scan)
        run_cli scan
        ;;
    partition)
        run_cli partition
        ;;
    ledger)
        run_cli ledger "$@"
        ;;
    doc)
        run_cli doc "$@"
        ;;
    diffpack)
        run_cli diffpack "$@"
        ;;
    lock)
        run_cli lock "$@"
        ;;
    lint)
        run_cli lint "$@"
        ;;
    index)
        run_cli index "$@"
        ;;
    ground)
        run_cli ground "$@"
        ;;
    commit)
        run_cli commit "$@"
        ;;
    branch)
        run_cli branch "$@"
        ;;
    init)
        run_cli init
        ;;
    remove)
        run_cli remove
        ;;
    *)
        usage_json
        ;;
esac
