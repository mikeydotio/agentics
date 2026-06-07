#!/usr/bin/env bash
# semver-router.sh — Route /semver arguments to semver-cli subcommands.
# Usage: bash semver-router.sh [arguments...]
# All output is JSON to stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLI="python3 ${SCRIPT_DIR}/semver-cli"

usage_json() {
    cat <<'EOF'
{"ok": false, "error": "usage", "display": "/semver current                        \u2014 Show current version and status\n/semver bump <major|minor|patch>       \u2014 Bump version, generate changelog, commit\n/semver bump ... --force               \u2014 Bump even with no changes\n/semver tracking start [options]       \u2014 Initialize version tracking\n/semver tracking stop                  \u2014 Archive and disable tracking\n/semver auto-bump start                \u2014 Enable automatic version bumps\n/semver auto-bump stop                 \u2014 Disable automatic version bumps\n/semver validate                       \u2014 Verify sync integrity\n/semver repair                         \u2014 Guided repair of sync issues"}
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
    ""|current)
        run_cli current
        ;;
    bump)
        level="${1:-}"
        shift 2>/dev/null || true
        # Single-call path: bump run gathers, then executes itself when no
        # questions/prompt-hooks apply (one round-trip on the happy path).
        # Plugin root is passed so execute can run user hooks.
        run_cli bump run "$level" --plugin-root "$PLUGIN_ROOT" "$@"
        ;;
    tracking)
        subcmd="${1:-}"
        shift 2>/dev/null || true
        case "$subcmd" in
            start)
                run_cli tracking start "$@"
                ;;
            stop)
                run_cli tracking stop-gather
                ;;
            *)
                usage_json
                ;;
        esac
        ;;
    auto-bump)
        subcmd="${1:-}"
        shift 2>/dev/null || true
        case "$subcmd" in
            start)
                run_cli auto-bump start "$@"
                ;;
            stop)
                run_cli auto-bump stop
                ;;
            *)
                usage_json
                ;;
        esac
        ;;
    validate|check)
        run_cli validate
        ;;
    recommend)
        run_cli recommend
        ;;
    repair|fix)
        run_cli repair diagnose
        ;;
    *)
        usage_json
        ;;
esac
