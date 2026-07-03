#!/usr/bin/env bats
# Tests for forge-predecessor-diff.sh — mechanical predecessor-diff
# truncation for just-in-time generator context (F033).
#
# Mock-free: drives real git in a throwaway /tmp repo (see CLAUDE.md).

SCRIPT="$BATS_TEST_DIRNAME/forge-predecessor-diff.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  ( cd "$TEST_DIR" && git init -q . && git config user.email t@t.com && git config user.name t )
}

teardown() {
  rm -rf "$TEST_DIR"
}

jq_field() {
  echo "$output" | jq -r "$1"
}

commit_story() {
  # commit_story <story-id> <file> <content>
  echo "$3" > "$TEST_DIR/$2"
  ( cd "$TEST_DIR" && git add -A && git commit -q -m "feat($1): change $2" )
}

# --- Environment guards ---

@test "not a git repo: ok=false, does not crash" {
  local nogit
  nogit="$(mktemp -d)"
  run bash "$SCRIPT" --project-dir "$nogit"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "not_a_git_repo" ]
  rm -rf "$nogit"
}

# --- No story commits yet ---

@test "no story commits: ok=true, zero line_count, empty commits" {
  ( cd "$TEST_DIR" && echo x > x.txt && git add -A && git commit -q -m "chore: not a story commit" )
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.line_count')" = "0" ]
  [ "$(jq_field '.truncated')" = "false" ]
  [ "$(jq_field '.commits | length')" = "0" ]
}

@test "non-feat commits are not mistaken for story commits" {
  ( cd "$TEST_DIR" && echo x > x.txt && git add -A && git commit -q -m "chore: setup" )
  ( cd "$TEST_DIR" && echo y > y.txt && git add -A && git commit -q -m "docs: readme" )
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  [ "$(jq_field '.commits | length')" = "0" ]
}

# --- Single story commit ---

@test "single story commit produces its diff and is not truncated" {
  commit_story "ST-1" "a.txt" "hello"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.truncated')" = "false" ]
  [ "$(jq_field '.commits | length')" = "1" ]
  [ "$(jq_field '.commits[0].subject')" = "feat(ST-1): change a.txt" ]
  [[ "$(jq_field '.diff')" == *"a.txt"* ]]
  [[ "$(jq_field '.diff')" == *"+hello"* ]]
}

@test "root commit (no parent) as the only story commit is handled without error" {
  commit_story "ST-1" "a.txt" "root story"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  [ "$(jq_field '.ok')" = "true" ]
  [[ "$(jq_field '.diff')" == *"root story"* ]]
}

# --- limit-stories ---

@test "limit-stories caps how many predecessor commits are considered" {
  commit_story "ST-1" "a.txt" "one"
  commit_story "ST-2" "b.txt" "two"
  commit_story "ST-3" "c.txt" "three"
  commit_story "ST-4" "d.txt" "four"
  run bash "$SCRIPT" --project-dir "$TEST_DIR" --limit-stories 2
  [ "$(jq_field '.commits | length')" = "2" ]
  [ "$(jq_field '.commits[0].subject')" = "feat(ST-4): change d.txt" ]
  [ "$(jq_field '.commits[1].subject')" = "feat(ST-3): change c.txt" ]
  # The diff should span from ST-3's parent through HEAD -- i.e. include
  # ST-3 and ST-4's changes but NOT ST-1/ST-2's.
  [[ "$(jq_field '.diff')" == *"four"* ]]
  [[ "$(jq_field '.diff')" == *"three"* ]]
  [[ "$(jq_field '.diff')" != *"two"* ]]
  [[ "$(jq_field '.diff')" != *"one"* ]]
}

@test "default limit-stories is 3" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  [ "$(jq_field '.limit_stories')" = "3" ]
}

# --- limit-lines / truncation ---

@test "default limit-lines is 5000" {
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  [ "$(jq_field '.limit_lines')" = "5000" ]
}

@test "a diff larger than limit-lines is reported truncated with an empty diff field" {
  commit_story "ST-1" "a.txt" "small change"
  run bash "$SCRIPT" --project-dir "$TEST_DIR" --limit-lines 1
  [ "$(jq_field '.truncated')" = "true" ]
  [ "$(jq_field '.diff')" = "" ]
  # line_count still reports the REAL size, even though diff was suppressed
  [ "$(jq_field '.line_count')" -gt 1 ]
  # commits are still populated so the model can summarize from them
  [ "$(jq_field '.commits | length')" = "1" ]
}

@test "a diff at or under limit-lines is not truncated and diff is populated" {
  commit_story "ST-1" "a.txt" "small"
  run bash "$SCRIPT" --project-dir "$TEST_DIR" --limit-lines 5000
  [ "$(jq_field '.truncated')" = "false" ]
  [ "$(jq_field '.diff')" != "" ]
}

# --- Output is always valid JSON ---

@test "output is always valid JSON" {
  commit_story "ST-1" "a.txt" "x"
  run bash "$SCRIPT" --project-dir "$TEST_DIR"
  echo "$output" | jq . >/dev/null
}
