#!/usr/bin/env bats
# Native contracts are reached through the existing Forge runner and isolation boundary.

@test "Codex instruction, resolver, hook, explorer and lifecycle regressions" {
  run python3 -B -m unittest discover -s "$BATS_TEST_DIRNAME/../tests" -p 'codex_*test.py'
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; return 1; fi
}

@test "Codex installed Forge resolves skills, dependencies and native hook commands" {
  run bash "$BATS_TEST_DIRNAME/../tests/test-codex-install.sh"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; return 1; fi
}

@test "Codex documented StoryHook setup runs against the real CLI" {
  run env FORGE_SETUP_SKILL="$BATS_TEST_DIRNAME/../codex/skills/decompose/SKILL.md" \
    bats "$BATS_TEST_DIRNAME/forge-storyhook-setup-contract.bats"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; return 1; fi
}
