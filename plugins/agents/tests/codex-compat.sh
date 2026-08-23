#!/usr/bin/env bash
# Dual-host regression contract for the shared Agents plugin.
# shellcheck disable=SC2329 # Test functions are discovered dynamically below.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

fail() { printf '%s\n' "$1" >&2; return 1; }

test_codex_manifest_is_valid_and_versioned() {
  local manifest="$PLUGIN_ROOT/.codex-plugin/plugin.json"
  local version
  version="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION" | sed 's/^v//')"

  jq -e --arg version "$version" '
    .name == "agents" and
    .version == $version and
    .skills == "./skills/" and
    (.description | type == "string" and length > 0) and
    .author.name == "mikeydotio" and
    .interface.displayName == "Agents" and
    .interface.category == "Productivity" and
    (.interface.defaultPrompt | length > 0 and length <= 3)
  ' "$manifest" >/dev/null || fail "invalid Codex manifest"
}

test_claude_skill_and_agent_definitions_are_unchanged() {
  local skill_hash definitions_hash
  skill_hash="$(shasum -a 256 "$PLUGIN_ROOT/claude/skills/agents/SKILL.md" | awk '{print $1}')"
  definitions_hash="$({
    find "$PLUGIN_ROOT/agents" -maxdepth 1 -type f -name '*.md' -print \
      | sort \
      | xargs shasum -a 256 \
      | awk '{print $1}'
  } | shasum -a 256 | awk '{print $1}')"

  [ "$skill_hash" = "fec709d92e2a7c8489cb0f9893fcabb59642519f33988a7433d5dbd26ab10fa4" ] \
    || fail "Claude skill changed while adding Codex support"
  [ "$definitions_hash" = "3d4219c5157d680d30faf53f0f8a186342070507336f742ad85c5b8358748c8e" ] \
    || fail "canonical Claude agent definitions changed while adding Codex support"
}

test_root_skill_routes_hosts_without_implementing_either() {
  local dispatcher="$PLUGIN_ROOT/skills/agents/SKILL.md"
  grep -q 'HOST_DISPATCH_VERSION: 1' "$dispatcher" || fail "missing host dispatcher marker"
  grep -q '<plugin-root>/claude/skills/agents/SKILL.md' "$dispatcher" \
    || fail "dispatcher does not route Claude"
  grep -q '<plugin-root>/codex/skills/agents/SKILL.md' "$dispatcher" \
    || fail "dispatcher does not route Codex"
  grep -qi 'ambiguous' "$dispatcher" || fail "dispatcher does not reject ambiguous hosts"
  ! grep -Eq '^(argument-hint|model|effort):' "$dispatcher" \
    || fail "host-specific metadata leaked into the shared dispatcher"
}

test_codex_skill_uses_native_spawn_and_installed_paths() {
  local skill="$PLUGIN_ROOT/codex/skills/agents/SKILL.md"
  grep -q 'Codex interaction contract' "$skill" || fail "missing Codex interaction contract"
  grep -q '<plugin-root>' "$skill" || fail "Codex skill does not resolve its installed root"
  # shellcheck disable=SC2016 # The dollar sign is literal Codex invocation syntax.
  grep -q '\$agents:agents run <name> <task>' "$skill" || fail "missing Codex run command"
  grep -q 'spawn_agent' "$skill" || fail "Codex run path does not use native spawn_agent"
  grep -q 'wait_agent' "$skill" || fail "Codex run path does not collect the spawned role"
  grep -q 'prompt-enforced' "$skill" || fail "Codex tool-policy limitation is not disclosed"
  grep -q 'inherit' "$skill" || fail "Codex model inheritance is not explicit"

  ! grep -Eq 'CLAUDE_PLUGIN_ROOT|subagent_type|(^|[^a-z_])Agent\(' "$skill" \
    || fail "Claude-only runtime syntax leaked into the Codex skill"
  ! grep -Eq '^model:[[:space:]]*(haiku|sonnet|opus)|reasoning_effort:' "$skill" \
    || fail "Codex skill pins a Claude model or a reasoning override"
}

test_role_resolver_accepts_catalog_names_and_rejects_paths() {
  local resolver="$PLUGIN_ROOT/bin/resolve-agent.sh"
  local resolved roster_count definition_count

  resolved="$(bash "$resolver" software-engineer)" || fail "known role did not resolve"
  [ "$resolved" = "$PLUGIN_ROOT/agents/software-engineer.md" ] \
    || fail "known role resolved outside the canonical catalog"

  if bash "$resolver" ../software-engineer >/dev/null 2>&1; then
    fail "path traversal was accepted as a role name"
  fi
  if bash "$resolver" missing-role >/dev/null 2>&1; then
    fail "missing role was accepted"
  fi

  roster_count="$(bash "$resolver" --list | wc -l | tr -d ' ')" || fail "role list failed"
  definition_count="$(find "$PLUGIN_ROOT/agents" -maxdepth 1 -type f -name '*.md' ! -name '_*' | wc -l | tr -d ' ')"
  [ "$roster_count" = "$definition_count" ] || fail "Codex resolver roster differs from Claude definitions"
}

command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required\n' >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()
printf '%s\n' '=== agents-codex-compat ==='
for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
  set +e
  out="$(set -e; "$fn" 2>&1)"
  ec=$?
  set -e
  if [ "$ec" -eq 0 ]; then
    printf '  PASS  %s\n' "$fn"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$fn"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/        /'
    FAIL=$((FAIL + 1))
    FAILURES+=("$fn")
  fi
done

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
fi
exit "$FAIL"
