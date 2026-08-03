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
{"ok": false, "error": "usage", "display": "/semver current                        \u2014 Show current version and status\n/semver bump <major|minor|patch>       \u2014 Bump version, generate changelog, commit\n/semver bump ... --force               \u2014 Bump even with no changes\n/semver set <vX.Y.Z>                    \u2014 Assign an explicit version (skip incremental bump)\n/semver init [vX.Y.Z]                   \u2014 Enable tracking + auto-bump and initialize (default v0.1.0)\n/semver tracking start [options]       \u2014 Initialize version tracking\n/semver tracking stop                  \u2014 Archive and disable tracking\n/semver auto-bump start                \u2014 Enable automatic version bumps\n/semver auto-bump stop                 \u2014 Disable automatic version bumps\n/semver validate                       \u2014 Verify sync integrity\n/semver repair                         \u2014 Guided repair of sync issues"}
EOF
}

# Exit status of the most recent run_cli invocation, propagated as this
# script's own exit code at the bottom of the file. Previously run_cli ended
# with a bare `set -e` (itself exit 0), so every CLI outcome — success,
# failure, or the new "bump landed but post-bump hooks were skipped" (3) —
# was silently reported as 0. Stays 0 for the usage_json branches, which
# never call the CLI at all.
RC=0

run_cli() {
    set +e
    $CLI "$@"
    RC=$?
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
    set)
        # Requires an explicit target version. set run gathers, then executes
        # itself on the happy path (like bump run). Plugin root threaded so the
        # post-bump hooks (e.g. plugin-version sync) fire.
        version="${1:-}"
        shift 2>/dev/null || true
        if [ -z "$version" ]; then
            usage_json
        else
            run_cli set run "$version" --plugin-root "$PLUGIN_ROOT" "$@"
        fi
        ;;
    init)
        # Version is optional (defaults to v0.1.0) — don't pre-extract it;
        # argparse consumes it as an optional positional. init run detects
        # existing artifacts and either does a clean init or returns an
        # assessment with tailored options.
        run_cli init run --plugin-root "$PLUGIN_ROOT" "$@"
        ;;
    tracking)
        subcmd="${1:-}"
        shift 2>/dev/null || true
        case "$subcmd" in
            start)
                # Plugin root threaded so post-bump hooks fire when --version
                # seeds an initial VERSION (mirrors bump/set/init above).
                run_cli tracking start --plugin-root "$PLUGIN_ROOT" "$@"
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

exit "$RC"
