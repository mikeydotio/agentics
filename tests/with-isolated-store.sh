#!/usr/bin/env bash
# Runs a test suite against a storyhook store of its own.
#
# WHY THIS EXISTS
#
# Several suites here drive the `story` CLI to build fixtures — a throwaway
# repository, a project in it, a story or two. Until storyhook moved its data
# into a single global store, that was self-isolating: `story init` wrote a
# `.storyhook/` directory *inside* the fixture, and it was deleted with the
# fixture. Nothing here had to think about isolation, so nothing here did.
#
# One global store ended that silently. Every one of those fixture sites became
# a permanent write into the developer's real tracker — no error, nothing to
# notice. On 2026-07-30 a single `make test` run put 394 projects into a real
# store, 234 of them carrying stories, and made the storyhook dashboard
# unusable: 407 registered repositories against 13 real ones.
#
# Nothing in this repository changed to cause that, which is the point. Safe
# code became unsafe underneath it.
#
# WHAT IT DOES
#
#   STORYHOOK_INVOKER=local  the load-bearing one. A storyhook client that
#                         cannot reach its preferred address falls back to the
#                         portfile under XDG_STATE_HOME — and finds the real
#                         daemon on :3456, which holds the REAL store and serves
#                         writes from it no matter what STORYHOOK_DATA_DIR says.
#                         `local` opens the store in-process instead, so the
#                         data dir above is actually the store being written.
#                         Setting the data dir alone is NOT enough: measured, a
#                         run so configured still put 55 projects in the real
#                         store.
#   STORYHOOK_DATA_DIR    a store of this run's own, deleted on exit
#   XDG_STATE_HOME        so daemon portfile/pidfile/logs land here too, and a
#                         fallback cannot rediscover the real daemon
#   STORYHOOK_DAEMON_ADDR a kernel-assigned port, so nothing binds the real
#                         daemon's :3456
#   STORYHOOK_PARENT_PID  so any daemon a suite spawns dies with this run
#
# `/private/tmp` rather than `$TMPDIR`: the latter is Spotlight-indexed on
# macOS, and suites that create many small files there stall as `mds_stores`
# backlogs.
#
# Storyhook 1.0.0 also refuses, by itself, to create a project at a temporary
# path in a non-temporary store. That refusal is the backstop; this is the fix.
# A suite run without this wrapper now fails loudly instead of polluting.

set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: with-isolated-store.sh <command> [args...]" >&2
    exit 2
fi

_root="$(mktemp -d /private/tmp/agentics-store.XXXXXX)"
export STORYHOOK_INVOKER="local"
export STORYHOOK_DATA_DIR="$_root/data"
export XDG_STATE_HOME="$_root/state"
mkdir -p "$STORYHOOK_DATA_DIR" "$XDG_STATE_HOME"
export STORYHOOK_DAEMON_ADDR="${STORYHOOK_DAEMON_ADDR:-127.0.0.1:0}"
export STORYHOOK_PARENT_PID="$$"

cleanup() {
    rm -rf "$_root"
}
trap cleanup EXIT

"$@"
