#!/usr/bin/env bats
# Tests for forge-step-exit.sh

SCRIPT="$BATS_TEST_DIRNAME/forge-step-exit.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  touch "$TEST_DIR/.gitkeep"
  # Match real .forge/ layout: state.json/lock.json/verdicts.jsonl are
  # gitignored runtime files (never version-controlled) — without this, a
  # test that writes state.json would see it swept into the commit by `git
  # add .forge/`, which isn't how a real target project is set up.
  printf '.forge/state.json\n.forge/lock.json\n.forge/verdicts.jsonl\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitkeep .gitignore
  git -C "$TEST_DIR" commit -q -m "init"

  mkdir -p "$TEST_DIR/.forge/handoffs"
  echo "test artifact" > "$TEST_DIR/.forge/handoffs/handoff-research.md"

  # Unset TMUX to test freshen-unavailable path
  unset TMUX
  unset TMUX_PANE
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- Argument parsing ---

@test "step-exit: fails without required arguments" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails without --step" {
  run bash "$SCRIPT" --summary "test" --next "/forge continue"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails without --summary" {
  run bash "$SCRIPT" --step research --next "/forge continue"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails without --next or --terminal" {
  run bash "$SCRIPT" --step research --summary "test"
  [ "$status" -ne 0 ]
}

@test "step-exit: fails when both --next and --terminal are given" {
  run bash "$SCRIPT" --step deploy --summary "test" --next "/forge continue" --terminal
  [ "$status" -ne 0 ]
}

# --- Git commit ---

@test "step-exit: output is valid JSON" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "completed research" --next "/forge design --orchestrated"
  echo "$output" >&2
  echo "$output" | jq . >/dev/null
}

@test "step-exit: commits .forge/ files" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "completed research" --next "/forge design --orchestrated"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
  # Verify commit exists with the right message
  local msg
  msg="$(git -C "$TEST_DIR" log -1 --format=%s)"
  [ "$msg" = "forge(research): completed research" ]
}

@test "step-exit: committed field is true" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local committed
  committed="$(echo "$output" | jq -r '.committed')"
  [ "$committed" = "true" ]
}

@test "step-exit: commit_hash is a short hash" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local hash
  hash="$(echo "$output" | jq -r '.commit_hash')"
  [[ "$hash" =~ ^[0-9a-f]{7,}$ ]]
}

# --- Freshen fallback (no tmux) ---

@test "step-exit: freshen_queued is false without tmux" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local queued
  queued="$(echo "$output" | jq -r '.freshen_queued')"
  [ "$queued" = "false" ]
}

@test "step-exit: fallback_message contains next command without tmux" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  local msg
  msg="$(echo "$output" | jq -r '.fallback_message')"
  [[ "$msg" == *"/forge design --orchestrated"* ]]
  [[ "$msg" == *"/clear"* ]]
}

# --- Commit message format ---

@test "step-exit: commit message uses forge(step) prefix" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step design --summary "architecture decided" --next "/forge plan --orchestrated"
  local msg
  msg="$(git -C "$TEST_DIR" log -1 --format=%s)"
  [ "$msg" = "forge(design): architecture decided" ]
}

# --- F053: no-op commit must not abort the exit protocol ---

@test "step-exit F053: a second call with nothing new to commit still succeeds" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "first" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  local hash_before
  hash_before="$(echo "$output" | jq -r '.commit_hash')"

  # Nothing changed under .forge/ since the first call — this must NOT abort.
  run bash "$SCRIPT" --step research --summary "second" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  local ok committed hash_after
  ok="$(echo "$output" | jq -r '.ok')"
  committed="$(echo "$output" | jq -r '.committed')"
  hash_after="$(echo "$output" | jq -r '.commit_hash')"
  [ "$ok" = "true" ]
  [ "$committed" = "false" ]
  [ "$hash_after" = "$hash_before" ]
}

@test "step-exit F053: a no-op commit still queues freshen / reports fallback" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "first" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" --step research --summary "second" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  local msg
  msg="$(echo "$output" | jq -r '.fallback_message')"
  [[ "$msg" == *"/forge design --orchestrated"* ]]
}

@test "step-exit F053: a no-op commit still sets state.json to paused" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/.forge"
  echo '{"status":"running"}' > "$TEST_DIR/.forge/state.json"

  run bash "$SCRIPT" --step research --summary "first" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --step research --summary "second, nothing new" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  local committed status_field
  committed="$(echo "$output" | jq -r '.committed')"
  status_field="$(jq -r '.status' "$TEST_DIR/.forge/state.json")"
  [ "$committed" = "false" ]
  [ "$status_field" = "paused" ]
}

# --- state.json resume.handoff_file (F039 — mechanical field) ---

@test "step-exit: resume.handoff_file follows the handoffs/handoff-<step>.md convention" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/.forge"
  echo '{"status":"running"}' > "$TEST_DIR/.forge/state.json"
  run bash "$SCRIPT" --step design --summary "done" --next "/forge plan --orchestrated"
  [ "$status" -eq 0 ]
  local hf
  hf="$(jq -r '.resume.handoff_file' "$TEST_DIR/.forge/state.json")"
  [ "$hf" = "handoffs/handoff-design.md" ]
}

# --- --extra-path ---

# Fixture paths here are deliberately ORDINARY repo paths (`docs/`,
# `tests/new_test.sh`). They used to be `.storyhook/`, which was never a real
# thing under storyhook 1.0.0+ — story state lives in a store outside the
# repository — so the suite was asserting the mechanism against a path no
# project has (AGE-11). `--extra-path` itself is generic; a directory form with
# a trailing slash and a single-file form are the two pathspec shapes worth
# covering, and neither has anything to do with storyhook.

@test "step-exit: --extra-path stages and commits an additional path" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/docs"
  echo "generated doc" > "$TEST_DIR/docs/overview.md"
  run bash "$SCRIPT" --step decompose --summary "stories created" --next "/forge execute --orchestrated" --extra-path docs/
  [ "$status" -eq 0 ]
  local tracked
  tracked="$(git -C "$TEST_DIR" show --stat -1 --format="" | tr -s ' ' | grep -c 'docs/overview.md' || true)"
  [ "$tracked" -ge 1 ]
}

# Effect oracle, not just a status reading (AGE-18): a missing --extra-path must
# be SKIPPED, not merely survived. `[ -e "$p" ] && git add "$p"` is the last
# command in the staging loop, so under `set -euo pipefail` its false branch is
# exempt from ERR only because it sits left of the `&&`. Asserting exit 0 alone
# would still pass if the script died right after the loop. These assertions
# prove the code AFTER the loop ran: the commit happened, state.json was patched
# to paused, and the freshen fallback was reached.
@test "step-exit: --extra-path silently skips a path that doesn't exist" {
  cd "$TEST_DIR"
  echo '{"status":"running"}' > "$TEST_DIR/.forge/state.json"
  run bash "$SCRIPT" --step decompose --summary "no such path" --next "/forge execute --orchestrated" --extra-path does/not/exist/
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.ok')" = "true" ]
  [ "$(echo "$output" | jq -r '.committed')" = "true" ]

  local files
  files="$(git -C "$TEST_DIR" show --stat -1 --format="")"
  [[ "$files" == *".forge/handoffs/handoff-research.md"* ]]
  [[ "$files" != *"does/not/exist"* ]]

  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
  [ "$(echo "$output" | jq -r '.fallback_message')" != "null" ]
}

@test "step-exit: --extra-path can be repeated" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/docs" "$TEST_DIR/tests"
  echo "generated doc" > "$TEST_DIR/docs/overview.md"
  echo "test content" > "$TEST_DIR/tests/new_test.sh"
  run bash "$SCRIPT" --step validate --summary "hardened tests" --next "/forge continue" \
    --extra-path docs/ --extra-path tests/new_test.sh
  [ "$status" -eq 0 ]
  local files
  files="$(git -C "$TEST_DIR" show --stat -1 --format="")"
  [[ "$files" == *"docs/overview.md"* ]]
  [[ "$files" == *"tests/new_test.sh"* ]]
}

# The mixed case the suite never had: every prior repeat test passed two paths
# that BOTH existed, so nothing proved a missing path leaves its siblings alone.
# Both orders matter and fail differently — a missing path LAST is the one whose
# false `[ -e ]` decides the loop's own exit status.

@test "step-exit: a missing --extra-path does not suppress a present one before it" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/tests"
  echo "test content" > "$TEST_DIR/tests/new_test.sh"
  echo '{"status":"running"}' > "$TEST_DIR/.forge/state.json"
  run bash "$SCRIPT" --step validate --summary "present then missing" --next "/forge continue" \
    --extra-path tests/new_test.sh --extra-path does/not/exist/
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.committed')" = "true" ]
  local files
  files="$(git -C "$TEST_DIR" show --stat -1 --format="")"
  [[ "$files" == *"tests/new_test.sh"* ]]
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
}

@test "step-exit: a missing --extra-path does not suppress a present one after it" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/tests"
  echo "test content" > "$TEST_DIR/tests/new_test.sh"
  echo '{"status":"running"}' > "$TEST_DIR/.forge/state.json"
  run bash "$SCRIPT" --step validate --summary "missing then present" --next "/forge continue" \
    --extra-path does/not/exist/ --extra-path tests/new_test.sh
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.committed')" = "true" ]
  local files
  files="$(git -C "$TEST_DIR" show --stat -1 --format="")"
  [[ "$files" == *"tests/new_test.sh"* ]]
  [ "$(jq -r '.status' "$TEST_DIR/.forge/state.json")" = "paused" ]
}

# --- --terminal (deploy: cancel instead of queue) ---

@test "step-exit: --terminal commits but does not queue freshen" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step deploy --summary "pipeline complete" --terminal
  [ "$status" -eq 0 ]
  local ok queued
  ok="$(echo "$output" | jq -r '.ok')"
  queued="$(echo "$output" | jq -r '.freshen_queued')"
  [ "$ok" = "true" ]
  [ "$queued" = "false" ]
  local msg
  msg="$(git -C "$TEST_DIR" log -1 --format=%s)"
  [ "$msg" = "forge(deploy): pipeline complete" ]
}

@test "step-exit: --terminal reports fallback_message as null" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step deploy --summary "pipeline complete" --terminal
  [ "$status" -eq 0 ]
  local msg
  msg="$(echo "$output" | jq -r '.fallback_message')"
  [ "$msg" = "null" ]
}

@test "step-exit: --terminal does not touch state.json status" {
  cd "$TEST_DIR"
  mkdir -p "$TEST_DIR/.forge"
  echo '{"status":"running","sessions_completed":3}' > "$TEST_DIR/.forge/state.json"
  run bash "$SCRIPT" --step deploy --summary "pipeline complete" --terminal
  [ "$status" -eq 0 ]
  local status_field sessions
  status_field="$(jq -r '.status' "$TEST_DIR/.forge/state.json")"
  sessions="$(jq -r '.sessions_completed' "$TEST_DIR/.forge/state.json")"
  [ "$status_field" = "running" ]
  [ "$sessions" = "3" ]
}

# --- Output must stay valid JSON when freshen actually succeeds (tmux available) ---
#
# freshen.sh's `queue`/`cancel` subcommands print their own human-readable
# confirmation line to stdout on success ("freshen: queued '...'"). Setting
# TMUX/TMUX_PANE is enough to pass freshen.sh's own require_tmux check (it
# only verifies the env vars are set, not that a live session is attached),
# so this genuinely exercises the success path — not just the no-tmux
# fallback every other test in this file uses.

@test "step-exit: output stays valid JSON when tmux env vars are present (freshen queue succeeds)" {
  cd "$TEST_DIR"
  TMUX="dummy,0,0" TMUX_PANE="%0" run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  local queued
  queued="$(echo "$output" | jq -r '.freshen_queued')"
  [ "$queued" = "true" ]
}

@test "step-exit: output stays valid JSON when tmux env vars are present (--terminal cancel succeeds)" {
  cd "$TEST_DIR"
  TMUX="dummy,0,0" TMUX_PANE="%0" run bash "$SCRIPT" --step deploy --summary "pipeline complete" --terminal
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
}

# --- F047: transition audit log ---
#
# forge-step-exit.sh shares freshen's own .freshen/transitions.log so a
# stalled pipeline's timeline reads as one story across both plugins.

@test "F047: a --next step-exit logs a queue transition" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/transitions.log" ]
  run grep -c "step 'research' -> queued next '/forge design --orchestrated'" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "F047: a --terminal step-exit logs a cancel transition" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step deploy --summary "pipeline complete" --terminal
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/transitions.log" ]
  run grep -c "step 'deploy' terminal -- freshen signal cancelled" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "F047: the logged queued=/cancelled= flag reflects whether tmux was actually available" {
  cd "$TEST_DIR"
  # No TMUX env in this test's environment (unset in setup()) -- freshen
  # queue fails, so the logged line must say queued=false, not a blind
  # "we called queue" record.
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  run grep -c "queued=false" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "F047: logging is best-effort and never fails the step-exit when freshen's lib is missing" {
  cd "$TEST_DIR"
  # Point SCRIPT_DIR's sibling resolution at a copy of forge's bin/ with no
  # freshen plugin next to it, simulating a partial/incomplete install.
  local isolated
  isolated="$(mktemp -d)"
  mkdir -p "$isolated/forge-only/bin"
  cp "$SCRIPT" "$isolated/forge-only/bin/forge-step-exit.sh"
  cp "$BATS_TEST_DIRNAME/forge-host.sh" "$isolated/forge-only/bin/forge-host.sh"
  run bash "$isolated/forge-only/bin/forge-step-exit.sh" --step research --summary "done" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  rm -rf "$isolated"
}

# --- --transition-id (agentics#33) ---
#
# Correlates this step-exit's "actual" log line with the "predicted" line
# forge-state.sh --record-transition wrote when the router read its JSON
# output earlier this same turn, so forge-transition-report.sh can pair them
# by transition_id instead of positional adjacency in the log (which a
# crashed/interleaved session would silently corrupt).

@test "--transition-id is optional -- omitting it still succeeds exactly as before" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
}

@test "--transition-id: logs an actual line with the given id when provided" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated" --transition-id "12345-6789"
  [ "$status" -eq 0 ]
  run grep -c "actual step=research transition_id=12345-6789" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "--transition-id: omitted logs transition_id=none instead of failing" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step research --summary "done" --next "/forge design --orchestrated"
  [ "$status" -eq 0 ]
  run grep -c "actual step=research transition_id=none" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "--transition-id: logs the actual line on --terminal exits too" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --step deploy --summary "pipeline complete" --terminal --transition-id "42-1"
  [ "$status" -eq 0 ]
  run grep -c "actual step=deploy transition_id=42-1" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "--transition-id: logging failure (missing freshen lib) never fails the step-exit" {
  cd "$TEST_DIR"
  local isolated
  isolated="$(mktemp -d)"
  mkdir -p "$isolated/forge-only/bin"
  cp "$SCRIPT" "$isolated/forge-only/bin/forge-step-exit.sh"
  cp "$BATS_TEST_DIRNAME/forge-host.sh" "$isolated/forge-only/bin/forge-host.sh"
  run bash "$isolated/forge-only/bin/forge-step-exit.sh" --step research --summary "done" --next "/forge design --orchestrated" --transition-id "1-1"
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  rm -rf "$isolated"
}
