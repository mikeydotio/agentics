#!/usr/bin/env bats
# Tests for forge-agent-alignment-check.sh — the WS3 regression guard that keeps
# forge's roster declarations and spawn sites from drifting back to a
# nonexistent agent name (F061/F083) or a bare `general-purpose` default with
# no registered-type/fallback path (F057).

SCRIPT="$BATS_TEST_DIRNAME/forge-agent-alignment-check.sh"
FORGE_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
AGENTS_ROOT="$(cd "$FORGE_ROOT/../agents" && pwd)"

setup() {
  FIXTURE_DIR="$(mktemp -d)"
  AGENTS_FIXTURE="$(mktemp -d)"
  export FIXTURE_DIR AGENTS_FIXTURE
  mkdir -p "$FIXTURE_DIR/references" "$FIXTURE_DIR/skills/execute" "$FIXTURE_DIR/agent-overrides"
  mkdir -p "$AGENTS_FIXTURE/agents"
  # A small, deliberately real roster for fixture tests.
  for name in generator evaluator reviewer triager validator software-architect \
              skeptic software-engineer qa-engineer project-manager \
              ux-designer-cli ux-designer-web ux-designer-mobile; do
    echo "---" > "$AGENTS_FIXTURE/agents/$name.md"
  done
}

teardown() {
  [[ -n "${FIXTURE_DIR:-}" && -d "$FIXTURE_DIR" ]] && rm -rf "$FIXTURE_DIR"
  [[ -n "${AGENTS_FIXTURE:-}" && -d "$AGENTS_FIXTURE" ]] && rm -rf "$AGENTS_FIXTURE"
}

jq_field() {
  echo "$output" | jq -r "$1"
}

# --- agents library unresolvable ---

@test "alignment-check: ok is false when the agents plugin root doesn't resolve" {
  run bash "$SCRIPT" "$FIXTURE_DIR" "/nonexistent/agents/root"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.error')" = "agents_library_missing" ]
}

# --- Real committed docs: the actual regression guard ---

@test "alignment-check: real committed forge docs are clean against the real agents library" {
  run bash "$SCRIPT" "$FORGE_ROOT" "$AGENTS_ROOT"
  echo "$output" >&2
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.alignment_ok')" = "true" ]
  [ "$(jq_field '.unresolved_roster_tokens | length')" -eq 0 ]
  [ "$(jq_field '.spawn_site_violations | length')" -eq 0 ]
}

@test "alignment-check: scans a nonzero number of real forge files and reports the real roster" {
  run bash "$SCRIPT" "$FORGE_ROOT" "$AGENTS_ROOT"
  [ "$(jq_field '.files_scanned | length')" -gt 0 ]
  [ "$(jq_field '.real_roster | length')" -gt 0 ]
  echo "$output" | jq -e '.real_roster | index("senior-engineer") == null' >/dev/null
  echo "$output" | jq -e '.real_roster | index("devils-advocate") == null' >/dev/null
  echo "$output" | jq -e '.real_roster | index("ux-designer") == null' >/dev/null
  echo "$output" | jq -e '.real_roster | index("skeptic") != null' >/dev/null
  echo "$output" | jq -e '.real_roster | index("software-engineer") != null' >/dev/null
}

# --- Drift detection: reintroduce a phantom agent name ---

@test "alignment-check: catches a reintroduced senior-engineer roster bullet" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

## Agent Roster

- `senior-engineer` — implements things
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.unresolved_roster_tokens | length')" -eq 1 ]
  [ "$(jq_field '.unresolved_roster_tokens[0].name')" = "senior-engineer" ]
}

@test "alignment-check: catches a reintroduced devils-advocate table row" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

## Agent Roster (team)

| Agent | Used By |
|-------|---------|
| `devils-advocate` | design, plan |
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.unresolved_roster_tokens[0].name')" = "devils-advocate" ]
}

@test "alignment-check: catches a bare ux-designer (no platform suffix) in a conditional bullet" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

### Conditionally Activated

- ux-designer: [YES/NO — reason]
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.unresolved_roster_tokens[0].name')" = "ux-designer" ]
}

@test "alignment-check: does NOT flag the documented ux-designer-{cli|web|mobile} shorthand" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

### Conditionally Activated

- ux-designer-{cli|web|mobile}: [YES/NO — which variant and why]
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "true" ]
}

@test "alignment-check: catches skills/*/SKILL.md roster bullets too, not just references/" {
  cat > "$FIXTURE_DIR/skills/execute/SKILL.md" <<'EOF'
---
name: execute
---

## Spawn the Execute Team

- `senior-engineer` — writes the code
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.unresolved_roster_tokens[0].file')" = "skills/execute/SKILL.md" ]
}

# --- No false positives outside a roster-declaration heading ---

@test "alignment-check: ignores kebab-case table rows outside a team/roster/spawn-agent heading" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

## State Transition Summary

| From | To | Trigger |
|------|-----|---------|
| `todo` | `in-progress` | Story picked by orchestrator |
| `nonexistent-state-name` | `done` | Something happens |
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "true" ]
  [ "$(jq_field '.unresolved_roster_tokens | length')" -eq 0 ]
}

@test "alignment-check: ignores plain bullets outside a roster heading" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

## Some Unrelated Section

- some-unrelated-bullet
- another-thing-entirely
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "true" ]
}

@test "alignment-check: does not flag a documentation placeholder like agents:<name>" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

Try `subagent_type: "agents:<name>"` first.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "true" ]
}

# --- Spawn-site checks ---

@test "alignment-check: catches an unregistered subagent_type namespace (e.g. forge:)" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

```
Agent(
  subagent_type: "forge:software-architect",
  prompt: "..."
)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.spawn_site_violations | length')" -eq 1 ]
  [ "$(jq_field '.spawn_site_violations[0].reason')" = "unregistered_namespace" ]
}

@test "alignment-check: catches agents:<unknown-name> as a spawn-site violation" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

```
subagent_type: "agents:senior-engineer",
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "false" ]
  [ "$(jq_field '.spawn_site_violations[0].reason')" = "unknown_agent" ]
}

@test "alignment-check: flags general-purpose spawned with no agents: fallback documented anywhere in the file" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

```
Agent(
  subagent_type: "general-purpose",
  prompt: "..."
)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "false" ]
  echo "$output" | jq -e '.spawn_site_violations | any(.reason == "undocumented_fallback_no_agents_namespace_mentioned")' >/dev/null
}

@test "alignment-check: allows general-purpose when the file documents the agents: preferred path" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

Preferred: subagent_type: "agents:generator". Fallback:

```
Agent(
  subagent_type: "general-purpose",
  prompt: "..."
)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "true" ]
}

@test "alignment-check: accepts agents:<real-name> as a clean spawn site" {
  cat > "$FIXTURE_DIR/references/fixture.md" <<'EOF'
# Fixture

```
subagent_type: "agents:generator",
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.alignment_ok')" = "true" ]
}

# --- Output shape ---

@test "alignment-check: output is always valid JSON" {
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  echo "$output" | jq . >/dev/null
}

@test "alignment-check: empty docs-root against a real agents-root reports ok true, alignment_ok true, zero files scanned" {
  run bash "$SCRIPT" "$FIXTURE_DIR" "$AGENTS_FIXTURE"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.alignment_ok')" = "true" ]
  [ "$(jq_field '.files_scanned | length')" -eq 0 ]
}
