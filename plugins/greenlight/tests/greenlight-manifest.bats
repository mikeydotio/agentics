#!/usr/bin/env bats
load contract-helper

setup_file() {
  GL_PRODUCTION_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export GL_PRODUCTION_ROOT
}

prepare_roots() {
  local host root
  for host in codex claude; do
    root="$GL_TEST_ROOT/$host plugin"
    mkdir -p "$root/hooks" "$root/references"
    # Invoke the production hook; only bundled data differs to identify the root.
    ln -s "$GL_PRODUCTION_ROOT/hooks/greenlight.sh" "$root/hooks/greenlight.sh"
    ln -s "$GL_PRODUCTION_ROOT/lib" "$root/lib"
    sed "s|^log_file:.*|log_file: $root/decisions.log|" \
      "$GL_PRODUCTION_ROOT/references/default-config.yaml" > "$root/references/default-config.yaml"
  done
  rm "$GL_CONFIG"
}

run_manifest() {
  local invocation
  invocation="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$GL_PRODUCTION_ROOT/hooks/hooks.json")"
  run env -i HOME="$GL_TEST_ROOT" PATH="$GL_TEST_ROOT/bin:$PATH" "$@" \
    bash -c "$invocation" <<< "$(payload codex Read '')"
}

assert_root() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$GL_CONFIG" ]
  [ -s "$1/decisions.log" ]
  grep -F '[ALLOW] Read:' "$1/decisions.log"
  local other
  for other in "$GL_TEST_ROOT/codex plugin" "$GL_TEST_ROOT/claude plugin"; do
    [[ "$other" == "$1" ]] || [ ! -e "$other/decisions.log" ]
  done
  [ ! -e "$GL_TEST_ROOT/curl.log" ]
}

@test "manifest loads PLUGIN_ROOT alone including a path with spaces" {
  prepare_roots
  run_manifest PLUGIN_ROOT="$GL_TEST_ROOT/codex plugin"
  assert_root "$GL_TEST_ROOT/codex plugin"
}

@test "manifest loads CLAUDE_PLUGIN_ROOT alone including a path with spaces" {
  prepare_roots
  run_manifest CLAUDE_PLUGIN_ROOT="$GL_TEST_ROOT/claude plugin"
  assert_root "$GL_TEST_ROOT/claude plugin"
}

@test "manifest and bundled resources prefer PLUGIN_ROOT when both are set" {
  prepare_roots
  run_manifest PLUGIN_ROOT="$GL_TEST_ROOT/codex plugin" CLAUDE_PLUGIN_ROOT="$GL_TEST_ROOT/claude plugin"
  assert_root "$GL_TEST_ROOT/codex plugin"
}

@test "empty PLUGIN_ROOT falls back to CLAUDE_PLUGIN_ROOT" {
  prepare_roots
  run_manifest PLUGIN_ROOT= CLAUDE_PLUGIN_ROOT="$GL_TEST_ROOT/claude plugin"
  assert_root "$GL_TEST_ROOT/claude plugin"
}

@test "empty CLAUDE_PLUGIN_ROOT does not shadow PLUGIN_ROOT" {
  prepare_roots
  run_manifest PLUGIN_ROOT="$GL_TEST_ROOT/codex plugin" CLAUDE_PLUGIN_ROOT=
  assert_root "$GL_TEST_ROOT/codex plugin"
}

@test "direct hook invocation finds its own bundled resources without root variables" {
  prepare_roots
  run env -i HOME="$GL_TEST_ROOT" PATH="$GL_TEST_ROOT/bin:$PATH" \
    bash "$GL_TEST_ROOT/codex plugin/hooks/greenlight.sh" <<< "$(payload codex Read '')"
  assert_root "$GL_TEST_ROOT/codex plugin"
}
