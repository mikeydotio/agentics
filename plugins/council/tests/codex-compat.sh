#!/usr/bin/env bash
# Dual-host regression contract for Council Vote.
# shellcheck disable=SC2329 # Test functions are discovered dynamically below.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

fail() { printf '%s\n' "$1" >&2; return 1; }

make_agents_root() {
  local root="$1"
  mkdir -p "$root/agents" "$root/bin" "$root/references" "$root/.codex-plugin"
  : > "$root/agents/software-architect.md"
  : > "$root/bin/resolve-agent.sh"
  : > "$root/references/agent-catalog.md"
  printf '{"name":"agents"}\n' > "$root/.codex-plugin/plugin.json"
}

test_claude_skill_and_shared_protocol_are_unchanged() {
  local skill_hash references_hash
  skill_hash="$(shasum -a 256 "$PLUGIN_ROOT/claude/skills/council-vote/SKILL.md" | awk '{print $1}')"
  references_hash="$({
    find "$PLUGIN_ROOT/references" -maxdepth 1 -type f -name '*.md' -print \
      | sort \
      | xargs shasum -a 256 \
      | awk '{print $1}'
  } | shasum -a 256 | awk '{print $1}')"

  [ "$skill_hash" = "34cfa1d9e032bdde54fa8e576b8a72c1e612485ba164f131c56eb58189d9b502" ] \
    || fail "Claude Council skill changed while adding Codex support"
  [ "$references_hash" = "0bb812289eafdc3456f2b071aeb12f65218d931e526db6aa0839f50b59384425" ] \
    || fail "shared Claude Council protocol changed while adding Codex support"
}

test_codex_manifest_is_valid_and_versioned() {
  local manifest="$PLUGIN_ROOT/.codex-plugin/plugin.json"
  local version
  version="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION" | sed 's/^v//')"

  jq -e --arg version "$version" '
    .name == "council" and
    .version == $version and
    .skills == "./skills/" and
    (.description | type == "string" and length > 0) and
    .author.name == "mikeydotio" and
    .interface.displayName == "Council Vote" and
    .interface.category == "Productivity" and
    (.interface.defaultPrompt | length > 0 and length <= 3)
  ' "$manifest" >/dev/null || fail "invalid Codex Council manifest"
}

test_codex_orchestration_is_native_parallel_and_bounded() {
  local skill="$PLUGIN_ROOT/codex/skills/council-vote/SKILL.md"
  local adapter="$PLUGIN_ROOT/codex/references/orchestration.md"

  grep -q 'spawn_agent' "$adapter" || fail "Codex adapter does not spawn council members"
  grep -q 'followup_task' "$adapter" || fail "Codex adapter does not preserve member identities"
  grep -q 'wait_agent' "$adapter" || fail "Codex adapter does not collect member results"
  grep -q 'interrupt_agent' "$adapter" || fail "Codex adapter cannot clean up a partial panel"
  grep -q 'Start all three' "$adapter" || fail "Codex adapter does not require parallel start"
  grep -q 'exactly one retry' "$adapter" || fail "Codex malformed-response retry is not bounded"
  grep -q 'ABORT.md' "$adapter" || fail "Codex adapter lacks an auditable abort path"
  grep -qi 'do not spawn further agents' "$adapter" || fail "Council members can recurse"
  grep -q 'resolve-agents-root.sh' "$skill" || fail "Codex skill does not resolve the Agents dependency"
  grep -q 'full canonical role' "$skill" || fail "Codex skill does not inject canonical roles"

  ! grep -Eq 'CLAUDE_PLUGIN_ROOT|subagent_type|run_in_background|(^|[^a-z_])Agent\(' "$skill" "$adapter" \
    || fail "Claude-only orchestration leaked into the Codex path"
  ! grep -Eq '^(argument-hint|model|effort):' "$skill" \
    || fail "Claude-only frontmatter leaked into the Codex skill"
}

test_host_dispatcher_routes_without_combining_hosts() {
  local dispatcher="$PLUGIN_ROOT/skills/council-vote/SKILL.md"
  grep -q 'HOST_DISPATCH_VERSION: 1' "$dispatcher" || fail "missing Council host dispatcher"
  grep -q '<plugin-root>/claude/skills/council-vote/SKILL.md' "$dispatcher" \
    || fail "dispatcher does not route Claude"
  grep -q '<plugin-root>/codex/skills/council-vote/SKILL.md' "$dispatcher" \
    || fail "dispatcher does not route Codex"
  grep -qi 'ambiguous' "$dispatcher" || fail "dispatcher does not reject ambiguous hosts"
}

test_agents_resolver_supports_checkout_cache_and_registry() {
  local resolver="$PLUGIN_ROOT/bin/resolve-agents-root.sh"
  local expected resolved fixture cache_agents registry_agents fake_bin fixture_council

  expected="$(cd "$PLUGIN_ROOT/../agents" && pwd)"
  resolved="$(bash "$resolver")" || fail "checkout sibling Agents plugin did not resolve"
  [ "$resolved" = "$expected" ] || fail "checkout Agents plugin resolved to the wrong root"

  fixture="$(mktemp -d)"
  # Expand the local now so the EXIT trap remains valid after this function returns.
  # shellcheck disable=SC2064
  trap "rm -rf '$fixture'" EXIT
  fixture_council="$fixture/council"
  mkdir -p "$fixture_council/bin"
  cp "$resolver" "$fixture_council/bin/resolve-agents-root.sh"

  cache_agents="$fixture/codex-home/plugins/cache/team/agents/9.9.9"
  make_agents_root "$cache_agents"
  cache_agents="$(cd "$cache_agents" && pwd -P)"
  resolved="$(CODEX_HOME="$fixture/codex-home" PATH="/usr/bin:/bin" bash "$fixture_council/bin/resolve-agents-root.sh")" \
    || fail "cached Agents plugin did not resolve"
  [ "$resolved" = "$cache_agents" ] || fail "cached Agents plugin resolved to the wrong root"

  rm -rf "$fixture/codex-home"
  registry_agents="$fixture/registry-agents"
  make_agents_root "$registry_agents"
  registry_agents="$(cd "$registry_agents" && pwd -P)"
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  # The generated fixture script must expand FAKE_AGENTS_PATH when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'jq -n --arg path "$FAKE_AGENTS_PATH" '\''{installed:[{name:"agents",installed:true,enabled:true,source:{source:"local",path:$path}}]}'\'' ' \
    > "$fake_bin/codex"
  chmod +x "$fake_bin/codex"
  resolved="$(FAKE_AGENTS_PATH="$registry_agents" CODEX_HOME="$fixture/codex-home" PATH="$fake_bin:$PATH" bash "$fixture_council/bin/resolve-agents-root.sh")" \
    || fail "registry Agents plugin did not resolve"
  [ "$resolved" = "$registry_agents" ] || fail "registry Agents plugin resolved to the wrong root"
}

command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq is required\n' >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()
printf '%s\n' '=== council-codex-compat ==='
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
