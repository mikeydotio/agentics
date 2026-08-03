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

# Helper: write minimally-valid content for one or more pipeline artifact
# files (F102 — forge-state.sh's artifact_exists now requires non-empty
# content with a top-level H1 for .md files, so a bare `touch` no longer
# counts as "present"). NOT used for handoffs/*.md, which are a separate,
# existence-only detection mechanism (detect_handoff) unaffected by F102.
mkmd() {
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "$f")"
    printf '# %s\n\nContent.\n' "$(basename "$f" .md)" > "$f"
  done
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
  mkmd "$FORGE_DIR/IDEA.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "research" ]
  [ "$(jq_field '.dispatch')" = "research --orchestrated" ]
}

# --- research/SUMMARY.md without DESIGN.md ---

@test "research/SUMMARY.md without DESIGN.md returns state=design" {
  mkdir -p "$FORGE_DIR/research"
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/research/SUMMARY.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "design" ]
  [ "$(jq_field '.dispatch')" = "design --orchestrated" ]
}

# --- DESIGN.md without PLAN.md ---

@test "DESIGN.md without PLAN.md returns state=plan" {
  mkdir -p "$FORGE_DIR/research"
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/research/SUMMARY.md"
  mkmd "$FORGE_DIR/DESIGN.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "plan" ]
  [ "$(jq_field '.dispatch')" = "plan --orchestrated" ]
}

# --- PLAN.md without plan-mapping.json ---

@test "PLAN.md without plan-mapping.json returns state=decompose" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/DESIGN.md"
  mkmd "$FORGE_DIR/PLAN.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "decompose" ]
  [ "$(jq_field '.dispatch')" = "decompose --orchestrated" ]
}

# --- plan-mapping.json exists (stories not all done) ---

@test "plan-mapping.json with stories not done returns state=execute" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/DESIGN.md"
  mkmd "$FORGE_DIR/PLAN.md"
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
  mkmd "$FORGE_DIR/REVIEW-REPORT.md"
  mkmd "$FORGE_DIR/VALIDATE-REPORT.md"
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
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
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
  mkmd "$FORGE_DIR/DEPLOY-APPROVAL.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "deploy" ]
  [ "$(jq_field '.dispatch')" = "deploy --orchestrated" ]
}

# --- COMPLETION.md ---

@test "COMPLETION.md returns state=complete" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/COMPLETION.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "complete" ]
  # Explicit token, not an empty dispatch.
  [ "$(jq_field '.dispatch')" = "report_complete" ]
}

# --- Artifacts map ---

@test "artifacts map reflects file presence" {
  mkdir -p "$FORGE_DIR/research"
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/research/SUMMARY.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.artifacts["IDEA.md"]')" = "true" ]
  [ "$(jq_field '.artifacts["research/SUMMARY.md"]')" = "true" ]
  [ "$(jq_field '.artifacts["DESIGN.md"]')" = "false" ]
  [ "$(jq_field '.artifacts["PLAN.md"]')" = "false" ]
}

# --- F102: a truncated/empty artifact must not count as "present" ---
#
# Before this fix, artifact_exists was a bare `[ -f ... ]` — a zero-byte or
# mid-write file (exactly what a freshen /clear or a Stop-hook timeout can
# leave behind) silently advanced the state machine, which is worse than a
# missing file (a missing file at least re-runs the step).

@test "F102: a zero-byte IDEA.md does not count as present (stays in interrogate)" {
  mkdir -p "$FORGE_DIR"
  touch "$FORGE_DIR/IDEA.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "interrogate" ]
  [ "$(jq_field '.artifacts["IDEA.md"]')" = "false" ]
}

@test "F102: a non-empty .md file with no top-level H1 does not count as present" {
  mkdir -p "$FORGE_DIR"
  printf 'some prose with no heading at all\n' > "$FORGE_DIR/IDEA.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "interrogate" ]
  [ "$(jq_field '.artifacts["IDEA.md"]')" = "false" ]
}

@test "F102: a .md file whose H1 is not the first line still counts (H1 anywhere at line start)" {
  mkdir -p "$FORGE_DIR"
  printf 'Some preamble.\n\n# Idea\n\nBody.\n' > "$FORGE_DIR/IDEA.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "research" ]
  [ "$(jq_field '.artifacts["IDEA.md"]')" = "true" ]
}

@test "F102: an empty plan-mapping.json does not count as present (stays in decompose)" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  touch "$FORGE_DIR/plan-mapping.json"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "decompose" ]
  [ "$(jq_field '.artifacts["plan-mapping.json"]')" = "false" ]
}

@test "F102: a plan-mapping.json with invalid JSON does not count as present" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo "this is not json" > "$FORGE_DIR/plan-mapping.json"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "decompose" ]
  [ "$(jq_field '.artifacts["plan-mapping.json"]')" = "false" ]
}

@test "F102: a valid-JSON plan-mapping.json counts as present" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "execute" ]
  [ "$(jq_field '.artifacts["plan-mapping.json"]')" = "true" ]
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
  mkmd "$FORGE_DIR/IDEA.md"
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
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/DESIGN.md"
  mkmd "$FORGE_DIR/PLAN.md"
  mkmd "$FORGE_DIR/TRIAGE.md"
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
  mkmd "$FORGE_DIR/DEPLOY-APPROVAL.md"
  mkmd "$FORGE_DIR/COMPLETION.md"
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
  ( cd "$TEST_DIR" && git init -q . && story project new --prefix ST >/dev/null )
}

# `story_type` is a fixed, project-scoped enum (story init seeds
# bug/chore/epic/story/task, NOT escalate) -- `story new/set --type escalate`
# errors with "unknown type" until this is registered once, mirroring
# decompose/SKILL.md Step 2's real registration call.
register_escalate_type() {
  ( cd "$TEST_DIR" && story type add escalate --description "test" >/dev/null 2>&1 )
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

@test "escalate detection reads the structured story_type field, not a title substring (F006)" {
  init_storyhook
  register_escalate_type
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
  ( cd "$TEST_DIR" && story new "ESCALATE: needs a decision" --type escalate >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "pause_escalate" ]
  [ "$(jq_field '.dispatch')" = "escalate_review" ]
}

@test "a resolved (done) ESCALATE story does not block the deploy gate" {
  init_storyhook
  register_escalate_type
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
  ( cd "$TEST_DIR" && story new "ESCALATE: needs a decision" --type escalate >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "pause_deploy" ]
  [ "$(jq_field '.dispatch')" = "deploy_gate" ]
}

@test "a legitimate story whose title merely contains 'escalate' is NOT mistaken for a pending escalation (F006)" {
  # Regression guard for the false-positive half of F006: before the fix,
  # forge-state.sh grepped the title case-insensitively for 'ESCALATE'
  # anywhere in it, so a normal feature story like this one would have
  # wedged the pipeline in pause_escalate forever.
  init_storyhook
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
  ( cd "$TEST_DIR" && story new "Implement alert escalation policy" >/dev/null )
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
  mkmd "$FORGE_DIR/REVIEW-REPORT.md"
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "validate --orchestrated" ]
}

@test "validate done and review missing dispatches review alone" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/VALIDATE-REPORT.md"
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state')" = "review_validate" ]
  [ "$(jq_field '.dispatch')" = "review --orchestrated" ]
}

@test "all non-done stories blocked surfaces state=blocked instead of wedging in execute" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && \
    story new "Task A" >/dev/null && story new "Task B" >/dev/null && \
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
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && \
    story new "Task A" >/dev/null && story new "Task B" >/dev/null && \
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
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
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
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
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
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
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
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/research/SUMMARY.md"
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
  mkmd "$FORGE_DIR/IDEA.md"
  mkmd "$FORGE_DIR/research/SUMMARY.md"
  touch "$FORGE_DIR/handoffs/handoff-interrogate.md"
  touch "$FORGE_DIR/handoffs/handoff-research.md"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.expected_handoff')" = "handoff-research.md" ]
  [ "$(jq_field '.expected_handoff_present')" = "true" ]
}

@test "triage requires both review's and validate's handoffs" {
  mkdir -p "$FORGE_DIR/handoffs"
  mkmd "$FORGE_DIR/REVIEW-REPORT.md"
  mkmd "$FORGE_DIR/VALIDATE-REPORT.md"
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
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run_state
  [ "$(jq_field '.state')" = "execute" ]
  [ "$(jq_field '.state_json_exists')" = "false" ]
  [ "$(jq_field '.state_json_status')" = "" ]
  [ "$(jq_field '.expected_handoff')" = "handoff-decompose.md" ]
}

@test "an existing state.json signals execute is resuming, not starting fresh" {
  mkdir -p "$FORGE_DIR/handoffs"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
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
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  echo 'not valid json' > "$FORGE_DIR/state.json"
  run_state
  [ "$status" -eq 0 ]
  [ "$(jq_field '.state_json_exists')" = "false" ]
}

# --- category / auto_advance / transition_id (agentics#33) ---
#
# `category` is the router's internal classification, named instead of left
# implicit inside `dispatch` string-matching. `auto_advance` is a pure
# derived view (`category == "pass_through"`). Both are pure telemetry here
# -- nothing acts on them yet (see design doc on agentics#33) -- but they
# must be correct and present on every state, including the byte-identical-
# dispatch trap where `fix_loop` and a plain design->plan transition share
# the exact same `dispatch` string and only `category` (backed by `state`)
# tells them apart.

@test "category=pass_through, auto_advance=true for interrogate (fresh pipeline)" {
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for research" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md"
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for design" {
  mkdir -p "$FORGE_DIR/research"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/research/SUMMARY.md"
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for plan (plain design->plan transition)" {
  mkdir -p "$FORGE_DIR/research"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/research/SUMMARY.md" "$FORGE_DIR/DESIGN.md"
  run_state
  [ "$(jq_field '.state')" = "plan" ]
  [ "$(jq_field '.dispatch')" = "plan --orchestrated" ]
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for decompose" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for execute" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for triage (both reports present)" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/REVIEW-REPORT.md" "$FORGE_DIR/VALIDATE-REPORT.md"
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for document (TRIAGE.md, no FIX items)" {
  mkdir -p "$FORGE_DIR"
  cat > "$FORGE_DIR/TRIAGE.md" <<'EOF'
# Triage Report

## ACCEPT
- Accept this
EOF
  run_state
  [ "$(jq_field '.state')" = "document" ]
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=pass_through, auto_advance=true for deploy" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/DEPLOY-APPROVAL.md"
  run_state
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

@test "category=fix_loop, auto_advance=false -- distinguishes the byte-identical dispatch trap from plain plan" {
  mkdir -p "$FORGE_DIR"
  cat > "$FORGE_DIR/TRIAGE.md" <<'EOF'
# Triage Report

## FIX
- Fix this bug
EOF
  run_state
  [ "$(jq_field '.state')" = "fix_loop" ]
  # Same literal dispatch string as the plain design->plan test above --
  # category (backed by `state`, checked first) is what actually
  # disambiguates them, not dispatch.
  [ "$(jq_field '.dispatch')" = "plan --orchestrated" ]
  [ "$(jq_field '.category')" = "fix_loop" ]
  [ "$(jq_field '.auto_advance')" = "false" ]
}

@test "category=deploy_gate, auto_advance=false for pause_deploy" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
  run_state
  [ "$(jq_field '.state')" = "pause_deploy" ]
  [ "$(jq_field '.category')" = "deploy_gate" ]
  [ "$(jq_field '.auto_advance')" = "false" ]
}

@test "category=report_complete, auto_advance=false for complete" {
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/COMPLETION.md"
  run_state
  [ "$(jq_field '.state')" = "complete" ]
  [ "$(jq_field '.category')" = "report_complete" ]
  [ "$(jq_field '.auto_advance')" = "false" ]
}

@test "category=blocked_review, auto_advance=false for blocked" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md" "$FORGE_DIR/DESIGN.md" "$FORGE_DIR/PLAN.md"
  echo '{}' > "$FORGE_DIR/plan-mapping.json"
  ( cd "$TEST_DIR" && \
    story new "Task A" >/dev/null && \
    story move ST-1 blocked "exhausted retries" >/dev/null )
  run_state_in_project
  [ "$(jq_field '.state')" = "blocked" ]
  [ "$(jq_field '.category')" = "blocked_review" ]
  [ "$(jq_field '.auto_advance')" = "false" ]
}

@test "category=escalate_review, auto_advance=false for pause_escalate" {
  init_storyhook
  register_escalate_type
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/DOCUMENTATION.md"
  ( cd "$TEST_DIR" && story new "ESCALATE: needs a decision" --type escalate >/dev/null )
  run_state_in_project
  [ "$(jq_field '.state')" = "pause_escalate" ]
  [ "$(jq_field '.category')" = "escalate_review" ]
  [ "$(jq_field '.auto_advance')" = "false" ]
}

@test "category=pass_through for all three review_validate dispatch variants" {
  init_storyhook
  mkdir -p "$FORGE_DIR"
  ( cd "$TEST_DIR" && story new "Task" >/dev/null && story move ST-1 done >/dev/null )
  run_state_in_project
  [ "$(jq_field '.dispatch')" = "review_validate --orchestrated" ]
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]

  mkmd "$FORGE_DIR/REVIEW-REPORT.md"
  run_state_in_project
  [ "$(jq_field '.dispatch')" = "validate --orchestrated" ]
  [ "$(jq_field '.category')" = "pass_through" ]
  [ "$(jq_field '.auto_advance')" = "true" ]
}

# --- transition_id ---

@test "transition_id is present and non-empty" {
  run_state
  local tid
  tid="$(jq_field '.transition_id')"
  [ -n "$tid" ]
  [ "$tid" != "null" ]
}

@test "transition_id differs across two consecutive invocations" {
  run_state
  local first
  first="$(jq_field '.transition_id')"
  run_state
  local second
  second="$(jq_field '.transition_id')"
  [ "$first" != "$second" ]
}

# --- --record-transition (opt-in logging to .freshen/transitions.log) ---

@test "without --record-transition, no predicted line is written to transitions.log" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.freshen/transitions.log" ]
}

@test "--record-transition appends a predicted line with category, dispatch, and transition_id" {
  cd "$TEST_DIR"
  mkdir -p "$FORGE_DIR"
  mkmd "$FORGE_DIR/IDEA.md"
  run bash "$SCRIPT" "$FORGE_DIR" --record-transition
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/transitions.log" ]
  local tid
  tid="$(jq_field '.transition_id')"
  run grep -c "predicted category=pass_through dispatch=\"research --orchestrated\" transition_id=${tid}" "$TEST_DIR/.freshen/transitions.log"
  [ "$output" = "1" ]
}

@test "--record-transition works regardless of flag position relative to the forge-dir argument" {
  cd "$TEST_DIR"
  run bash "$SCRIPT" --record-transition "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.freshen/transitions.log" ]
  [ "$(jq_field '.state')" = "interrogate" ]
}

@test "--record-transition logging failure never affects forge-state.sh's JSON output or exit code" {
  cd "$TEST_DIR"
  mkdir -p "$(dirname "$FORGE_DIR")"
  # Occupy the log directory's path with a plain file so mkdir -p fails --
  # transition-log.sh's own best-effort swallow (already covered by its own
  # bats suite) must hold at this integration level too.
  : > "$TEST_DIR/.freshen"
  run bash "$SCRIPT" "$FORGE_DIR" --record-transition
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  [ "$(jq_field '.state')" = "interrogate" ]
}

# --- Structural coverage guard ---
#
# Every `dispatch="..."` assignment inside detect_state() must have a
# corresponding `category="..."` assignment at the same branch, so a future
# branch added to the state machine can't silently leave category unset
# (which would default to "unknown" -- fail-closed, never a silent
# "pass_through" -- but should never happen in practice; this test makes an
# omission a loud CI failure instead of a quiet gap).

@test "structural coverage: every dispatch assignment in detect_state() has a matching category assignment" {
  local fn_body
  fn_body="$(awk '/^detect_state\(\) \{/,/^}/' "$SCRIPT")"
  # Only count branch-level assignments (indented 4+ spaces, i.e. inside an
  # if/elif/else body) -- this deliberately excludes the two 2-space-indent
  # function-level lines that aren't part of the per-branch pairing: the
  # `local dispatch=""`/`local category=""` declarations, and the
  # fail-closed `category="unknown"` default applied after the chain.
  local dispatch_count category_count
  dispatch_count="$(echo "$fn_body" | grep -cE '^ {4,}dispatch="')"
  category_count="$(echo "$fn_body" | grep -cE '^ {4,}category="')"
  [ "$dispatch_count" -gt 0 ]
  [ "$dispatch_count" -eq "$category_count" ]
}
