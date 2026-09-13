#!/usr/bin/env bats
# Exercise configuration through production entrypoints in isolated homes.

setup() {
  FIXTURE="$(mktemp -d /tmp/age52-config.XXXXXX)"
  ROOT="$FIXTURE/plugin with spaces"
  mkdir -p "$ROOT" "$FIXTURE/home"
  cp -R "$BATS_TEST_DIRNAME/../hooks" "$BATS_TEST_DIRNAME/../references" "$ROOT/"
  [ ! -d "$BATS_TEST_DIRNAME/../lib" ] || cp -R "$BATS_TEST_DIRNAME/../lib" "$ROOT/"
  [ ! -f "$BATS_TEST_DIRNAME/../bin/greenlight-config.sh" ] || {
    mkdir -p "$ROOT/bin"
    cp "$BATS_TEST_DIRNAME/../bin/greenlight-config.sh" "$ROOT/bin/"
  }
  CONFIG="$FIXTURE/home/.config/greenlight/config.yaml"
  DEFAULTS="$ROOT/references/default-config.yaml"
}

teardown() {
  chmod -R u+rwX "$FIXTURE"
  rm -rf "$FIXTURE"
}

config() {
  run env -i HOME="$FIXTURE/home" PATH="$PATH" PLUGIN_ROOT="$ROOT" \
    bash "$ROOT/bin/greenlight-config.sh" "$@"
}

user_config() {
  mkdir -p "$(dirname "$CONFIG")"
  printf '%s\n' "$1" > "$CONFIG"
}

bundle_set() {
  sed "s|^$1:.*|$1: $2|" "$DEFAULTS" > "$FIXTURE/defaults.tmp"
  mv "$FIXTURE/defaults.tmp" "$DEFAULTS"
}

hook() {
  local data
  data="$(jq -cn --arg mode "${2:-default}" \
    '{tool_name:"Bash",tool_input:{command:"ls"},permission_mode:$mode}')"
  run env -i HOME="$FIXTURE/home" PATH="$PATH" PLUGIN_ROOT="$ROOT" \
    GREENLIGHT_PLAN_EXPLORER="${1:-0}" bash "$ROOT/hooks/greenlight.sh" <<< "$data"
}

@test "fresh hook reads defaults without creating user configuration" {
  hook
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<< "$output"
  [ ! -e "$FIXTURE/home/.config" ]
}

@test "bundle-only upgrade changes behavior next invocation; user pin wins" {
  hook
  [ "$status" -eq 0 ]
  bundle_set disabled_modes default
  hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  user_config 'disabled_modes: bypassPermissions'
  hook
  jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<< "$output"
  [ "$(cat "$CONFIG")" = 'disabled_modes: bypassPermissions' ]
}

@test "status exposes every bundled setting and explicit pins equal to defaults" {
  user_config 'ai_enabled: false'
  config status
  [ "$status" -eq 0 ]
  jq -e '.ok and (.settings|length == 15) and
    .settings.ai_enabled == {value:"false",default:"false",source:"user",pinned:true} and
    .settings.ai_model == {value:"claude-haiku-4-5",default:"claude-haiku-4-5",source:"bundled",pinned:false}' <<< "$output"
}

@test "legacy AI pins change only when explicitly unset; other overrides survive" {
  user_config $'# Keep my commands\nai_enabled: true\nai_model: claude-sonnet-4-6\nai_show_rationale: true\ncustom_allow: my-tool\nfuture_key: keep'
  cp "$CONFIG" "$FIXTURE/before"
  config get ai_model
  [ "$output" = claude-sonnet-4-6 ]
  cmp "$CONFIG" "$FIXTURE/before"
  config unset ai_enabled ai_model ai_show_rationale
  [ "$status" -eq 0 ]
  config status
  jq -e '.settings.ai_enabled.value == "false" and .settings.ai_model.source == "bundled" and
    .settings.ai_show_rationale.value == "false" and .settings.custom_allow.value == "my-tool"' <<< "$output"
  [ "$(cat "$CONFIG")" = $'# Keep my commands\ncustom_allow: my-tool\nfuture_key: keep' ]
}

@test "empty lists clear defaults; empty scalar inherits but is disclosed as pinned" {
  user_config $'disabled_modes: ""\nai_model:'
  hook 0 bypassPermissions
  jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<< "$output"
  config status
  jq -e '.settings.disabled_modes.value == "" and .settings.disabled_modes.source == "user" and
    .settings.ai_model.value == "claude-haiku-4-5" and .settings.ai_model.source == "bundled" and
    .settings.ai_model.pinned' <<< "$output"
}

@test "first set is sparse and later sets preserve comments unknown keys and literal values" {
  config set ai_enabled true
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CONFIG" | tr -d ' ')" -eq 1 ]
  printf '# retain\nfuture: literal\n' >> "$CONFIG"
  local literal='a $HOME $(touch nope) `touch nope` & "quoted" path'
  config set log_file "$literal"
  [ "$status" -eq 0 ]
  config get log_file
  [ "$output" = "$literal" ]
  grep -Fx '# retain' "$CONFIG"
  grep -Fx 'future: literal' "$CONFIG"
  config set ai_enabled false
  [ "$status" -eq 0 ]
  [ "$(grep -c '^ai_enabled:' "$CONFIG")" -eq 1 ]
  [ ! -e "$FIXTURE/nope" ]
}

@test "list mutations start from effective defaults and preserve explicit empty lists" {
  config remove disabled_modes bypassPermissions
  [ "$status" -eq 0 ]
  config get disabled_modes
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  config add disabled_modes plan
  [ "$status" -eq 0 ]
  config add disabled_modes plan
  [ "$status" -eq 0 ]
  config get disabled_modes
  [ "$output" = plan ]
  config unset disabled_modes
  [ "$status" -eq 0 ]
  config get disabled_modes
  [ "$output" = bypassPermissions ]
}

@test "reset retains exact backup and future defaults stay live; repeated reset works" {
  user_config $'# old config\nmode: strict\ncustom_allow: special'
  cp "$CONFIG" "$FIXTURE/before"
  config reset
  [ "$status" -eq 0 ]
  local backup
  backup="$(jq -r '.backup' <<< "$output")"
  [ "$backup" != "$CONFIG" ]
  cmp "$backup" "$FIXTURE/before"
  [ ! -s "$CONFIG" ]
  config reset
  [ "$status" -eq 0 ]
  bundle_set mode permissive
  config get mode
  [ "$output" = permissive ]
  cmp "$backup" "$FIXTURE/before"
}

@test "read-only status get and unset of absent key never seed a defaults snapshot" {
  config status
  [ "$status" -eq 0 ]
  config get ai_enabled
  [ "$output" = false ]
  [ ! -e "$FIXTURE/home/.config" ]
  config unset ai_model
  [ "$status" -eq 0 ]
  [ ! -e "$CONFIG" ]
}

@test "duplicate and malformed recognized settings defer normal hook and deny explorer" {
  local bad
  for bad in $'ai_enabled: false\nai_enabled: true' 'ai_enabled true' 'ai_enabled: perhaps' 'mode: [strict]' 'ai_model: "unterminated'; do
    user_config "$bad"
    cp "$CONFIG" "$FIXTURE/before"
    hook
    [ "$status" -eq 0 ]
    [[ "$output" == *'greenlight config:'* ]]
    [[ "$output" != *'"allow"'* ]]
    hook 1
    [[ "$output" == *'"deny"'* ]]
    config set mode strict
    [ "$status" -eq 1 ]
    cmp "$CONFIG" "$FIXTURE/before"
  done
}

@test "missing defaults and incomplete defaults never approve or mutate user config" {
  user_config 'mode: strict'
  rm "$DEFAULTS"
  hook
  [ "$status" -eq 0 ]
  [[ "$output" == *'greenlight config:'* ]]
  [[ "$output" != *'"allow"'* ]]
  config set mode permissive
  [ "$status" -eq 1 ]
  printf 'mode: standard\n' > "$DEFAULTS"
  config status
  [ "$status" -eq 1 ]
  [ "$(cat "$CONFIG")" = 'mode: strict' ]
}

@test "unreadable configuration fails visibly and leaves content intact" {
  user_config 'mode: strict'
  chmod 000 "$CONFIG"
  [ ! -r "$CONFIG" ]
  config status
  [ "$status" -eq 1 ]
  hook
  [[ "$output" == *'greenlight config:'* ]]
  [[ "$output" != *'"allow"'* ]]
  chmod 600 "$CONFIG"
  [ "$(cat "$CONFIG")" = 'mode: strict' ]
}

@test "writers refuse occupied lock and symlink without changing original" {
  user_config 'mode: strict'
  mkdir "$(dirname "$CONFIG")/.config.lock"
  config set mode permissive
  [ "$status" -eq 1 ]
  [[ "$output" == *'lock'* ]]
  [ "$(cat "$CONFIG")" = 'mode: strict' ]
  rmdir "$(dirname "$CONFIG")/.config.lock"
  mv "$CONFIG" "$FIXTURE/target"
  ln -s "$FIXTURE/target" "$CONFIG"
  config reset
  [ "$status" -eq 1 ]
  [ -L "$CONFIG" ]
  [ "$(cat "$FIXTURE/target")" = 'mode: strict' ]
}

@test "failed write and invalid requests preserve configuration" {
  user_config 'mode: strict'
  chmod 500 "$(dirname "$CONFIG")"
  config set mode permissive
  [ "$status" -eq 1 ]
  [ "$(cat "$CONFIG")" = 'mode: strict' ]
  chmod 700 "$(dirname "$CONFIG")"
  config set typo value
  [ "$status" -eq 2 ]
  config set ai_enabled invalid
  [ "$status" -eq 2 ]
  config add ai_model foo
  [ "$status" -eq 2 ]
  config set log_file $'line1\nline2'
  [ "$status" -eq 2 ]
  config unset mode typo
  [ "$status" -eq 2 ]
  [ "$(cat "$CONFIG")" = 'mode: strict' ]
}

@test "quoted CRLF configuration without final newline is read as literal scalar data" {
  mkdir -p "$(dirname "$CONFIG")"
  printf "mode: 'strict'\r\nai_model: \"a-model\"" > "$CONFIG"
  config get mode
  [ "$status" -eq 0 ]
  [ "$output" = strict ]
  config get ai_model
  [ "$output" = a-model ]
}

@test "inherited writer variables cannot claim or remove resources" {
  printf 'not owned\n' > "$FIXTURE/sentinel"
  run env -i HOME="$FIXTURE/home" PATH="$PATH" PLUGIN_ROOT="$ROOT" \
    GL_WRITE_TEMP="$FIXTURE/sentinel" GL_BACKUP=unowned GL_WRITE_LOCKED=true \
    bash "$ROOT/bin/greenlight-config.sh" reset
  [ "$status" -eq 0 ]
  jq -e '.ok and .backup == null' <<< "$output"
  [ "$(cat "$FIXTURE/sentinel")" = 'not owned' ]
}

@test "concurrent successful list edits are never lost and contention fails visibly" {
  local i rc successes=0
  for i in 1 2 3 4 5 6; do
    (
      if env -i HOME="$FIXTURE/home" PATH="$PATH" PLUGIN_ROOT="$ROOT" \
        bash "$ROOT/bin/greenlight-config.sh" add custom_allow "tool-$i" > "$FIXTURE/out-$i" 2> "$FIXTURE/err-$i"; then
        printf '0\n' > "$FIXTURE/rc-$i"
      else
        printf '%s\n' "$?" > "$FIXTURE/rc-$i"
      fi
    ) &
  done
  wait
  config get custom_allow
  [ "$status" -eq 0 ]
  for i in 1 2 3 4 5 6; do
    rc="$(cat "$FIXTURE/rc-$i")"
    if [[ "$rc" == 0 ]]; then
      successes=$((successes + 1))
      jq -e '.ok' "$FIXTURE/out-$i"
      [[ " $output " == *" tool-$i "* ]]
      [ ! -s "$FIXTURE/err-$i" ]
    else
      [ "$rc" -eq 1 ]
      [ ! -s "$FIXTURE/out-$i" ]
      grep -F 'cannot acquire writer lock' "$FIXTURE/err-$i"
      [[ " $output " != *" tool-$i "* ]]
    fi
  done
  [ "$successes" -gt 0 ]
  [ ! -d "$(dirname "$CONFIG")/.config.lock" ]
}
