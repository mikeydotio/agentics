#!/usr/bin/env bash
# AGE-110: an optimized Release archive that names NEITHER optimization key
# must proceed, not be refused as "unresolved".
#
# _archive_gate's ladder is SWIFT_OPTIMIZATION_LEVEL -> GCC_OPTIMIZATION_LEVEL
# -> unresolved, and its docstring says in bold that absence of those keys is
# the *healthy* signal, "measured: a real Release archive omits both", and
# "must never itself trigger a refusal". The `else` arm did the opposite.
#
# Measured on SCADPad, whose Release configuration inherits Xcode's optimized
# defaults (SWIFT_COMPILATION_MODE = wholemodule) and therefore reports
# neither key, while its Debug configuration reports -Onone and 0 explicitly.
# Absence is specifically the Release signal, so refusing on it refuses the
# safe build and accepts nothing.
#
# The genuinely unresolved case is different and still refuses: xcodebuild
# gave no answer at all, which _archive_build_settings signals as None.

set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1

python3 - "$PLUGIN_ROOT" <<'PY'
import importlib.util, sys
from pathlib import Path

plugin_root = Path(sys.argv[1])
spec = importlib.util.spec_from_loader(
    "deployit_cli",
    importlib.machinery.SourceFileLoader("deployit_cli", str(plugin_root / "bin" / "deployit-cli")),
)
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)

passed = failed = 0
def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1; print(f"  PASS  {name}")
    else:
        failed += 1; print(f"  FAIL  {name}"); print(f"        {detail}")

# ---- the regression: Release omitting both keys ---------------------------
release = {"CONFIGURATION": "Release", "SWIFT_COMPILATION_MODE": "wholemodule"}
g = cli._archive_gate(release, {}, "ios", False)
check("an answered Release naming no optimization key proceeds",
      g["verdict"] == "proceed", f"got {g['verdict']} / {g['reason']}")
check("...and is not reported as unresolved",
      g["reason"] != cli._GATE_UNRESOLVED, f"reason={g['reason']}")

# It must proceed for a publishing macOS deploy too — absence is healthy, and
# the publish ceiling only applies to an *acknowledged unoptimized* build.
g = cli._archive_gate(release, {}, "macos", True)
check("...including a macOS deploy that publishes a release",
      g["verdict"] == "proceed", f"got {g['verdict']} / {g['reason']}")

# ---- the genuinely unresolved case still refuses --------------------------
for label, settings in (("None", None), ("empty", {})):
    g = cli._archive_gate(settings, {}, "ios", False)
    check(f"xcodebuild giving no answer at all ({label}) still refuses as unresolved",
          g["verdict"] == "refuse" and g["reason"] == cli._GATE_UNRESOLVED,
          f"got {g['verdict']} / {g['reason']}")

# ---- the safety property is intact ---------------------------------------
debug = {"CONFIGURATION": "Debug", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
         "GCC_OPTIMIZATION_LEVEL": "0"}
g = cli._archive_gate(debug, {}, "ios", False)
check("an explicitly -Onone build is still refused unacknowledged",
      g["verdict"] == "refuse" and g["reason"] == cli._GATE_UNACKNOWLEDGED,
      f"got {g['verdict']} / {g['reason']}")

g = cli._archive_gate(debug, {"build": {"allow_debug": True}}, "macos", True)
check("an acknowledged -Onone build still cannot publish a release",
      g["verdict"] == "refuse" and g["reason"] == cli._GATE_PUBLISH,
      f"got {g['verdict']} / {g['reason']}")

g = cli._archive_gate(debug, {"build": {"allow_debug": True}}, "ios", False)
check("an acknowledged -Onone build proceeds with a warning",
      g["verdict"] == "proceed" and g["warnings"], f"got {g}")

# A Release-NAMED configuration that really is -Onone is still caught: the
# gate is substance-based, never name-based.
lying = {"CONFIGURATION": "Release", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
g = cli._archive_gate(lying, {}, "ios", False)
check("a Release-named build compiled -Onone is still refused",
      g["verdict"] == "refuse" and g["reason"] == cli._GATE_UNACKNOWLEDGED,
      f"got {g['verdict']} / {g['reason']}")

# ---- the refusal must not blame xcodebuild for an answer it gave ----------
meta = {"xcode_container_flag": "-workspace",
        "xcode_container_path": "/x/P.xcworkspace",
        "default_scheme": "P", "platform": "ios"}
msg = cli._archive_refusal_message(
    cli._archive_gate(None, {}, "ios", False), meta, None)
check("the unresolved refusal names xcodebuild not answering",
      "xcodebuild" in msg, msg[:200])

print(f"\nResults: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
