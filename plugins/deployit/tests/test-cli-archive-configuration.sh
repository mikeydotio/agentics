#!/usr/bin/env bash
# AGE-28: deployit must not force a build configuration, and must refuse an
# unacknowledged unoptimized archive.
#
# The defect: _xcodebuild_archive hardcoded `-configuration Debug`, which
# OVERRIDES the scheme's ArchiveAction, so every OTA build ever produced
# shipped unoptimized with `#if DEBUG` code compiled in. Reproduced on the real
# moshtail project with `xcodebuild -showBuildSettings -json … archive`,
# identical commands except the flag:
#
#   without: CONFIGURATION=Release  SWIFT_OPTIMIZATION_LEVEL=-O   (debug keys ABSENT)
#   with:    CONFIGURATION=Debug    SWIFT_OPTIMIZATION_LEVEL=-Onone
#            SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG  GCC_OPTIMIZATION_LEVEL=0
#
# Design ruled by /council-vote (unanimous after one deliberation round) —
# .council/age28-archive-configuration/DECISION.md. Fully hermetic: no
# xcodebuild, no network, no real project.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# --- config.toml fixtures for the [build] table -------------------------------
mkdir -p "$ROOT/none"                       # no .deployit at all
mkdir -p "$ROOT/ack/.deployit"
cat > "$ROOT/ack/.deployit/config.toml" <<'TOML'
[build]
allow_debug = true
TOML
mkdir -p "$ROOT/both/.deployit"
cat > "$ROOT/both/.deployit/config.toml" <<'TOML'
[toolchain]
min_sdk = "27"

[build]
allow_debug = true
TOML
mkdir -p "$ROOT/off/.deployit"
cat > "$ROOT/off/.deployit/config.toml" <<'TOML'
[build]
allow_debug = false
TOML

python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys

plugin_root = pathlib.Path(sys.argv[1]); root = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

META = {"xcode_container_flag": "-project",
        "xcode_container_path": "/w/App.xcodeproj",
        "default_scheme": "App", "platform": "ios"}
ARCH = pathlib.Path("/w/build/app.xcarchive")

# ── GOLDEN FIXTURES — captured verbatim from the real moshtail A/B run. ───────
# The Release entry OMITS the debug keys rather than setting them empty. That
# asymmetry is the whole point: a gate that treats "key absent" as suspicious
# would refuse every healthy Release archive, and `None.split()` would crash on
# the happy path. Both were real defects in a round-1 council proposal.
REAL_RELEASE = {"CONFIGURATION": "Release",
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "ENABLE_TESTABILITY": "NO"}
REAL_DEBUG = {"CONFIGURATION": "Debug",
              "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
              "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
              "GCC_OPTIMIZATION_LEVEL": "0",
              "ENABLE_TESTABILITY": "YES"}
assert "SWIFT_ACTIVE_COMPILATION_CONDITIONS" not in REAL_RELEASE, \
    "fixture integrity: the Release fixture must OMIT the debug keys, as measured"

failures = []
def check(label, cond):
    if not cond:
        failures.append(label)

# ══ M8 — THE REGRESSION TEST. The only assertion that goes RED on the old code.
argv = mod._archive_argv(META, ARCH, None)
check("M8: -configuration must not appear in the archive argv",
      "-configuration" not in argv)
check("M8: Debug must not appear in the archive argv", "Debug" not in argv)
# Effect oracle: prove the command is still a real archive invocation, so the
# deletion cannot be satisfied by returning a stub/empty argv.
for tok in ("xcodebuild", "-project", "/w/App.xcodeproj", "-scheme", "App",
            "-destination", "generic/platform=iOS", "-archivePath",
            "-allowProvisioningUpdates", "archive"):
    check(f"M8: archive argv must still contain {tok!r}", tok in argv)
check("M8: 'archive' must remain the final action", argv[-1] == "archive")
check("M8: explicit --scheme override must win",
      mod._archive_argv(META, ARCH, "iOS Browser")[4] == "iOS Browser")

# ══ M7 — ORACLE/BUILD AGREEMENT. If the settings query and the archive disagree
# on container, scheme or destination, the gate measures a DIFFERENT build than
# it ships: a gate that verifies the wrong thing while reporting green.
s_argv = mod._settings_argv(META, None)
check("M7: settings argv must ask for JSON", "-json" in s_argv)
check("M7: settings argv must query the archive action", s_argv[-1] == "archive")
check("M7: settings argv must use -showBuildSettings", "-showBuildSettings" in s_argv)
for i, tok in ((1, "-project"), (2, "/w/App.xcodeproj")):
    check(f"M7: settings/archive container must agree at {i}", s_argv[i] == argv[i] == tok)
check("M7: settings/archive -scheme must agree",
      s_argv[s_argv.index("-scheme") + 1] == argv[argv.index("-scheme") + 1])
check("M7: settings/archive -destination must agree",
      s_argv[s_argv.index("-destination") + 1] == argv[argv.index("-destination") + 1])
check("M7: settings argv must honour an explicit --scheme (duckduckgo-apple)",
      mod._settings_argv(META, "iOS Browser")[4] == "iOS Browser")
check("M7: the settings query must never build a configuration",
      "-configuration" not in s_argv)

# ══ M9 — CONFIG LOADING. python3 on the target machine is 3.9.6 with NO
# tomllib, so the regex fallback is the ONLY path that ever executes there.
# Test the fallback parser DIRECTLY and unconditionally so the suite can never
# pass vacuously on a 3.11+ machine.
p = mod._parse_project_config_text
check("M9: [build]-only config must survive the fallback parser",
      p('[build]\nallow_debug = true\n').get("build", {}).get("allow_debug") is True)
both = p('[toolchain]\nmin_sdk = "27"\n\n[build]\nallow_debug = true\n')
check("M9: [toolchain] must survive alongside [build]",
      both.get("toolchain", {}).get("min_sdk") == "27")
check("M9: [build] must survive alongside [toolchain] (the :605 regression)",
      both.get("build", {}).get("allow_debug") is True)
check("M9: allow_debug = false must not read as an acknowledgement",
      not p('[build]\nallow_debug = false\n').get("build", {}).get("allow_debug"))
check("M9: an unrelated table must not manufacture a [build] table",
      "build" not in p('[toolchain]\nmin_sdk = "27"\n'))
# The bool trap: every other bool in this parser is a PRESENCE test, not the
# quoted-string capture used for the toolchain keys. A quoted regex copied from
# those lines would silently never match an unquoted TOML bool.
check("M9: allow_debug must not require quotes",
      p('[build]\nallow_debug=true\n').get("build", {}).get("allow_debug") is True)

# End-to-end through whichever parser this interpreter actually has.
check("M9: e2e no config -> {}", mod._read_project_config(root / "none") == {})
check("M9: e2e [build] only",
      mod._read_project_config(root / "ack").get("build", {}).get("allow_debug") is True)
e2e_both = mod._read_project_config(root / "both")
check("M9: e2e both tables survive together",
      e2e_both.get("build", {}).get("allow_debug") is True
      and e2e_both.get("toolchain", {}).get("min_sdk") == "27")
check("M9: e2e allow_debug=false is not an acknowledgement",
      not mod._read_project_config(root / "off").get("build", {}).get("allow_debug"))

# ══ THE BOUNDARY MUTATION TEST — full cross-product as an explicit table.
NO_ACK, ACK = {}, {"build": {"allow_debug": True}}
PLATFORMS = ("ios", "visionos", "macos")
gate = mod._archive_gate

# M4/M5: every healthy Release row proceeds silently and must not raise —
# including do_release=True and including an acknowledged healthy build.
for plat in PLATFORMS:
    for dr in (False, True):
        for cfg, name in ((NO_ACK, "no-ack"), (ACK, "ack")):
            r = gate(REAL_RELEASE, cfg, plat, dr)
            check(f"M4: Release/{name}/{plat}/do_release={dr} must proceed",
                  r["verdict"] == "proceed")
            check(f"M4: Release/{name}/{plat}/do_release={dr} must warn about nothing",
                  r["warnings"] == [])

# M2: UNACKNOWLEDGED unoptimized refuses on EVERY platform, publish or not.
# do_release is False for ios/visionos BY CONSTRUCTION, so these rows go RED
# both if someone adds `and platform == "macos"` and if someone reuses
# do_release as the trigger rather than as a ceiling.
verdicts = set()
for plat in PLATFORMS:
    for dr in (False, True):
        r = gate(REAL_DEBUG, NO_ACK, plat, dr)
        verdicts.add((r["verdict"], r["reason"]))
        check(f"M2: unacknowledged Debug on {plat}/do_release={dr} must refuse",
              r["verdict"] == "refuse")
        check(f"M2: unacknowledged Debug on {plat} must cite the right reason",
              r["reason"] == "unoptimized_unacknowledged")
# INVARIANCE: the unacknowledged verdict must not vary with platform or publish
# at all. A row-by-row table alone would not catch a condition introduced
# somewhere else in that path; this collapses all six into one assertion.
check("M2-INVARIANCE: unacknowledged verdict must be identical across all "
      "(platform, do_release) combinations", len(verdicts) == 1)

# M1: the escape hatch's exact width. Neither row alone pins it — the first
# alone permits ignoring the acknowledgement entirely, the second alone permits
# an early `return proceed`.
pub = gate(REAL_DEBUG, ACK, "macos", True)
check("M1: allow_debug must NOT authorise a publishing deploy",
      pub["verdict"] == "refuse")
check("M1: a publish refusal must be distinguishable from an unacknowledged one",
      pub["reason"] == "unoptimized_publish")
side = gate(REAL_DEBUG, ACK, "macos", False)
check("M1: allow_debug must permit a non-publishing macOS deploy",
      side["verdict"] == "proceed")
for plat in ("ios", "visionos"):
    check(f"M1: allow_debug must permit an acknowledged {plat} sideload",
          gate(REAL_DEBUG, ACK, plat, False)["verdict"] == "proceed")
check("M1: the three reasons must be distinct strings",
      len({"unoptimized_unacknowledged", "unoptimized_publish", "unresolved"}) == 3)

# M3: the fails-open mutation. An acknowledged proceed must NEVER be silent —
# `warnings = []` on this path is precisely the wrong implementation.
for plat in PLATFORMS:
    r = gate(REAL_DEBUG, ACK, plat, False)
    check(f"M3: an acknowledged Debug archive on {plat} must still warn",
          len(r["warnings"]) >= 1)
    check(f"M3: the {plat} warning must name the configuration",
          any("Debug" in w for w in r["warnings"]))

# M6: UNRESOLVED — refused, distinctly, and NOT silenced by allow_debug.
# "I know this is unoptimized and I accept it" is a different claim from
# "deployit could not tell"; one key must not silence both.
for label, settings in (("empty", {}), ("none", None),
                        ("no optimization key", {"CONFIGURATION": "Release"})):
    r = gate(settings, NO_ACK, "ios", False)
    check(f"M6: unresolved ({label}) must refuse", r["verdict"] == "refuse")
    check(f"M6: unresolved ({label}) must be its own reason", r["reason"] == "unresolved")
    r_ack = gate(settings, ACK, "ios", False)
    check(f"M6: allow_debug must NOT silence unresolved ({label})",
          r_ack["verdict"] == "refuse" and r_ack["reason"] == "unresolved")

# The ObjC rung: a target with no Swift key is decided on GCC_OPTIMIZATION_LEVEL
# rather than falling through to unresolved.
check("LADDER: ObjC-only unoptimized decides on the second rung",
      gate({"CONFIGURATION": "Debug", "GCC_OPTIMIZATION_LEVEL": "0"},
           NO_ACK, "ios", False)["reason"] == "unoptimized_unacknowledged")
check("LADDER: ObjC-only optimized proceeds",
      gate({"CONFIGURATION": "Release", "GCC_OPTIMIZATION_LEVEL": "s"},
           NO_ACK, "ios", False)["verdict"] == "proceed")
# Swift wins over GCC when both are present (they are, in a real Debug build).
check("LADDER: the Swift rung outranks the GCC rung",
      gate({"SWIFT_OPTIMIZATION_LEVEL": "-O", "GCC_OPTIMIZATION_LEVEL": "0"},
           NO_ACK, "ios", False)["verdict"] == "proceed")
# Substance over name: a Release-NAMED configuration built -Onone must refuse.
check("SUBSTANCE: a Release-named but unoptimized configuration must refuse",
      gate({"CONFIGURATION": "Release", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"},
           NO_ACK, "ios", False)["verdict"] == "refuse")

# M5 (explicit): the measured None shape must not raise anywhere.
try:
    gate({"SWIFT_OPTIMIZATION_LEVEL": "-Onone",
          "SWIFT_ACTIVE_COMPILATION_CONDITIONS": None}, ACK, "ios", False)
except AttributeError as exc:
    failures.append(f"M5: None conditions must not raise AttributeError ({exc})")

# M10: the persistence payload — the durable record. There is NO post-hoc
# oracle (a real .xcarchive/Info.plist carries no configuration field), so this
# is the only way anyone can ever learn what a shipped build was built with.
rec = gate(REAL_DEBUG, ACK, "macos", False)
check("M10: the verdict must carry the configuration label",
      rec["configuration"] == "Debug")
check("M10: the verdict must carry the OPTIMIZATION LEVEL, not just the name",
      rec["optimization_level"] == "-Onone")
check("M10: the verdict must record unoptimized", rec["unoptimized"] is True)
check("M10: the verdict must record the acknowledgement", rec["allow_debug"] is True)
rel = gate(REAL_RELEASE, NO_ACK, "ios", False)
check("M10: a healthy build records its label too", rel["configuration"] == "Release")
check("M10: a healthy build records -O", rel["optimization_level"] == "-O")
check("M10: a healthy build is not marked unoptimized", rel["unoptimized"] is False)

# M10b: the fields must reach BOTH _meta.json write paths. The iOS writer uses
# an explicit key allowlist, so a field threaded only through meta_full would be
# silently dropped there while flowing freely on macOS — i.e. missing from every
# published Developer-ID release, which is exactly what the record is for.
import inspect
for stage in (mod._stage_ios_or_visionos, mod._stage_macos):
    src = inspect.getsource(stage)
    for field in ("configuration", "configuration_source", "optimization_level"):
        check(f"M10b: {stage.__name__}'s _meta.json allowlist must carry {field!r}",
              field in src)

if failures:
    print(f"FAIL ({len(failures)}):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)

print(f"ok: {len(PLATFORMS) * 2 * 2} release rows + 6 boundary rows + ladder/"
      f"unresolved/persistence units (python "
      f"{sys.version_info.major}.{sys.version_info.minor}, "
      f"{'tomllib' if sys.version_info >= (3, 11) else 'regex-fallback'} e2e path)")
PY

echo "PASS"
