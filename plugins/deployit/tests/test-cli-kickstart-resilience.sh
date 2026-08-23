#!/usr/bin/env bash
# AGE-85 (A): a launchd restart request that times out or is refused must not
# take `redeploy` out of the CLI's JSON contract.
#
# `_kickstart_daemon` used to be `subprocess.run(..., check=True, timeout=10)`,
# so both TimeoutExpired and CalledProcessError escaped as a raw Python
# traceback — exit 1, no JSON, nothing for the orchestrator to show. And the
# crash landed AFTER `_sync_plugin_root` had already repaired the symlinks, so
# the half-finished repair went unreported.
#
# The restart request is not the authority on whether the daemon is alive;
# `_wait_for_health` is. So a failed request is a warning carried into the
# result, never an exception.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export DEPLOYIT_STATE_DIR="$ROOT/state"
export DEPLOYIT_TAILSCALE_BIN="$TESTS_DIR/fakes/tailscale"
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/true"
export DEPLOYIT_SKIP_LAUNCHD=1
export DEPLOYIT_SKIP_KICKSTART=1
export DEPLOYIT_SKIP_VERIFY=1
export DEPLOYIT_SKIP_TAILSCALE_SERVE=1
export DEPLOYIT_SKIP_INDEX_CLONE=1

python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap \
    > "$ROOT/bootstrap.log" 2>&1 \
    || { echo "FAIL: bootstrap exited $? — the CLI said:"; cat "$ROOT/bootstrap.log"; exit 1; }

# Port isolation: bootstrap writes the default port, and the developer running
# these tests usually has a REAL daemon listening on it — which would make the
# sandbox's health probe report someone else's backend as this one's. Pin the
# sandbox to a port nothing can be on.
FREE_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
python3 - "$ROOT/state/config.toml" "$FREE_PORT" <<'ISO'
import re, sys
path, port = sys.argv[1], sys.argv[2]
body = open(path).read()
body, n = re.subn(r'(?m)^\s*port\s*=.*$', f'port = {port}', body, count=1)
assert n == 1, f'no server.port line in {path}:\n{body}'
open(path, 'w').write(body)
ISO

# A dev-checkout-shaped target for `redeploy --source`.
FAKE="$ROOT/fake-plugin"
mkdir -p "$FAKE/bin" "$FAKE/tests"
echo '#!/usr/bin/env python3' > "$FAKE/bin/deployit-backend"
chmod +x "$FAKE/bin/deployit-backend"
echo '#!/usr/bin/env bash' > "$FAKE/tests/verify-live.sh"
chmod +x "$FAKE/tests/verify-live.sh"

# The kickstart must actually run for the rest of this test to mean anything.
unset DEPLOYIT_SKIP_KICKSTART

resolve() { python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"; }

# assert_ok_with_warning <label> <want-substring-in-warning>
assert_ok_with_warning() {
    local label="$1" want="$2" out rc
    set +e
    out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" \
              redeploy --source "$FAKE" 2>"$ROOT/stderr.log")
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "FAIL[$label]: redeploy exited $rc — a failed restart request must not"
        echo "              fail the command. stdout: $out"
        echo "              stderr: $(cat "$ROOT/stderr.log")"
        exit 1
    fi
    grep -q 'Traceback' "$ROOT/stderr.log" \
        && { echo "FAIL[$label]: traceback escaped:"; cat "$ROOT/stderr.log"; exit 1; }
    WANT="$want" LABEL="$label" python3 -c "
import json, os, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(f\"FAIL[{os.environ['LABEL']}]: output is not JSON: {raw!r}\")
label, want = os.environ['LABEL'], os.environ['WANT']
assert d.get('ok') is True, f'FAIL[{label}]: expected ok=true, got: {d}'
warn = d.get('kickstart_warning')
assert warn, f'FAIL[{label}]: expected a kickstart_warning, got: {d}'
assert want in warn, f'FAIL[{label}]: warning {warn!r} does not mention {want!r}'
assert warn in d.get('display', ''), \
    f'FAIL[{label}]: warning must be visible in display, got: {d.get(\"display\")!r}'
" <<<"$out" || exit 1
    # The repair that did land must still have landed.
    [[ "$(resolve "$ROOT/state/_plugin_root")" == "$(resolve "$FAKE")" ]] \
        || { echo "FAIL[$label]: symlink repair was lost"; exit 1; }
}

# --- Case 1: the restart request outlives its timeout.
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/launchctl-hang"
export DEPLOYIT_KICKSTART_TIMEOUT=1
assert_ok_with_warning "timeout" "timed out"

# --- Case 2: launchctl refuses the request outright.
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/launchctl-fail"
unset DEPLOYIT_KICKSTART_TIMEOUT
assert_ok_with_warning "nonzero-exit" "113"

# --- Case 3: launchctl is not on PATH at all.
export DEPLOYIT_LAUNCHCTL_BIN="$ROOT/no-such-launchctl"
assert_ok_with_warning "missing-binary" "launchctl"

# --- Case 4: a clean restart reports no warning.
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/true"
clean=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" \
            redeploy --source "$FAKE") \
    || { echo "FAIL: clean redeploy exited $? — $clean"; exit 1; }
python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True, d
assert d.get('kickstart_warning') is None, \
    f'a clean kickstart must not warn, got: {d[\"kickstart_warning\"]!r}'
" <<<"$clean" || exit 1

# --- Case 5: the health probe is the authority. When it fails, the command
# fails — and the earlier restart-request warning travels with it as context.
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/launchctl-fail"
unset DEPLOYIT_SKIP_VERIFY
set +e
unhealthy=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" \
                redeploy --source "$FAKE" 2>"$ROOT/stderr5.log")
rc5=$?
set -e
[[ $rc5 -ne 0 ]] || { echo "FAIL: unhealthy daemon should fail redeploy: $unhealthy"; exit 1; }
python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is False, d
assert 'healthy' in d['display'], d
assert d.get('kickstart_warning'), \
    f'the restart-request failure must travel with the health failure: {d}'
" <<<"$unhealthy" || exit 1

echo "PASS"
