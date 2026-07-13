#!/usr/bin/env bash
# rca-stack.sh detect: one fixture per stack id, make-wins-over-npm, xcode needs
# scheme, pnpm-vs-npm lockfile discrimination, and the empty (none) case.
source "$(dirname "$0")/lib.sh"

# in a fresh dir populated by the given commands, echo the detect JSON.
detect_in() {
  local d; d="$(mktmp)"
  ( cd "$d" && eval "$1" ) >/dev/null 2>&1
  bash "$STACK" detect --dir "$d"
}

# swift-pm
out=$(detect_in 'touch Package.swift')
assert_eq "$(jqf "$out" '.primary')" "swift-pm" "swift-pm primary"
assert_eq "$(jqf "$out" '.stacks[0].test_cmd')" "swift test" "swift-pm test_cmd"
assert_eq "$(jqf "$out" '.stacks[0].single_test_cmd_template')" "swift test --filter {test}" "swift-pm single template"

# xcode (no Package.swift) needs a scheme
out=$(detect_in 'mkdir App.xcodeproj')
assert_eq "$(jqf "$out" '.primary')" "xcode" "xcode primary"
assert_eq "$(jqf "$out" '.stacks[0].test_cmd')" "null" "xcode test_cmd null"
assert_json "$out" '.stacks[0].needs == ["scheme"]' "xcode needs scheme"

# Package.swift beside an xcodeproj → swift-pm wins (xcode is elif)
out=$(detect_in 'touch Package.swift; mkdir App.xcodeproj')
assert_eq "$(jqf "$out" '.primary')" "swift-pm" "Package.swift beats xcodeproj"
assert_json "$out" '[.stacks[].id] | index("xcode") == null' "no xcode stack when Package.swift present"

# cargo
out=$(detect_in 'touch Cargo.toml')
assert_eq "$(jqf "$out" '.primary')" "cargo" "cargo primary"
assert_eq "$(jqf "$out" '.stacks[0].single_test_cmd_template')" "cargo test {test}" "cargo single template"

# npm (package.json, no pnpm lock)
out=$(detect_in 'printf "{}" > package.json')
assert_eq "$(jqf "$out" '.primary')" "npm" "npm primary"
assert_eq "$(jqf "$out" '.stacks[0].setup_cmd')" "npm ci" "npm setup_cmd"

# pnpm (pnpm-lock.yaml present)
out=$(detect_in 'printf "{}" > package.json; touch pnpm-lock.yaml')
assert_eq "$(jqf "$out" '.primary')" "pnpm" "pnpm primary"
assert_eq "$(jqf "$out" '.stacks[0].setup_cmd')" "pnpm install --frozen-lockfile" "pnpm setup_cmd"
assert_json "$out" '[.stacks[].id] | index("npm") == null' "pnpm excludes npm"

# pytest via pytest.ini
out=$(detect_in 'touch pytest.ini')
assert_eq "$(jqf "$out" '.primary')" "pytest" "pytest via pytest.ini"
# pytest via pyproject [tool.pytest]
out=$(detect_in 'printf "[tool.pytest.ini_options]\n" > pyproject.toml')
assert_eq "$(jqf "$out" '.primary')" "pytest" "pytest via pyproject [tool.pytest]"
# pytest via tests/*.py
out=$(detect_in 'mkdir tests; touch tests/test_x.py')
assert_eq "$(jqf "$out" '.primary')" "pytest" "pytest via tests/*.py"

# bats under tests/
out=$(detect_in 'mkdir tests; touch tests/x.bats')
assert_eq "$(jqf "$out" '.stacks[0].id')" "bats" "bats detected"
assert_eq "$(jqf "$out" '.stacks[0].test_cmd')" "bats tests" "bats test_cmd targets the dir"

# make wins as primary over npm
out=$(detect_in 'printf "test:\n\techo hi\n" > Makefile; printf "{}" > package.json')
assert_eq "$(jqf "$out" '.primary')" "make" "make wins over npm"
assert_eq "$(jqf "$out" '.confidence')" "high" "make → high confidence"
assert_json "$out" '[.stacks[].id] | index("npm") != null' "npm still listed as a stack"

# Makefile without a test: target → not a make stack
out=$(detect_in 'printf "build:\n\techo hi\n" > Makefile')
assert_json "$out" '[.stacks[].id] | index("make") == null' "Makefile w/o test: is not a make stack"

# multiple non-make stacks → medium confidence
out=$(detect_in 'touch Cargo.toml; printf "{}" > package.json')
assert_eq "$(jqf "$out" '.confidence')" "medium" "two non-make stacks → medium"

# none
out=$(detect_in 'touch nothing.txt')
assert_json "$out" '.ok == true and .primary == null and .confidence == "none" and (.stacks|length==0)' "no markers → none (ok:true)"

finish
