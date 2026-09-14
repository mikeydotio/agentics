#!/usr/bin/env bats
# Exact instruction coverage for both Forge hosts. This does not simulate model compliance.

@test "integrity: both hosts fail closed on unverified results" {
  run python3 -B -W error "$BATS_TEST_DIRNAME/../tests/integrity_contract_test.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
