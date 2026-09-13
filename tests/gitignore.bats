#!/usr/bin/env bats
# Exercise the repository ignore policy through real Git status and staging.

setup() {
  local variable
  for variable in ${!GIT_@}; do
    unset "$variable"
  done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  FIXTURE=$(mktemp -d /private/tmp/agentics-ignore.XXXXXX)
  cp "$BATS_TEST_DIRNAME/../.gitignore" "$FIXTURE/.gitignore"
  git init --quiet --template= "$FIXTURE"
  cd "$FIXTURE" || return
  git config core.excludesFile /dev/null
  git add .gitignore
  mkdir .claude
  printf '%s\n' '{"protocol_version":2,"session_id":"fixture"}' \
    > .claude/dispatch-sentinel.json
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "dispatch witness remains on disk without dirtying status or entering the index" {
  run git status --porcelain --untracked-files=all -- .claude
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  git add --all
  run git ls-files -- .claude/dispatch-sentinel.json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -s .claude/dispatch-sentinel.json ]
}

@test "dispatch exclusion preserves sibling configuration and nested project files" {
  mkdir -p nested/.claude
  printf '{}\n' > .claude/settings.json
  printf '{}\n' > .claude/dispatch-sentinel.json.example
  printf '{}\n' > nested/.claude/dispatch-sentinel.json

  run git status --porcelain --untracked-files=all -- \
    .claude/settings.json .claude/dispatch-sentinel.json.example nested
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]

  git add --all
  run git ls-files -- .claude/settings.json \
    .claude/dispatch-sentinel.json.example nested/.claude/dispatch-sentinel.json
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}
