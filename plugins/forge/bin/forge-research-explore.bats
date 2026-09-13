#!/usr/bin/env bats
# Tests for forge-research-explore.sh — the deterministic seam the forge
# research step uses to (optionally) run a governed greenlight explorer for a
# codebase-oriented research track. The greenlight launcher is mocked via
# GREENLIGHT_EXPLORE_BIN so these tests never spawn a real `claude -p`.

BIN="$BATS_TEST_DIRNAME/forge-research-explore.sh"

setup() {
  WORK="$(mktemp -d /tmp/fre.XXXXXX)"
  FORGE_DIR="$WORK/.forge"
  mkdir -p "$FORGE_DIR"

  MOCK="$WORK/mock-explore.sh"
  export MOCK_LOG="$WORK/mock.log"
  cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
echo "ARGS=$*" >> "$MOCK_LOG"
out=""; prev=""
for a in "$@"; do [ "$prev" = "--out" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && { mkdir -p "$(dirname "$out")"; printf '# codebase findings\nstub\n' > "$out"; }
jq -n --arg o "$out" '{ok:true, rc:0, findings:$o, kept:false}'
EOF
  chmod +x "$MOCK"
}

teardown() {
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
  return 0
}

set_flag() { printf '{"governed_explorer": %s}\n' "$1" > "$FORGE_DIR/config.json"; }
runfre() { run env GREENLIGHT_EXPLORE_BIN="$MOCK" MOCK_LOG="$MOCK_LOG" bash "$BIN" "$@"; }

@test "no config.json → disabled, launcher not invoked" {
  runfre --topic arch --task "map it" --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.enabled')" = "false" ]
  [ ! -f "$MOCK_LOG" ]
}

@test "governed_explorer:false → disabled, launcher not invoked" {
  set_flag false
  runfre --topic arch --task "x" --forge-dir "$FORGE_DIR"
  [ "$(echo "$output" | jq -r '.enabled')" = "false" ]
  [ ! -f "$MOCK_LOG" ]
}

@test "governed_explorer:true → runs launcher, writes codebase-<topic>.md, folds path" {
  set_flag true
  runfre --topic architecture --task "map the module layout" --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.enabled')" = "true" ]
  [ "$(echo "$output" | jq -r '.ran')" = "true" ]
  local out; out="$(echo "$output" | jq -r '.out')"
  [ "$out" = "$FORGE_DIR/research/codebase-architecture.md" ]
  [ -f "$out" ]
  grep -q "codebase findings" "$out"
  grep -q -- "--task map the module layout" "$MOCK_LOG"
  grep -q -- "--out $FORGE_DIR/research/codebase-architecture.md" "$MOCK_LOG"
}

@test "topic is sanitized into the filename" {
  set_flag true
  runfre --topic "Data Layer!" --task "x" --forge-dir "$FORGE_DIR"
  [ "$(echo "$output" | jq -r '.out')" = "$FORGE_DIR/research/codebase-data-layer.md" ]
}

@test "enabled but launcher missing → ran:false with error (non-fatal, exit 0)" {
  set_flag true
  run env GREENLIGHT_EXPLORE_BIN="/no/such/launcher" bash "$BIN" --topic x --task y --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.enabled')" = "true" ]
  [ "$(echo "$output" | jq -r '.ran')" = "false" ]
  [ "$(echo "$output" | jq -r '.error')" != "null" ]
}

@test "missing --topic is a usage error" {
  set_flag true
  runfre --task "x" --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "missing --task is a usage error" {
  set_flag true
  runfre --topic x --forge-dir "$FORGE_DIR"
  [ "$status" -ne 0 ]
}

@test "missing option values fail promptly with contextual usage errors" {
  run python3 - "$BIN" <<'PYTEST'
import subprocess, sys
for option in ("--topic", "--task", "--forge-dir"):
    result = subprocess.run(["bash", sys.argv[1], option],
                            capture_output=True, text=True, timeout=2)
    assert result.returncode == 2, (option, result.returncode, result.stderr)
    assert option + " requires a value" in result.stderr, result.stderr
PYTEST
  [ "$status" -eq 0 ]
}
