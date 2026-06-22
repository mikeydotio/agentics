#!/usr/bin/env bash
# Release wiring in deployit-cli: _stage_macos(release=True) stages <App>.zip and
# records release_zip in _meta.json; _publish_github_release shells to
# deployit-release (fake gh), honours DEPLOYIT_SKIP_RELEASE_PUBLISH, and degrades
# gracefully when no zip was staged. Plus a source guard that the publish runs
# AFTER the index append + backend refresh (so a failed deploy never orphans a
# public release).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

command -v hdiutil >/dev/null && command -v ditto >/dev/null \
    && command -v /usr/libexec/PlistBuddy >/dev/null \
    || { echo "SKIP: macOS tools unavailable"; exit 0; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
export DEPLOYIT_GH_BIN="$TESTS_DIR/fakes/gh"
export DEPLOYIT_SKIP_CODESIGN_VERIFY=1
export FAKE_GH_LOG="$ROOT/gh.log"

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, json, os, pathlib, subprocess, sys

plugin_root = pathlib.Path(sys.argv[1]); root = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

state = root / "state"; (state / "serve").mkdir(parents=True)
BASE = "https://demo.tail.ts.net/deployit"

def make_app():
    app = root / "export" / "Hello.app"
    (app / "Contents" / "MacOS").mkdir(parents=True, exist_ok=True)
    (app / "Contents" / "MacOS" / "Hello").write_text("#!/bin/sh\necho hi\n")
    subprocess.run(["/usr/libexec/PlistBuddy", "-c",
                    "Add :CFBundleShortVersionString string 1.5.0",
                    str(app / "Contents" / "Info.plist")], check=True, capture_output=True)
    return app

meta = dict(id="hello-macos-x", platform="macos", project="Hello",
            bundle_id="io.x.Hello", marketing_version="1.5.0", semver_version=None,
            build_number="7", commit="abc1234", timestamp="2026-05-20T09:00:00-07:00",
            origin_host="demo.tail.ts.net", origin_base_url=BASE)
notes = root / "notes.md"; notes.write_text("- a change\n")
# proj models the app checkout: a git repo with an origin (no semver, so the
# release version is resolved from the zipped app's Info.plist).
proj = root / "proj"; proj.mkdir()
subprocess.run(["git", "-C", str(proj), "init", "-q"], check=True)
subprocess.run(["git", "-C", str(proj), "remote", "add", "origin",
                "https://github.com/me/Hello.git"], check=True)

# 1) staging produces the release zip + meta.release_zip
mod._stage_macos(state, plugin_root, "bid1", make_app(), meta, False, "",
                 {"enabled": False}, release=True)
serve = state / "serve" / "bid1"
assert (serve / "Hello.zip").is_file(), "release zip missing"
assert json.loads((serve / "_meta.json").read_text()).get("release_zip") == "Hello.zip"

# 2) publish shells out to deployit-release via the fake gh
rel = mod._publish_github_release(plugin_root, proj, state, "bid1", notes,
                                  clobber=False, prerelease=False, attach_dmg=False)
assert rel.get("ok"), rel
assert rel.get("release_url", "").endswith("/tag/1.5.0"), rel
log = (root / "gh.log").read_text()
assert "release create 1.5.0" in log, log

# 3) DEPLOYIT_SKIP_RELEASE_PUBLISH short-circuits without calling gh
(root / "gh.log").write_text("")
os.environ["DEPLOYIT_SKIP_RELEASE_PUBLISH"] = "1"
rel = mod._publish_github_release(plugin_root, proj, state, "bid1", notes,
                                  clobber=False, prerelease=False, attach_dmg=False)
assert rel.get("ok") and rel.get("skipped"), rel
assert (root / "gh.log").read_text() == "", "skip env must not call gh"
del os.environ["DEPLOYIT_SKIP_RELEASE_PUBLISH"]

# 4) a non-release build (no release_zip) degrades gracefully
mod._stage_macos(state, plugin_root, "bid2", make_app(), meta, False, "",
                 {"enabled": False}, release=False)
rel = mod._publish_github_release(plugin_root, proj, state, "bid2", notes,
                                  clobber=False, prerelease=False, attach_dmg=False)
assert not rel.get("ok") and "no release zip" in rel.get("display", ""), rel

# 5) source guard: publish call comes AFTER index append + backend refresh
src = (plugin_root / "bin" / "deployit-cli").read_text()
call = src.index("rel = _publish_github_release(")
assert src.index("_append_to_index(state, entry)") < call, "publish must follow index append"
assert src.index('_refresh_local_backend(cfg["server"]["port"])') < call, "publish must follow refresh"

print("ok")
PY

echo "PASS"
