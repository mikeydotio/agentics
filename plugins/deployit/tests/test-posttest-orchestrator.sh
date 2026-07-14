#!/usr/bin/env bash
# bin/deployit-posttest orchestrator (issue #90), run SYNCHRONOUSLY: exit 0 ->
# passed, non-zero -> failed, un-launchable script -> error; the suite's output
# is captured to the per-build log; and status/log land OUTSIDE serve/<id>/ (so a
# late write can never resurrect a build gc/rm deleted).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
HELPER="$PLUGIN_ROOT/bin/deployit-posttest"

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

python3 - "$HELPER" "$ROOT" <<'PY'
import json, os, pathlib, subprocess, sys

helper = sys.argv[1]; root = pathlib.Path(sys.argv[2])
state = root / "state"; proj = root / "proj" / ".deployit"
proj.mkdir(parents=True); (state / "posttest").mkdir(parents=True); (state / "logs").mkdir(parents=True)


def run(bid, body):
    script = root / "proj" / ".deployit" / "post-deploy-test.sh"
    if body is not None:
        script.write_text(body)
    status = state / "posttest" / f"{bid}.json"
    log = state / "logs" / f"posttest-{bid}.log"
    subprocess.run(
        ["python3", helper, "--script", str(script), "--project-dir", str(root / "proj"),
         "--build-id", bid, "--status-file", str(status), "--log-file", str(log),
         "--state-dir", str(state), "--install-url", f"http://x/{bid}/"],
        check=True,
    )
    return json.loads(status.read_text()), log

# 1) passing suite -> passed
st, log = run("pass", "#!/usr/bin/env bash\necho hello-$DEPLOYIT_BUILD_ID\nexit 0\n")
assert st["status"] == "passed" and st["exit_code"] == 0, st
assert "hello-pass" in log.read_text(), log.read_text()

# 2) failing suite -> failed, exit code preserved
st, _ = run("fail", "#!/usr/bin/env bash\necho boom\nexit 7\n")
assert st["status"] == "failed" and st["exit_code"] == 7, st

# 3) missing script -> error (not failed), never crashes
missing = state / "posttest" / "err.json"
subprocess.run(
    ["python3", helper, "--script", str(root / "nope.sh"), "--project-dir", str(root / "proj"),
     "--build-id", "err", "--status-file", str(missing),
     "--log-file", str(state / "logs" / "posttest-err.log"), "--state-dir", str(state)],
    check=True,
)
st = json.loads(missing.read_text())
assert st["status"] == "error" and st["exit_code"] is None, st

# 4) status/log live OUTSIDE serve/<id>/ — the orchestrator never touches serve/,
# so a late write can't resurrect a build that gc/rm deleted.
(state / "serve").mkdir()
run("outside", "#!/usr/bin/env bash\nexit 0\n")
assert (state / "posttest" / "outside.json").is_file(), "status must be under posttest/"
assert (state / "logs" / "posttest-outside.log").is_file(), "log must be under logs/"
assert not (state / "serve" / "outside").exists(), "orchestrator must not create serve/<id>/"

print("ok")
PY

echo "PASS"
