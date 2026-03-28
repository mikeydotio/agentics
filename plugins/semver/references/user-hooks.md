# User-Defined Hooks

Custom scripts and AI instructions that run automatically before and after version bumps.

## Directory Structure

```
.semver/hooks/
├── pre-bump/
│   ├── PROMPT_HOOK.md          # AI agent instructions (optional)
│   ├── 01-run-tests.sh         # Runs before VERSION is updated
│   └── 02-lint-check.sh        # Alphabetical order by filename
└── post-bump/
    ├── PROMPT_HOOK.md          # AI agent instructions (optional)
    ├── 01-sync-package-json.sh # Runs after commit + tag
    └── 02-notify.sh
```

Hooks are **optional**. If `.semver/hooks/` does not exist, the bump proceeds normally with no overhead.

## Script Hook Contract

### Environment Variables

Every hook script receives these environment variables:

| Variable | Example | Description |
|----------|---------|-------------|
| `BUMP_TYPE` | `minor` | The bump level: `major`, `minor`, or `patch` |
| `OLD_VERSION` | `v1.2.3` | The current version before the bump (includes prefix) |
| `NEW_VERSION` | `v1.3.0` | The computed new version after the bump (includes prefix) |
| `SEMVER_BUMP_IN_PROGRESS` | `1` | Re-entrancy guard — always `1` during hook execution |

### Working Directory

Scripts run from the **project root** (the directory containing `.semver/`).

### Exit Codes

**Pre-bump scripts:**
- Exit `0` → continue to the next hook, then proceed with the bump
- Exit non-zero → **abort the entire bump**. VERSION and CHANGELOG are not modified. The failing script's name and exit code are reported.

**Post-bump scripts:**
- Exit `0` → continue to the next hook
- Exit non-zero → **warn but do not roll back**. The version bump has already been committed and tagged. A warning is reported with the failing script's name and exit code.

### Execution Order

Scripts are discovered as `*.sh` files in the phase directory and sorted alphabetically using `LC_COLLATE=C` (ASCII byte order). Use numeric prefixes for deterministic ordering:

```
01-validate.sh    ← runs first
02-test.sh        ← runs second
10-build.sh       ← runs third
```

### What Gets Executed

- Only files matching `*.sh` that are **executable** (`chmod +x`)
- `PROMPT_HOOK.md` is never executed as a script — it is read by the AI agent separately
- Non-`.sh` files (README.md, .txt, etc.) are ignored
- Non-executable `.sh` files are skipped

## AI Prompt Hooks (PROMPT_HOOK.md)

`PROMPT_HOOK.md` is a markdown file containing instructions for the AI agent executing the bump. Claude reads the file and follows its instructions inline during the bump flow.

### Available Context

When following PROMPT_HOOK.md instructions, the AI agent knows:
- `BUMP_TYPE` — the bump level (major/minor/patch)
- `OLD_VERSION` — the current version before the bump
- `NEW_VERSION` — the computed new version

Reference these in your instructions as prose (e.g., "If this is a major bump..."), not as shell variables.

### Timing

- **Pre-bump PROMPT_HOOK.md** is read **before** shell scripts run and **before** VERSION is modified. The AI can signal an abort if it finds a blocking issue.
- **Post-bump PROMPT_HOOK.md** is read **after** shell scripts run and **after** the commit and tag exist.

### Constraints

PROMPT_HOOK.md instructions **MUST NOT**:
- Trigger `/semver bump` or any version bump — this causes infinite recursion
- Modify the `VERSION` file directly — the bump flow handles this
- Modify `CHANGELOG.md` directly — the bump flow handles this
- Modify `.semver/config.yaml` — this could corrupt the bump state

PROMPT_HOOK.md instructions **SHOULD**:
- Complete in a bounded scope — avoid open-ended tasks
- Be specific about what actions to take
- Be idempotent when possible

## Re-entrancy Guard

The environment variable `SEMVER_BUMP_IN_PROGRESS=1` is set before any hooks execute and remains set through the entire bump flow. This prevents infinite loops:

**In shell scripts:** The hook runner checks this variable before executing. If a script somehow triggers another bump attempt, the runner will block it.

```bash
# Example: checking the guard in a script that might trigger builds
if [ "${SEMVER_BUMP_IN_PROGRESS:-}" = "1" ]; then
    echo "Skipping version-dependent action: bump already in progress"
    exit 0
fi
```

**In AI instructions:** The SKILL.md bump flow checks this guard as its very first step. If Claude is instructed by a PROMPT_HOOK.md to run `/semver bump`, the guard will block it.

## Sample Hooks

### pre-bump/01-run-tests.sh

Runs the project test suite before allowing a version bump. Aborts the bump if tests fail.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[pre-bump] Running test suite before $BUMP_TYPE bump ($OLD_VERSION → $NEW_VERSION)..."

if [ -f "package.json" ]; then
    npm test
elif [ -f "Cargo.toml" ]; then
    cargo test
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    python -m pytest
else
    echo "[pre-bump] No recognized test runner found — skipping"
    exit 0
fi

echo "[pre-bump] Tests passed."
```

### pre-bump/02-lint-check.sh

Runs a linter to ensure code quality before bumping.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[pre-bump] Running lint check..."

if [ -f "package.json" ]; then
    npx eslint . --quiet 2>/dev/null || {
        echo "[pre-bump] Lint errors found. Fix them before bumping."
        exit 1
    }
fi

echo "[pre-bump] Lint check passed."
```

### post-bump/01-sync-package-json.sh

Syncs the new version into package.json after a bump.

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "package.json" ]; then
    exit 0
fi

# Strip version prefix (e.g., "v1.2.3" → "1.2.3")
BARE_VERSION="${NEW_VERSION#v}"

echo "[post-bump] Syncing version $BARE_VERSION to package.json..."

# Use jq if available, otherwise sed
if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --arg v "$BARE_VERSION" '.version = $v' package.json > "$tmp" && mv "$tmp" package.json
else
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$BARE_VERSION\"/" package.json
fi

git add package.json
git commit --amend --no-edit

echo "[post-bump] package.json updated to $BARE_VERSION."
```

### post-bump/02-notify-webhook.sh

Posts a notification to a webhook after a successful bump.

```bash
#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL="${SEMVER_WEBHOOK_URL:-}"
if [ -z "$WEBHOOK_URL" ]; then
    echo "[post-bump] No SEMVER_WEBHOOK_URL set — skipping notification"
    exit 0
fi

echo "[post-bump] Notifying webhook of $NEW_VERSION release..."

curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"version\":\"$NEW_VERSION\",\"previous\":\"$OLD_VERSION\",\"bump_type\":\"$BUMP_TYPE\"}" \
    || echo "[post-bump] Warning: webhook notification failed (non-fatal)"
```

### pre-bump/PROMPT_HOOK.md

```markdown
# Pre-Bump Review

Before proceeding with the version bump:

1. If this is a **major** bump, review the git diff since the last tag for breaking API changes.
   Summarize what is breaking and confirm with the user that these breaking changes are intentional.

2. If this is a **minor** bump, briefly list the new features being included.

3. For all bump types, check if README.md mentions a version number that should be updated
   after the bump completes.
```

### post-bump/PROMPT_HOOK.md

```markdown
# Post-Bump Actions

After the version bump has been committed and tagged:

1. If a README.md exists and contains version badges or version references,
   update them to reflect the new version.

2. Summarize the changelog entry that was generated and suggest whether
   a GitHub release should be drafted.
```

## Creating Hooks

### By Asking Claude

Simply tell Claude what you want:
- "Add a pre-bump hook that runs our test suite"
- "I want a post-bump hook that updates package.json"
- "Set up a PROMPT_HOOK that reviews breaking changes before major bumps"

Claude will create the directory structure, write the script, set permissions, and commit.

### Manually

```bash
# Create the hook directories
mkdir -p .semver/hooks/pre-bump .semver/hooks/post-bump

# Write a hook script
cat > .semver/hooks/pre-bump/01-my-check.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Running pre-bump check for $BUMP_TYPE bump ($OLD_VERSION → $NEW_VERSION)"
# Your logic here
EOF

# Make it executable
chmod +x .semver/hooks/pre-bump/01-my-check.sh

# Commit
git add .semver/hooks/
git commit -m "chore: add pre-bump hook"
```

## Troubleshooting

**Hook not running?**
- Check it has execute permission: `ls -la .semver/hooks/pre-bump/`
- Ensure it ends with `.sh`
- Verify `.semver/hooks/pre-bump/` (or `post-bump/`) directory exists

**Hooks running in wrong order?**
- Use zero-padded numeric prefixes: `01-`, `02-`, `10-`
- Sorting is byte-order (ASCII), not natural/numeric — `10` sorts after `09` but before `2`

**Infinite loop or re-entrancy error?**
- A hook script or PROMPT_HOOK.md is triggering `/semver bump`
- Check the `SEMVER_BUMP_IN_PROGRESS` guard in your scripts
- Review PROMPT_HOOK.md for instructions that could cause Claude to bump again

**Post-bump hook failed?**
- The version bump is already committed and tagged — it will NOT be rolled back
- Fix the hook script and re-run it manually, or address the issue in a follow-up commit

**Hook output not visible?**
- Script stdout/stderr is captured and reported to the user after execution
- Keep output concise — long output may be truncated
