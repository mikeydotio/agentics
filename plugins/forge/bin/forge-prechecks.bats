#!/usr/bin/env bats
# Tests for forge-prechecks.sh

SCRIPT="$BATS_TEST_DIRNAME/forge-prechecks.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  # Initialize a git repo so git diff commands work
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"

  # Initial commit so HEAD exists
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep
  git -C "$TEST_DIR" commit -q -m "init"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- Output structure ---

@test "output is valid JSON" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  echo "$output" >&2
  echo "$output" | jq . >/dev/null
}

@test "output contains ok field" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local ok
  ok="$(echo "$output" | jq -r '.ok')"
  [ "$ok" = "true" ]
}

@test "output contains all_passed field" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  echo "$output" | jq -e '.all_passed' >/dev/null
}

@test "output contains checks array with 4 items" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local count
  count="$(echo "$output" | jq '.checks | length')"
  [ "$count" -eq 4 ]
}

@test "output contains display string" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local display
  display="$(echo "$output" | jq -r '.display')"
  [[ "$display" == *"[forge] Pre-checks:"* ]]
}

# --- Test suite auto-detect ---

@test "detects npm test from package.json" {
  cat > "$TEST_DIR/package.json" <<'EOF'
{ "scripts": { "test": "echo ok" } }
EOF
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .command')"
  [ "$cmd" = "npm test" ]
}

@test "detects pytest from pytest.ini" {
  touch "$TEST_DIR/pytest.ini"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .command')"
  [ "$cmd" = "pytest" ]
}

@test "detects cargo test from Cargo.toml" {
  touch "$TEST_DIR/Cargo.toml"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .command')"
  [ "$cmd" = "cargo test" ]
}

@test "detects make test from Makefile with test target" {
  cat > "$TEST_DIR/Makefile" <<'EOF'
test:
	echo "tests pass"
EOF
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .command')"
  [ "$cmd" = "make test" ]
}

@test "detects tests/run-tests.sh" {
  mkdir -p "$TEST_DIR/tests"
  echo '#!/usr/bin/env bash' > "$TEST_DIR/tests/run-tests.sh"
  echo 'echo ok' >> "$TEST_DIR/tests/run-tests.sh"
  chmod +x "$TEST_DIR/tests/run-tests.sh"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .command')"
  [ "$cmd" = "bash tests/run-tests.sh" ]
}

@test "skips tests when no test tool found" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .passed')"
  [ "$passed" = "true" ]
  local details
  details="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .details')"
  [[ "$details" == *"skip"* ]] || [[ "$details" == *"No test"* ]]
}

# --- Linter auto-detect ---

@test "detects eslint from .eslintrc.json" {
  touch "$TEST_DIR/.eslintrc.json"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .command')"
  [ "$cmd" = "npx eslint --no-warn ." ]
}

@test "detects tsc from tsconfig.json" {
  echo '{}' > "$TEST_DIR/tsconfig.json"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .command')"
  [ "$cmd" = "npx tsc --noEmit" ]
}

@test "detects ruff from ruff.toml" {
  touch "$TEST_DIR/ruff.toml"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .command')"
  [ "$cmd" = "ruff check ." ]
}

@test "detects cargo clippy from Cargo.toml" {
  touch "$TEST_DIR/Cargo.toml"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .command')"
  [ "$cmd" = "cargo clippy" ]
}

@test "skips linter when no lint tool found" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .passed')"
  [ "$passed" = "true" ]
}

# --- Stub grep ---

@test "stub grep passes when no modified files" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep detects TODO in modified files" {
  echo "// TODO implement this" > "$TEST_DIR/src.js"
  git -C "$TEST_DIR" add src.js
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "false" ]
  local matches
  matches="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .matches | length')"
  [ "$matches" -ge 1 ]
}

@test "stub grep detects FIXME in modified files" {
  echo "# FIXME broken" > "$TEST_DIR/code.py"
  git -C "$TEST_DIR" add code.py
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "false" ]
}

@test "stub grep ignores unmodified files" {
  echo "// TODO old thing" > "$TEST_DIR/old.js"
  git -C "$TEST_DIR" add old.js
  git -C "$TEST_DIR" commit -q -m "add old file"

  # New clean file — no stubs
  echo "clean code" > "$TEST_DIR/new.js"
  git -C "$TEST_DIR" add new.js

  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep detects multiple patterns" {
  cat > "$TEST_DIR/multi.ts" <<'EOF'
// HACK workaround
throw new Error("not implemented");
// TODO: finish this
EOF
  git -C "$TEST_DIR" add multi.ts
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local count
  count="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .matches | length')"
  [ "$count" -ge 3 ]
}

@test "stub grep detects Python's NotImplementedError idiom" {
  echo 'raise NotImplementedError("finish me")' > "$TEST_DIR/code.py"
  git -C "$TEST_DIR" add code.py
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "false" ]
}

@test "stub grep detects Rust's unimplemented! macro" {
  echo 'fn f() { unimplemented!() }' > "$TEST_DIR/lib.rs"
  git -C "$TEST_DIR" add lib.rs
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "false" ]
}

@test "stub grep detects Swift's fatalError(\"not implemented\") idiom" {
  echo 'func f() { fatalError("not implemented") }' > "$TEST_DIR/File.swift"
  git -C "$TEST_DIR" add File.swift
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "false" ]
}

# --- F105 regression guard: no false positives on legitimate code ---
#
# The pre-fix pattern hard-failed on the bare substrings 'stub'/'placeholder'
# anywhere in a file — directly hostile to Mikey's domain (SwiftUI/web
# education content where form `placeholder` text is everywhere) and to any
# codebase with a real, legitimately-named `*stub*` identifier. These guard
# against ever reintroducing that over-broad match.

@test "stub grep does NOT false-positive on a SwiftUI placeholder attribute" {
  cat > "$TEST_DIR/ContentView.swift" <<'EOF'
TextField("Enter your name", text: $name)
    .placeholder(when: name.isEmpty) { Text("Enter your name") }
EOF
  git -C "$TEST_DIR" add ContentView.swift
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep does NOT false-positive on an HTML placeholder attribute" {
  echo '<input type="text" placeholder="Search…">' > "$TEST_DIR/index.html"
  git -C "$TEST_DIR" add index.html
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep does NOT false-positive on a legitimately-named *stub* function" {
  echo 'func generate_stub_data() -> [Item] { realImplementation() }' > "$TEST_DIR/Fixtures.swift"
  git -C "$TEST_DIR" add Fixtures.swift
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep does NOT false-positive on a bare XXX substring" {
  echo 'let coordinate = "XXX-42"' > "$TEST_DIR/Model.swift"
  git -C "$TEST_DIR" add Model.swift
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep does NOT false-positive on a word containing TODO as a substring (word-boundary check)" {
  echo 'import TODOISTKit // a real third-party package name, not a marker' > "$TEST_DIR/vars.swift"
  git -C "$TEST_DIR" add vars.swift
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

@test "stub grep is case-sensitive (mixed/lower case 'hack' is not the all-caps HACK marker)" {
  echo 'let hackathonProjectName = "Best Hack Idea Ever"' > "$TEST_DIR/vars2.swift"
  git -C "$TEST_DIR" add vars2.swift
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "stub_grep") | .passed')"
  [ "$passed" = "true" ]
}

# --- Scope check ---

@test "scope check skipped when no story-id" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "scope") | .passed')"
  [ "$passed" = "true" ]
  local details
  details="$(echo "$output" | jq -r '.checks[] | select(.check == "scope") | .details')"
  [[ "$details" == *"skip"* ]] || [[ "$details" == *"No story"* ]]
}

@test "scope check identifies expected files" {
  # Create plan-mapping with expected files
  cat > "$TEST_DIR/plan-mapping.json" <<'EOF'
{
  "stories": {
    "S-1": {
      "files_expected": ["src/api.ts", "src/db.ts"]
    }
  }
}
EOF
  echo "api code" > "$TEST_DIR/src_api.ts"
  # Simulate git diff returning a known file
  mkdir -p "$TEST_DIR/src"
  echo "api code" > "$TEST_DIR/src/api.ts"
  git -C "$TEST_DIR" add src/api.ts
  run bash "$SCRIPT" --project-dir "$TEST_DIR" --story-id S-1 --mapping "$TEST_DIR/plan-mapping.json"
  local expected
  expected="$(echo "$output" | jq -r '.checks[] | select(.check == "scope") | .expected_modified | length')"
  [ "$expected" -ge 1 ]
}

@test "scope check identifies unexpected files" {
  cat > "$TEST_DIR/plan-mapping.json" <<'EOF'
{
  "stories": {
    "S-1": {
      "files_expected": ["src/api.ts"]
    }
  }
}
EOF
  mkdir -p "$TEST_DIR/src"
  echo "api" > "$TEST_DIR/src/api.ts"
  echo "surprise" > "$TEST_DIR/src/surprise.ts"
  git -C "$TEST_DIR" add src/api.ts src/surprise.ts
  run bash "$SCRIPT" --project-dir "$TEST_DIR" --story-id S-1 --mapping "$TEST_DIR/plan-mapping.json"
  local unexpected
  unexpected="$(echo "$output" | jq -r '.checks[] | select(.check == "scope") | .unexpected_modified | length')"
  [ "$unexpected" -ge 1 ]
}

@test "scope check unexpected files do not fail all_passed" {
  cat > "$TEST_DIR/plan-mapping.json" <<'EOF'
{
  "stories": {
    "S-1": {
      "files_expected": ["src/api.ts"]
    }
  }
}
EOF
  mkdir -p "$TEST_DIR/src"
  echo "surprise" > "$TEST_DIR/src/surprise.ts"
  git -C "$TEST_DIR" add src/surprise.ts
  run bash "$SCRIPT" --project-dir "$TEST_DIR" --story-id S-1 --mapping "$TEST_DIR/plan-mapping.json"
  local all_passed
  all_passed="$(echo "$output" | jq -r '.all_passed')"
  [ "$all_passed" = "true" ]
}

# --- All checks run even if one fails ---

@test "all 4 checks present even when one fails" {
  echo "// TODO stub" > "$TEST_DIR/fail.js"
  git -C "$TEST_DIR" add fail.js
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local count
  count="$(echo "$output" | jq '.checks | length')"
  [ "$count" -eq 4 ]
}

@test "all_passed is false when stub grep fails" {
  echo "// TODO stub" > "$TEST_DIR/fail.js"
  git -C "$TEST_DIR" add fail.js
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local all_passed
  all_passed="$(echo "$output" | jq -r '.all_passed')"
  [ "$all_passed" = "false" ]
}

# --- Test suite pass/fail ---

@test "test check passes when test command succeeds" {
  cat > "$TEST_DIR/package.json" <<'EOF'
{ "scripts": { "test": "echo ok" } }
EOF
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .passed')"
  [ "$passed" = "true" ]
}

@test "test check fails when test command fails" {
  cat > "$TEST_DIR/package.json" <<'EOF'
{ "scripts": { "test": "exit 1" } }
EOF
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local passed
  passed="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .passed')"
  [ "$passed" = "false" ]
}

# --- display line format ---

@test "display shows PASS for passing check" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local display
  display="$(echo "$output" | jq -r '.display')"
  [[ "$display" == *"[PASS]"* ]]
}

@test "display shows FAIL for failing check" {
  echo "// TODO stub" > "$TEST_DIR/fail.js"
  git -C "$TEST_DIR" add fail.js
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local display
  display="$(echo "$output" | jq -r '.display')"
  [[ "$display" == *"[FAIL]"* ]]
}

@test "display shows SKIP for skipped check" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local display
  display="$(echo "$output" | jq -r '.display')"
  [[ "$display" == *"[SKIP]"* ]]
}

# --- pytest detection from pyproject.toml ---

@test "detects pytest from pyproject.toml with pytest section" {
  cat > "$TEST_DIR/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
testpaths = ["tests"]
EOF
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "tests") | .command')"
  [ "$cmd" = "pytest" ]
}

# --- ruff detection from pyproject.toml ---

@test "detects ruff from pyproject.toml with ruff section" {
  cat > "$TEST_DIR/pyproject.toml" <<'EOF'
[tool.ruff]
line-length = 88
EOF
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .command')"
  [ "$cmd" = "ruff check ." ]
}

# --- eslint.config.* detection ---

@test "detects eslint from eslint.config.js" {
  touch "$TEST_DIR/eslint.config.js"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  local cmd
  cmd="$(echo "$output" | jq -r '.checks[] | select(.check == "linter") | .command')"
  [ "$cmd" = "npx eslint --no-warn ." ]
}
