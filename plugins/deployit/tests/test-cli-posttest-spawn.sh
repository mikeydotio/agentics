#!/usr/bin/env bash
# Out-of-band post-deploy test spawn wiring (issue #90). _spawn_post_deploy_test:
#   * present script  -> spawns bin/deployit-posttest DETACHED (start_new_session,
#                        all stdio DEVNULL) and writes a `running` status marker;
#   * DEPLOYIT_SKIP_POSTTEST -> no spawn, returns skipped;
#   * absent script   -> no spawn, writes `not_configured` (never a silent no-op);
# plus a source guard that the spawn runs AFTER the index append + backend refresh
# (so it only fires once the build is fully published).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, json, os, pathlib, sys

plugin_root = pathlib.Path(sys.argv[1]); root = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

state = root / "state"; state.mkdir()
proj = root / "proj"; (proj / ".deployit").mkdir(parents=True)
script = proj / ".deployit" / "post-deploy-test.sh"
INSTALL = "https://demo.tail.ts.net/deployit/bid1/"


class FakeProc:
    pid = 4242


class FakeSub:
    """Stand in for the subprocess module so we capture Popen without spawning."""
    DEVNULL = -3
    calls = []

    @staticmethod
    def Popen(cmd, **kw):
        FakeSub.calls.append((cmd, kw))
        return FakeProc()


mod.subprocess = FakeSub

def status_path(bid):
    return state / "posttest" / f"{bid}.json"

# 1) script present -> detached spawn + `running` marker
script.write_text("#!/usr/bin/env bash\nmake ui-test\n")
FakeSub.calls.clear()
res = mod._spawn_post_deploy_test(state, plugin_root, proj, "bid1", INSTALL)
assert res["status"] == "running", res
assert len(FakeSub.calls) == 1, FakeSub.calls
cmd, kw = FakeSub.calls[0]
assert kw.get("start_new_session") is True, kw
assert kw.get("stdin") == FakeSub.DEVNULL, kw
assert kw.get("stdout") == FakeSub.DEVNULL and kw.get("stderr") == FakeSub.DEVNULL, kw
assert cmd[0] == "python3" and cmd[1].endswith("/bin/deployit-posttest"), cmd
assert "--build-id" in cmd and cmd[cmd.index("--build-id") + 1] == "bid1", cmd
assert cmd[cmd.index("--script") + 1] == str(script), cmd
assert cmd[cmd.index("--project-dir") + 1] == str(proj), cmd
assert cmd[cmd.index("--install-url") + 1] == INSTALL, cmd
marker = json.loads(status_path("bid1").read_text())
assert marker["status"] == "running" and marker["pid"] == 4242, marker

# 2) DEPLOYIT_SKIP_POSTTEST -> no spawn
FakeSub.calls.clear()
os.environ["DEPLOYIT_SKIP_POSTTEST"] = "1"
res = mod._spawn_post_deploy_test(state, plugin_root, proj, "bid2", INSTALL)
assert res["status"] == "skipped", res
assert FakeSub.calls == [], "skip env must not spawn"
del os.environ["DEPLOYIT_SKIP_POSTTEST"]

# 3) absent script -> no spawn, loud not_configured marker
FakeSub.calls.clear()
noproj = root / "bare"; noproj.mkdir()
res = mod._spawn_post_deploy_test(state, plugin_root, noproj, "bid3", INSTALL)
assert res["status"] == "not_configured", res
assert FakeSub.calls == [], "absent script must not spawn"
assert json.loads(status_path("bid3").read_text())["status"] == "not_configured"

# 4) source guard: the spawn call runs after index append + backend refresh
src = (plugin_root / "bin" / "deployit-cli").read_text()
call = src.index("_spawn_post_deploy_test(state, args.plugin_root, cwd, build_id, install_url)")
assert src.index("_append_to_index(state, entry") < call, "spawn must follow index append"
assert src.index('_refresh_local_backend(cfg["server"]["port"])') < call, "spawn must follow refresh"

print("ok")
PY

echo "PASS"
