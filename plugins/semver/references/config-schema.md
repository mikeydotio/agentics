# Config Schema: .semver/config.yaml

The semver plugin stores per-project configuration in `.semver/config.yaml` at the project root. All values are single-line scalars — no nested objects, no multi-line values.

## Schema

```yaml
# Master switch — enables/disables all semver features
tracking: true

# Auto-bump sub-feature (requires tracking: true)
auto_bump: false

# When auto-bump fires, ask user to confirm before bumping
# true = propose and wait for approval
# false = analyze and execute immediately
auto_bump_confirm: true

# Version string prefix: "" for bare numbers (1.2.3), "v" for prefixed (v1.2.3)
# Applied to VERSION file content and git tags (when enabled)
version_prefix: "v"

# Git tagging: create git tags on version bumps
# true = create tags (default), false = skip tagging (commit-only bumps)
git_tagging: true

# Changelog format:
# "grouped" = entries organized by type (Added, Fixed, Changed, etc.)
# "flat" = linear bullet list of changes
changelog_format: "grouped"

# Branch that triggers auto-bump / nudge hooks
target_branch: "main"
```

## Defaults

| Field | Type | Default | Values |
|-------|------|---------|--------|
| `tracking` | bool | `true` | `true`, `false` |
| `auto_bump` | bool | `false` | `true`, `false` |
| `auto_bump_confirm` | bool | `true` | `true`, `false` |
| `version_prefix` | string | `"v"` | `""`, `"v"` |
| `git_tagging` | bool | `true` | `true`, `false` |
| `changelog_format` | string | `"grouped"` | `"grouped"`, `"flat"` |
| `target_branch` | string | `"main"` | any branch name |

## Example

```yaml
tracking: true
auto_bump: true
auto_bump_confirm: true
version_prefix: "v"
git_tagging: true
changelog_format: "grouped"
target_branch: "main"
```

## Reading Config in Bash (Hook Scripts)

The config is intentionally flat so hook scripts can parse it with grep/sed without requiring `yq`:

```bash
get_config() {
  local key="$1" default="$2" config_file="$3"
  local val
  val=$(grep "^${key}:" "$config_file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | tr -d "'\"")
  printf '%s' "${val:-$default}"
}

# Usage
TRACKING="$(get_config 'tracking' 'false' "$CONFIG_FILE")"
```

## Writing Config in the Skill

When the skill creates or updates config, it must:
1. Write all fields (never partial writes)
2. Use the exact field names above
3. Keep values on single lines with no trailing whitespace
4. Not add comments (they may interfere with grep-based parsing in hooks)

## When Config Is Read

- **SessionStart hook**: reads `tracking` to decide whether to inject version context
- **PostToolUse hook**: reads all fields to decide nudge vs auto-bump behavior
- **SKILL.md commands**: read relevant fields for each operation
