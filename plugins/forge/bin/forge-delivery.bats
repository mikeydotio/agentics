#!/usr/bin/env bats
# Production delivery gates and both-host instruction coverage.

@test "delivery: pending specialists cannot advance, commit or clean Forge" {
  run python3 -B -W error "$BATS_TEST_DIRNAME/../tests/delivery_test.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "delivery: every Forge dispatch follows bounded owner policy" {
  run python3 -B -W error "$BATS_TEST_DIRNAME/../tests/delivery_contract_test.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
