#!/usr/bin/env bats
# Tests for forge's session-stop.sh Stop hook, focused on the cross-plugin
# hook-ordering fix: Claude Code does not guarantee whether forge's
# session-stop.sh or freshen's on-stop.sh runs first within the same Stop
# event, and the two used to depend on that order (forge writes a signal
# file that freshen's hook reads and acts on). See references/auto-resume.md
# ("Cross-Plugin Hook Ordering") for the full writeup.
#
# tmux itself is shimmed (a fake executable on PATH that logs invocations) —
# this is not mocking forge's own behavior, only standing in for a real tmux
# pane so these tests don't require an actual tmux session. Everything else
# (state.json, lock.json, the freshen signal protocol) is the real thing.

FORGE_HOOK="$BATS_TEST_DIRNAME/session-stop.sh"
FRESHEN_HOOK="$BATS_TEST_DIRNAME/../../freshen/hooks/on-stop.sh"
FORGE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
FRESHEN_PLUGIN_ROOT="$BATS_TEST_DIRNAME/../../freshen"

# macOS assesses a *freshly written* executable on its first exec (XProtect /
# syspolicyd). Measured on an M1 Max: 12-43s for a new shim script's first exec
# when XprotectService is saturated, ~0.05s for every exec after that. So any
# assertion timing a region that contains a shim's *first* exec is measuring
# that assessment, not the code under test -- which is what made the F051 bound
# below look non-deterministic (AGE-16), with the hook itself measured at a flat
# 5.0s throughout.
#
# Two things follow, and both are load-bearing:
#
# 1. Shims are built ONCE PER FILE, at a stable path, with every per-test value
#    (log path, behaviour mode) read from the environment at RUN time. Writing
#    them per test -- into a fresh `mktemp -d` -- meant a fresh assessment per
#    test, which cost ~107s per suite run.
# 2. Each shim is warmed here, outside every timed region, so the assessment is
#    paid before any measurement starts. Every shim must honour SHIM_WARMUP=1 by
#    exiting immediately, BEFORE any side effect -- otherwise the warm-up would
#    append to $TMUX_LOG (six assertions require it to stay empty) or sit
#    through the shim's own sleep.
#
# This removes only fixture-construction cost: production `story`/`tmux` are
# installed, already-assessed binaries, so the confound has no production
# analogue. It does not weaken any assertion -- a warmed run still goes red
# against a genuinely unbounded call (~30s) while a correct one lands at ~5s.
#
# Relocating the shims out of $TMPDIR does NOT help: /private/tmp measured
# 25-41s, worse than $TMPDIR. The cause is first-exec assessment, not Spotlight
# indexing, so this repo's .metadata_never_index guidance does not apply here.
setup_file() {
  export SHIM_DIR="$BATS_FILE_TMPDIR/shim"
  export STORY_SHIM_DIR="$BATS_FILE_TMPDIR/story-shim"
  mkdir -p "$SHIM_DIR" "$STORY_SHIM_DIR"

  # tmux shim: log every invocation instead of driving a real pane.
  cat > "$SHIM_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
[ -n "${SHIM_WARMUP:-}" ] && exit 0
echo "$@" >> "$TMUX_LOG"
exit 0
EOF

  # story shim: behaviour picked at run time so the file content never changes.
  # Only tests that put $STORY_SHIM_DIR on PATH see it at all.
  cat > "$STORY_SHIM_DIR/story" <<'EOF'
#!/usr/bin/env bash
[ -n "${SHIM_WARMUP:-}" ] && exit 0
touch "$TEST_DIR/story-started"
case "${STORY_SHIM_MODE:-hang}" in
  hang)
    sleep 30
    touch "$TEST_DIR/story-completed"
    echo "should never print -- killed by the timeout wrapper first"
    ;;
  grandchild)
    python3 "$STORY_SHIM_DIR/spawn-grandchild.py" "$TEST_DIR/gc.pid"
    ;;
esac
exit 0
EOF

  cat > "$STORY_SHIM_DIR/spawn-grandchild.py" <<'EOF'
"""Fork a session-leader grandchild that holds its inherited stdout open.

Mirrors the shape storyhook's own SH-94 hit in production: an auto-spawned
`story ... daemon --serve` that escapes the process group `timeout` signals and
keeps the caller's pipe open. `setsid(1)` does not exist on macOS, so the escape
is done here via os.setsid() after a fork.
"""
import os
import sys
import time

pid_path = sys.argv[1]

if os.fork() == 0:
    os.setsid()                     # leave the process group timeout(1) signals
    with open(pid_path, "w") as fh:
        fh.write(str(os.getpid()))
    time.sleep(30)                  # hold the inherited stdout open
    os._exit(0)

# Parent: do not exit until the grandchild has recorded its pid, so the test
# never races the fork. Bounded, so a child that dies cannot spin us forever.
deadline = time.monotonic() + 5
while not os.path.exists(pid_path) and time.monotonic() < deadline:
    time.sleep(0.01)
EOF

  chmod +x "$SHIM_DIR/tmux" "$STORY_SHIM_DIR/story"
  warm_shim "$SHIM_DIR/tmux"
  warm_shim "$STORY_SHIM_DIR/story"
}

warm_shim() {
  SHIM_WARMUP=1 "$1" >/dev/null 2>&1 || true
}

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  mkdir -p "$TEST_DIR/.forge" "$TEST_DIR/.freshen"

  cat > "$TEST_DIR/.forge/state.json" <<'EOF'
{"status": "running", "sessions_completed": 0, "stories_attempted": 2, "stories_this_session": 1}
EOF
  cat > "$TEST_DIR/.forge/lock.json" <<EOF
{"holder": "test-session", "acquired_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

  TMUX_LOG="$TEST_DIR/tmux.log"
  export TMUX_LOG
  touch "$TMUX_LOG"
  export PATH="$SHIM_DIR:$PATH"
}

# Put the story shim on PATH for this test and select its behaviour. Kept out
# of setup() so the tests that don't ask for it keep resolving `story` exactly
# as they did before.
use_story_shim() {
  export STORY_SHIM_MODE="$1"
  export PATH="$STORY_SHIM_DIR:$PATH"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]]; then
    local guard_file
    guard_file="$(guard_file_for "$TEST_DIR")"
    rm -f "$guard_file" "${guard_file}.tmp"
  fi
  # Reap any session-leader grandchild a shim deliberately left running, so it
  # cannot outlive the suite holding descriptors open.
  if [[ -n "${TEST_DIR:-}" && -f "$TEST_DIR/gc.pid" ]]; then
    kill "$(cat "$TEST_DIR/gc.pid")" 2>/dev/null || true
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

run_forge_stop() {
  CLAUDE_PROJECT_DIR="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$FORGE_PLUGIN_ROOT" \
    TMUX=1 TMUX_PANE="%1" \
    bash "$FORGE_HOOK" < /dev/null
}

# Same as run_forge_stop, but with the hook's own stdout/stderr pointed at
# FILES instead of bats' capture pipe. Mandatory for any test whose shim may
# leave a process alive after the hook returns: such a process inherits the
# hook's stdout, and if that is bats' pipe then bats itself blocks waiting for
# EOF -- on exactly the pipe semantics under test. The test would then hang (or
# time out) whether or not the hook is correct, making the oracle unevaluable.
run_forge_stop_isolated() {
  CLAUDE_PROJECT_DIR="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$FORGE_PLUGIN_ROOT" \
    TMUX=1 TMUX_PANE="%1" \
    bash "$FORGE_HOOK" < /dev/null > "$TEST_DIR/hook.out" 2> "$TEST_DIR/hook.err"
}

run_freshen_stop() {
  ( cd "$TEST_DIR" && \
    CLAUDE_PLUGIN_ROOT="$FRESHEN_PLUGIN_ROOT" TMUX=1 TMUX_PANE="%1" \
    bash "$FRESHEN_HOOK" )
}

send_count() {
  grep -c "send-keys" "$TMUX_LOG" || true
}

# Mirrors stop-guard.sh's own _stop_guard_file() key derivation exactly, so
# tests can pre-seed / clean up the real on-disk guard file for a given
# project dir without sourcing the lib (which would pollute the test's own
# shell with its functions/vars).
guard_file_for() {
  local project="$1" hash
  hash=$(printf '%s' "$project" | md5sum 2>/dev/null | cut -c1-8)
  [ -z "$hash" ] && hash=$(printf '%s' "$project" | md5 2>/dev/null | cut -c1-8)
  echo "/tmp/claude-stop-guard-${USER:-uid$(id -u)}-${hash}"
}

@test "freshen's Stop hook alone sends nothing before forge has written a signal" {
  # This is the exact ordering that used to silently strand auto-resume:
  # freshen's Stop hook running before forge's finds no signal yet and exits
  # without ever sending /clear.
  run_freshen_stop
  [ ! -s "$TMUX_LOG" ]
}

@test "forge's Stop hook sends /clear itself, regardless of whether freshen's hook already ran and found nothing" {
  run_freshen_stop
  run_forge_stop
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
  [ -f "$TEST_DIR/.freshen/.clear-pending" ]
  [ "$(send_count)" = "1" ]
}

@test "freshen's Stop hook does not double-send /clear if forge already sent it this batch" {
  run_forge_stop
  [ "$(send_count)" = "1" ]
  run_freshen_stop
  # Still exactly one /clear -- freshen's hook must see .clear-pending
  # (set by forge) and skip sending a second one.
  [ "$(send_count)" = "1" ]
}

@test "the forge signal file survives both hooks so on-clear.sh can still consume it" {
  run_forge_stop
  run_freshen_stop
  [ -f "$TEST_DIR/.freshen/forge.signal" ]
}

@test "forge's Stop hook sends nothing when status is not running" {
  echo '{"status": "paused"}' > "$TEST_DIR/.forge/state.json"
  run_forge_stop
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -s "$TMUX_LOG" ]
}

@test "forge's Stop hook skips the signal and /clear entirely without tmux" {
  # Explicitly unset TMUX/TMUX_PANE -- the test harness itself may be running
  # inside a real tmux session, whose env vars would otherwise leak through.
  env -u TMUX -u TMUX_PANE CLAUDE_PROJECT_DIR="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$FORGE_PLUGIN_ROOT" \
    bash "$FORGE_HOOK" < /dev/null
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  [ ! -s "$TMUX_LOG" ]
}

# --- F050: a tripped circuit breaker must not leak the lock / skip the checkpoint ---

@test "a tripped circuit breaker still lets the durable checkpoint run, but suppresses the auto-resume signal" {
  local guard_file now
  guard_file="$(guard_file_for "$TEST_DIR")"
  mkdir -p "$(dirname "$guard_file")"
  now=$(date +%s)
  # Four distinct ticks (>2s apart so stop_guard_check's own same-event
  # dedup window doesn't collapse them), all inside the 30s trip window --
  # this alone reaches the default threshold (4), so the very next
  # stop_guard_check call (made by session-stop.sh itself below) trips.
  {
    echo $((now - 20))
    echo $((now - 15))
    echo $((now - 10))
    echo $((now - 5))
  } > "$guard_file"

  run_forge_stop

  # The durable checkpoint must have completed despite the trip (F050).
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
  [ ! -f "$TEST_DIR/.forge/lock.json" ]
  [ -f "$TEST_DIR/.forge/handoffs/handoff-execute.md" ]
  # ...but the breaker trip must still suppress the one thing it exists to
  # gate: queuing the freshen auto-resume signal / sending /clear.
  [ ! -f "$TEST_DIR/.freshen/forge.signal" ]
  # StoryHook may use tmux for its own activity windows; no terminal send is allowed.
  ! grep -q '^send-keys ' "$TMUX_LOG"
}

# --- F055: portable duration computation (no GNU-only `date -d`) ---

@test "session-stop computes a real duration via jq's fromdate, not GNU date -d" {
  run_forge_stop
  run grep -oE '\*\*Duration\*\*: [0-9]+s' "$TEST_DIR/.forge/handoffs/handoff-execute.md"
  [ "$status" -eq 0 ]
}

@test "an unparseable lock timestamp degrades to Duration: unknown instead of crashing" {
  cat > "$TEST_DIR/.forge/lock.json" <<'EOF'
{"holder": "test-session", "acquired_at": "not-a-real-timestamp"}
EOF
  run_forge_stop
  run grep -F '**Duration**: unknown' "$TEST_DIR/.forge/handoffs/handoff-execute.md"
  [ "$status" -eq 0 ]
}

# --- F051: bounded story handoff (timeout), reordered after the checkpoint ---

@test "a hanging story handoff is bounded by a timeout and never blocks the checkpoint" {
  use_story_shim hang

  local start end elapsed
  start=$(date +%s)
  run_forge_stop_isolated
  end=$(date +%s)
  elapsed=$((end - start))

  # Primary oracle is an EFFECT, not a clock reading: the shim reaches its
  # completion marker only after a full 30s sleep, so the marker's absence
  # (paired with the start marker's presence, proving the call was actually
  # made) is direct evidence the timeout fired. A wall-clock reading alone
  # cannot distinguish "the bound held" from "the machine was fast".
  [ -f "$TEST_DIR/story-started" ]
  [ ! -f "$TEST_DIR/story-completed" ]
  # The checkpoint must have completed regardless of the hang.
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
  [ ! -f "$TEST_DIR/.forge/lock.json" ]
  # Loose backstop only -- deliberately left generous against the hook's 15s
  # budget (internal timeout is 5s). Do not tighten: with the effect oracle
  # above carrying the signal, a narrower margin buys no detection and only
  # re-imports load sensitivity.
  [ "$elapsed" -lt 12 ]
}

@test "a story handoff that leaves a surviving grandchild does not hold the hook open" {
  # The timeout alone cannot bound this. `timeout` signals the process group it
  # created; a descendant that calls setsid() has left that group, survives, and
  # keeps the stdout it inherited open. A command substitution does not return
  # until every writer closes that pipe, so the hook blocks for the survivor's
  # full lifetime no matter what the timeout does.
  #
  # This is not a synthetic worry: storyhook's own SH-94 records a test binary
  # blocked in read(2) for four minutes on a pipe whose write end an
  # auto-spawned `story ... daemon --serve` held at fd 7 -- and `story handoff`
  # is exactly a command that can auto-spawn that daemon.
  command -v python3 >/dev/null || skip "python3 required to fork a session-leader grandchild"
  use_story_shim grandchild

  local start end elapsed gc_pid
  start=$(date +%s)
  run_forge_stop_isolated
  end=$(date +%s)
  elapsed=$((end - start))

  # Ordering oracle: the grandchild must still be ALIVE at the moment the hook
  # returned. This fails for the defect -- a hook that waited out the survivor
  # returns only after it has exited -- and it cannot fail merely because the
  # machine is slow, since load delays the hook's return without resurrecting
  # or killing the grandchild.
  [ -f "$TEST_DIR/gc.pid" ]
  gc_pid="$(cat "$TEST_DIR/gc.pid")"
  run kill -0 "$gc_pid"
  [ "$status" -eq 0 ]

  # ...and the checkpoint still completed.
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
  [ ! -f "$TEST_DIR/.forge/lock.json" ]
  # Loose backstop, same reasoning as above.
  [ "$elapsed" -lt 12 ]
}
