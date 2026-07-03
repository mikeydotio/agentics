#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/forge-state.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  FORGE_DIR="$TEST_DIR/.forge"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: run the script pointing at our test forge dir
run_state() {
  run bash "$SCRIPT" "$FORGE_DIR"
}

# Helper: get a field from JSON output
jq_field() {
  echo "$output" | jq -r "$1"
}

# --- No .forge directory ---

@test "no .forge directory returns state=interrogate" {
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "interrogate" ]
  [ "$(jq_field '.dispatch')" = "interrogate --orchestrated" ]
}

# --- Empty .forge directory ---

@test "empty .forge directory returns state=interrogate" {
  mkdir -p "$FORGE_DIR"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "interrogate" ]
}

# --- IDEA.md only ---

@test "IDEA.md without research/SUMMARY.md returns state=research" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "research" ]
  [ "$(jq_field '.dispatch')" = "research --orchestrated" ]
}

# --- research/SUMMARY.md without DESIGN.md ---

@test "research/SUMMARY.md without DESIGN.md returns state=design" {
  mkdir -p "$FORGE_DIR/research"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/research/SUMMARY.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "design" ]
  [ "$(jq_field '.dispatch')" = "design --orchestrated" ]
}

# --- DESIGN.md without PLAN.md ---

@test "DESIGN.md without PLAN.md returns state=plan" {
  mkdir -p "$FORGE_DIR/research"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/research/SUMMARY.md"
  touch "$FORGE_DIR/DESIGN.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "plan" ]
  [ "$(jq_field '.dispatch')" = "plan --orchestrated" ]
}

# --- PLAN.md without plan-mapping.json ---

@test "PLAN.md without plan-mapping.json returns state=decompose" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/DESIGN.md"
  touch "$FORGE_DIR/PLAN.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "decompose" ]
  [ "$(jq_field '.dispatch')" = "decompose --orchestrated" ]
}

# --- plan-mapping.json exists (stories not all done) ---

@test "plan-mapping.json with stories not done returns state=execute" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/DESIGN.md"
  touch "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  # story CLI may not return done stories -- script should handle gracefully
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "execute" ]
  [ "$(jq_field '.dispatch')" = "execute --orchestrated" ]
}

# --- REVIEW-REPORT.md + VALIDATE-REPORT.md ---

@test "both reports present returns state=triage" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/REVIEW-REPORT.md"
  touch "$FORGE_DIR/VALIDATE-REPORT.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "triage" ]
  [ "$(jq_field '.dispatch')" = "triage --orchestrated" ]
}

# --- TRIAGE.md with no FIX items ---

@test "TRIAGE.md with no FIX items returns state=document" {
  mkdir -p "$FORGE_DIR"
  cat > "$FORGE_DIR/TRIAGE.md" <<'EOF'
# Triage Report

## ESCALATE
- Some item

## ACCEPT
- Accept this
EOF
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "document" ]
  [ "$(jq_field '.dispatch')" = "document --orchestrated" ]
}

# --- TRIAGE.md with FIX items and cycle < max ---

@test "TRIAGE.md with FIX items and cycle < max returns state=fix_loop" {
  mkdir -p "$FORGE_DIR"
  cat > "$FORGE_DIR/TRIAGE.md" <<'EOF'
# Triage Report

## FIX
- Fix this bug
- Fix that bug

## ACCEPT
- Accept this
EOF
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "fix_loop" ]
  [ "$(jq_field '.dispatch')" = "plan --orchestrated" ]
  [ "$(jq_field '.fix_cycle')" = "0" ]
}

# --- TRIAGE.md with FIX items but cycle at max ---

@test "TRIAGE.md with FIX items but cycle at max returns state=document" {
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-1"
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-2"
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-3"
  echo '{"max_fix_cycles": 3}' > "$FORGE_DIR/config.json"
  cat > "$FORGE_DIR/TRIAGE.md" <<'EOF'
# Triage Report

## FIX
- Fix this
EOF
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "document" ]
  [ "$(jq_field '.fix_cycle')" = "3" ]
}

# --- TRIAGE.md with FIX items, yolo mode, higher max ---

@test "yolo mode uses max_fix_cycles_yolo" {
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-1"
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-2"
  mkdir -p "$FORGE_DIR/fix-cycles/cycle-3"
  echo '{"yolo": true, "max_fix_cycles": 3, "max_fix_cycles_yolo": 10}' > "$FORGE_DIR/config.json"
  cat > "$FORGE_DIR/TRIAGE.md" <<'EOF'
# Triage Report

## FIX
- Fix this
EOF
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "fix_loop" ]
  [ "$(jq_field '.yolo')" = "true" ]
  [ "$(jq_field '.max_fix_cycles')" = "10" ]
}

# --- DOCUMENTATION.md without ESCALATE stories ---

@test "DOCUMENTATION.md without ESCALATE returns state=pause_deploy" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/DOCUMENTATION.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "pause_deploy" ]
  # pause/complete states carry an explicit machine-readable dispatch
  # token instead of an empty string, so the router doesn't have to infer
  # the right branch from the state name alone.
  [ "$(jq_field '.dispatch')" = "deploy_gate" ]
}

# --- DEPLOY-APPROVAL.md ---

@test "DEPLOY-APPROVAL.md returns state=deploy" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/DEPLOY-APPROVAL.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "deploy" ]
  [ "$(jq_field '.dispatch')" = "deploy --orchestrated" ]
}

# --- COMPLETION.md ---

@test "COMPLETION.md returns state=complete" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/COMPLETION.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "complete" ]
  # Explicit token, not an empty dispatch.
  [ "$(jq_field '.dispatch')" = "report_complete" ]
}

# --- Artifacts map ---

@test "artifacts map reflects file presence" {
  mkdir -p "$FORGE_DIR/research"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/research/SUMMARY.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.artifacts["IDEA.md"]')" = "true" ]
  [ "$(jq_field '.artifacts["research/SUMMARY.md"]')" = "true" ]
  [ "$(jq_field '.artifacts["DESIGN.md"]')" = "false" ]
  [ "$(jq_field '.artifacts["PLAN.md"]')" = "false" ]
}

# --- Handoff detection ---

@test "detects latest handoff file" {
  mkdir -p "$FORGE_DIR/handoffs"
  touch "$FORGE_DIR/handoffs/handoff-interrogate.md"
  sleep 0.1
  touch "$FORGE_DIR/handoffs/handoff-research.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.has_handoff')" = "true" ]
  [ "$(jq_field '.latest_handoff')" = "handoffs/handoff-research.md" ]
}

@test "no handoff directory sets has_handoff=false" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.has_handoff')" = "false" ]
  [ "$(jq_field '.latest_handoff')" = "" ]
}

# --- Config defaults ---

@test "missing config.json uses defaults" {
  mkdir -p "$FORGE_DIR"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.yolo')" = "false" ]
  [ "$(jq_field '.max_fix_cycles')" = "3" ]
}

# --- Priority: higher states override lower ---

@test "COMPLETION.md overrides all other artifacts" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/DESIGN.md"
  touch "$FORGE_DIR/PLAN.md"
  touch "$FORGE_DIR/TRIAGE.md"
  touch "$FORGE_DIR/DOCUMENTATION.md"
  touch "$FORGE_DIR/DEPLOY-APPROVAL.md"
  touch "$FORGE_DIR/COMPLETION.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "complete" ]
}

# --- storyhook_available field ---

@test "storyhook_available field is present" {
  mkdir -p "$FORGE_DIR"
  run_state
  [ "$status" -eq 0 ]
  # Field should be boolean (true or false)
  local val
  val="$(jq_field '.storyhook_available')"
  [[ "$val" = "true" || "$val" = "false" ]]
}

# --- Valid JSON output ---

@test "output is valid JSON" {
  mkdir -p "$FORGE_DIR"
  run_state
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

# --- Real storyhook integration ---
#
# These drive the real `story` CLI in a throwaway project (never mocked —
# see CLAUDE.md). check_storyhook() doesn't `cd` into FORGE_DIR itself (it
# relies on the caller's cwd, matching production where forge always runs
# with the target project as cwd), so these use run_state_in_project to
# invoke the script from inside TEST_DIR.

init_storyhook() {
  ( cd "$TEST_DIR" && git init -q . && story init --prefix ST >/dev/null 2>&1 )
}

run_state_in_project() {
  run bash -c "cd '$TEST_DIR' && bash '$SCRIPT' '$FORGE_DIR'"
}

@test "stories_all_done reads the real double-nested story list --json shape" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  ( cd "$TEST_DIR" && \
    story new "Task A" >/dev/null && story new "Task B" >/dev/null && \
    story move ST-1 done >/dev/null && story move ST-2 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  # Before the fix, the wrong selector (.stories[].state) always parsed
  # as null, so stories_all_done was permanently false and this stayed stuck
  # in "execute" forever instead of advancing to review_validate.
  [ "$(jq_field '.state')" = "review_validate" ]
}

@test "escalate detection reads .story.title, not .title" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/DOCUMENTATION.md"
  ( cd "$TEST_DIR" && story new "ESCALATE: needs a decision" >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "pause_escalate" ]
  [ "$(jq_field '.dispatch')" = "escalate_review" ]
}

@test "a resolved (done) ESCALATE story does not block the deploy gate" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/DOCUMENTATION.md"
  ( cd "$TEST_DIR" && story new "ESCALATE: needs a decision" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "pause_deploy" ]
  [ "$(jq_field '.dispatch')" = "deploy_gate" ]
}

@test "neither review nor validate report dispatches the combined recipe" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "review_validate --orchestrated" ]
}

@test "review done and validate missing dispatches validate alone" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/REVIEW-REPORT.md"
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "validate --orchestrated" ]
}

@test "validate done and review missing dispatches review alone" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/VALIDATE-REPORT.md"
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "review --orchestrated" ]
}

@test "all non-done stories blocked surfaces state=blocked instead of wedging in execute" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && \
    story new "Task A" >/dev/null && story new "Task B" >/dev/null && \
    story state add blocked --super OPEN --role active >/dev/null && \
    story move ST-1 done >/dev/null && \
    story move ST-2 blocked "exhausted retries" >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "blocked" ]
  [ "$(jq_field '.dispatch')" = "blocked_review" ]
  [ "$(jq_field '.stories_blocked_only')" = "true" ]
}

@test "a blocked story alongside an actionable todo story stays in execute" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && \
    story new "Task A" >/dev/null && story new "Task B" >/dev/null && \
    story state add blocked --super OPEN --role active >/dev/null && \
    story move ST-1 blocked "exhausted retries" >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "execute" ]
  [ "$(jq_field '.stories_blocked_only')" = "false" ]
}

# --- The decompose-created "project story" deadlock ---
#
# `story decompose` auto-creates a synthetic parent story from the input
# markdown's top heading (see references/story-decomposition.md). storyhook's
# `story next` permanently excludes ANY story with children from ever being
# offered (a `has_children` filter in storyhook's src/app.rs), so once every
# real task story reaches `done`, the parent is the only story left non-done
# -- forever, since nothing ever hands it back to `story next` to close it.
# Before the fix, check_storyhook() required this parent to be `done` via
# the exact same path as a real leaf story, so `stories_all_done` could never
# become true and forge-state.sh reported `state:"execute"` forever instead
# of transitioning to `review_validate`. This is a live-testing find, not one
# of the plan's 106 catalogued findings.

decompose_single_task_plan() {
  ( cd "$TEST_DIR" && \
    printf '## Task Breakdown\n\n### Wave 1\n\n- [ ] [HIGH] Only task\n' \
      | story decompose --stdin --json >/dev/null )
}

@test "a decompose-created parent story does not permanently wedge execute in the state machine" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  decompose_single_task_plan
  # ST-1 is the auto-created parent ("Task Breakdown"), ST-2 is the one real
  # task story -- confirm the fixture matches the documented decompose shape
  # before asserting anything about forge-state.sh's behavior on top of it.
  run bash -c "cd '$TEST_DIR' && story list --json | jq -r '.stories[] | select(.story.id==\"ST-1\") | .story.relationships[0].relation'"
  [ "$output" = "parent-of" ]

  echo '{"plan_hash":"x","project_story":"ST-1","stories":{}}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && story move ST-2 in-progress >/dev/null && story move ST-2 done >/dev/null )

  # Confirm the underlying storyhook bug this test guards against: `story
  # next` really does refuse to ever hand back the parent, and it really
  # does stay "todo" forever with no other action taken.
  run bash -c "cd '$TEST_DIR' && story next --json | jq -r '.message'"
  [ "$output" = "no ready stories" ]
  run bash -c "cd '$TEST_DIR' && story list --json | jq -r '.stories[] | select(.story.id==\"ST-1\") | .story.state'"
  [ "$output" = "todo" ]

  # forge-state.sh must not be fooled by this: with plan-mapping.json's
  # project_story excluded from the done-check, it should already report
  # review_validate even though ST-1 (the parent) is still literally "todo"
  # in storyhook and no explicit close has happened.
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "review_validate --orchestrated" ]
}

@test "closing the project story via forge-close-project-story.sh keeps forge-state.sh in agreement" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  decompose_single_task_plan
  echo '{"plan_hash":"x","project_story":"ST-1","stories":{}}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && story move ST-2 in-progress >/dev/null && story move ST-2 done >/dev/null )

  # Simulate the execute loop's Complete step explicitly closing the parent
  # for hygiene (references/execution-loop.md).
  run bash "$BATS_TEST_DIRNAME/forge-close-project-story.sh" "$TEST_DIR"
  [ "$(echo "$output" | jq -r '.reason')" = "closed" ]
  run bash -c "cd '$TEST_DIR' && story list --json | jq -r '.stories[] | select(.story.id==\"ST-1\") | .story.state'"
  [ "$output" = "done" ]

  # forge-state.sh's own detection is unaffected either way -- defense in
  # depth, not a dependency on the close having run.
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
}

@test "a project story with zero real task stories does not wedge check_storyhook on an empty states list" {
  # `story decompose --stdin` allows a wave with zero checkbox items,
  # producing a parent-only story list (project_story is the ONLY story).
  # Excluding project_story then leaves an empty selection. A prior
  # implementation computed the non-done count via
  # `states=$(... ) ; echo "$states" | grep -cv '^done$'` -- but `echo ""`
  # still emits one blank line, so grep counted it as 1 non-done entry and
  # stories_all_done stayed false forever, wedging execute the same way the
  # project-story deadlock above does, just via a different trigger. Guard
  # against regressing back to that shell/grep counting idiom.
  init_storyhook
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  ( cd "$TEST_DIR" && \
    printf '## Task Breakdown\n\n### Wave 1\n\n' \
      | story decompose --stdin --json >/dev/null )
  run bash -c "cd '$TEST_DIR' && story list --json | jq '.stories | length'"
  [ "$output" = "1" ]

  echo '{"plan_hash":"x","project_story":"ST-1","stories":{}}' > "$FORGE_DIR/plan-mapping.json"

  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "review_validate --orchestrated" ]
}

# --- Expected handoff for the specific step being resumed ---

@test "expected handoff for design is research's, not just any newest file" {
  mkdir -p "$FORGE_DIR/handoffs" "$FORGE_DIR/research"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/research/SUMMARY.md"
  # Only an older, unrelated handoff exists -- NOT handoff-research.md.
  touch "$FORGE_DIR/handoffs/handoff-interrogate.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "design" ]
  [ "$(jq_field '.has_handoff')" = "true" ]
  [ "$(jq_field '.expected_handoff')" = "handoff-research.md" ]
  [ "$(jq_field '.expected_handoff_present')" = "false" ]
}

@test "expected_handoff_present becomes true once the specific handoff exists" {
  mkdir -p "$FORGE_DIR/handoffs" "$FORGE_DIR/research"
  touch "$FORGE_DIR/IDEA.md"
  touch "$FORGE_DIR/research/SUMMARY.md"
  touch "$FORGE_DIR/handoffs/handoff-interrogate.md"
  touch "$FORGE_DIR/handoffs/handoff-research.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.expected_handoff')" = "handoff-research.md" ]
  [ "$(jq_field '.expected_handoff_present')" = "true" ]
}

@test "triage requires both review's and validate's handoffs" {
  mkdir -p "$FORGE_DIR/handoffs"
  touch "$FORGE_DIR/REVIEW-REPORT.md"
  touch "$FORGE_DIR/VALIDATE-REPORT.md"
  touch "$FORGE_DIR/handoffs/handoff-review.md"
  run_state
  [ "$(jq_field '.state')" = "triage" ]
  [ "$(jq_field '.expected_handoff')" = "handoff-review.md,handoff-validate.md" ]
  [ "$(jq_field '.expected_handoff_present')" = "false" ]

  touch "$FORGE_DIR/handoffs/handoff-validate.md"
  run_state
  [ "$(jq_field '.expected_handoff_present')" = "true" ]
}

@test "interrogate (fresh pipeline) expects no prior handoff" {
  run_state
  [ "$(jq_field '.state')" = "interrogate" ]
  [ "$(jq_field '.expected_handoff')" = "" ]
  [ "$(jq_field '.expected_handoff_present')" = "true" ]
}

# --- Fresh-start vs. resume discriminator ---

@test "no state.json signals a fresh execute start, not a resume" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run_state
  [ "$(jq_field '.state')" = "execute" ]
  [ "$(jq_field '.state_json_exists')" = "false" ]
  [ "$(jq_field '.state_json_status')" = "" ]
  [ "$(jq_field '.expected_handoff')" = "handoff-decompose.md" ]
}

@test "an existing state.json signals execute is resuming, not starting fresh" {
  mkdir -p "$FORGE_DIR/handoffs"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  echo '{"status": "paused", "sessions_completed": 1}' > "$FORGE_DIR/state.json"
  run_state
  [ "$(jq_field '.state')" = "execute" ]
  [ "$(jq_field '.state_json_exists')" = "true" ]
  [ "$(jq_field '.state_json_status')" = "paused" ]
  [ "$(jq_field '.expected_handoff')" = "handoff-execute.md" ]
}

@test "malformed state.json is treated as absent, not a crash" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  echo 'not valid json' > "$FORGE_DIR/state.json"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state_json_exists')" = "false" ]
}
