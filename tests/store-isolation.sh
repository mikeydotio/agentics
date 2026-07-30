#!/usr/bin/env bash
# Every test target runs against a storyhook store of its own.
#
# The defect class this pins is "a suite drives the `story` CLI without
# isolating its data home". On 2026-07-30 one `make test` run put 394 projects
# into the developer's real store, 234 of them carrying stories, because that
# was true of every target here — and nothing in this repository had changed.
# Storyhook moved its data into a single global store, and self-isolating
# fixtures stopped being self-isolating.
#
# A new target added without the wrapper is exactly how it comes back, so the
# check is mechanical rather than a note in a README.

set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { echo "  $*" >&2; }

# Every recipe line that runs a suite, other than the wrapper itself.
# This guard and the wrapper are exempt: neither drives the `story` CLI to
# build fixtures, and the guard has to invoke the wrapper to test it.
suite_lines=$(grep -nE '^\t.*\bbash (tests/|plugins/)' Makefile \
    | grep -v 'with-isolated-store.sh bash' \
    | grep -v 'tests/store-isolation.sh' \
    || true)

if [ -n "$suite_lines" ]; then
    echo "FAIL: these Makefile recipes run a suite without an isolated store:" >&2
    while IFS= read -r line; do note "$line"; done <<<"$suite_lines"
    note ""
    note "Route them through the wrapper:"
    note "    bash tests/with-isolated-store.sh bash <suite>"
    fail=1
fi

# The wrapper has to actually export what it claims to. A wrapper that stopped
# setting one of these would leave every suite silently unprotected again — and
# the daemon address matters as much as the data dir: a client that dials the
# real daemon on :3456 writes to the real store no matter what
# STORYHOOK_DATA_DIR says, because the daemon holds the store, not the client.
for var in STORYHOOK_INVOKER STORYHOOK_DATA_DIR XDG_STATE_HOME STORYHOOK_DAEMON_ADDR STORYHOOK_PARENT_PID; do
    if ! grep -q "export $var" tests/with-isolated-store.sh; then
        echo "FAIL: tests/with-isolated-store.sh no longer exports $var" >&2
        fail=1
    fi
done

# And it has to work: run it and confirm the variable arrives, pointing
# somewhere that is not the real store.
observed=$(bash tests/with-isolated-store.sh bash -c 'printf "%s" "$STORYHOOK_DATA_DIR"')
case "$observed" in
    "$HOME"/*)
        echo "FAIL: the wrapper handed a suite a data dir inside \$HOME: $observed" >&2
        fail=1
        ;;
    /private/tmp/agentics-store.*) ;;
    *)
        echo "FAIL: the wrapper produced an unexpected data dir: $observed" >&2
        fail=1
        ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "store-isolation: every test target runs against its own store"
fi
exit "$fail"
