#!/usr/bin/env bash
# owner/repo derivation from the origin remote across URL forms (https, ssh,
# scp-style, with/without .git). Asserted via the .repo field of `list`.
source "$(dirname "$0")/lib.sh"

check() {  # check <origin-url> <expected-repo>
  local dir out
  dir=$(mk_repo "$1")
  out=$(cd "$dir" && bash "$SCRIPT" list 2>&1)
  assert_eq "$(jqf "$out" .repo)" "$2" "origin [$1]"
}

check "https://github.com/mikeyward/agentics.git"  "mikeyward/agentics"
check "https://github.com/mikeyward/agentics"      "mikeyward/agentics"
check "git@github.com:mikeyward/agentics.git"       "mikeyward/agentics"
check "git@github.com:mikeyward/agentics"           "mikeyward/agentics"
check "ssh://git@github.com/mikeyward/agentics.git"  "mikeyward/agentics"

finish
