#!/usr/bin/env bash
# run-user-hooks.sh — Execute user-defined pre-bump or post-bump hook scripts
#
# Usage: run-user-hooks.sh <phase> <bump_type> <old_version> <new_version> <project_dir>
#   phase:       "pre-bump" or "post-bump"
#   bump_type:   "major", "minor", or "patch"
#   old_version: current version string (e.g., "v1.2.3")
#   new_version: computed new version string (e.g., "v1.3.0")
#   project_dir: absolute path to the project root
#
# Exit codes:
#   0 — success (or no hooks found)
#   1 — a pre-bump hook script failed (post-bump failures return 0 with warnings)
#   2 — re-entrancy guard detected (bump already in progress)
#
# Stdout: single JSON object with results
# Hook script output is captured separately and included in the JSON.

set -uo pipefail

# --- Arguments ---

PHASE="${1:-}"
BUMP_TYPE="${2:-}"
OLD_VERSION="${3:-}"
NEW_VERSION="${4:-}"
PROJECT_DIR="${5:-}"

if [ -z "$PHASE" ] || [ -z "$BUMP_TYPE" ] || [ -z "$OLD_VERSION" ] || [ -z "$NEW_VERSION" ] || [ -z "$PROJECT_DIR" ]; then
    echo '{"status":"error","message":"Usage: run-user-hooks.sh <phase> <bump_type> <old_version> <new_version> <project_dir>"}' >&1
    exit 1
fi

if [ "$PHASE" != "pre-bump" ] && [ "$PHASE" != "post-bump" ]; then
    echo '{"status":"error","message":"Phase must be pre-bump or post-bump"}' >&1
    exit 1
fi

# --- Re-entrancy Guard ---

if [ "${SEMVER_BUMP_IN_PROGRESS:-}" = "1" ]; then
    jq -n '{status:"blocked",reason:"re-entrancy guard: a bump is already in progress"}' >&1
    exit 2
fi

# --- Directory Check ---

HOOKS_DIR="${PROJECT_DIR}/.semver/hooks/${PHASE}"

if [ ! -d "$HOOKS_DIR" ]; then
    jq -n '{status:"ok",hooks_run:0,prompt_hook:null,warnings:[]}' >&1
    exit 0
fi

# --- PROMPT_HOOK.md ---

PROMPT_HOOK_FILE="${HOOKS_DIR}/PROMPT_HOOK.md"
PROMPT_HOOK_CONTENT="null"

if [ -f "$PROMPT_HOOK_FILE" ]; then
    PROMPT_HOOK_CONTENT=$(jq -Rs '.' "$PROMPT_HOOK_FILE")
fi

# --- Discover Scripts ---

export LC_COLLATE=C

SCRIPTS=()
for f in "$HOOKS_DIR"/*.sh; do
    [ -f "$f" ] || continue        # handle empty glob
    [ -x "$f" ] || continue        # skip non-executable
    SCRIPTS+=("$f")
done

# Sort (already sorted by glob with LC_COLLATE=C, but be explicit)
IFS=$'\n' SCRIPTS=($(printf '%s\n' "${SCRIPTS[@]}" | sort)); unset IFS

if [ ${#SCRIPTS[@]} -eq 0 ] && [ "$PROMPT_HOOK_CONTENT" = "null" ]; then
    jq -n '{status:"ok",hooks_run:0,prompt_hook:null,warnings:[]}' >&1
    exit 0
fi

if [ ${#SCRIPTS[@]} -eq 0 ]; then
    jq -n --argjson prompt "$PROMPT_HOOK_CONTENT" \
        '{status:"ok",hooks_run:0,prompt_hook:$prompt,warnings:[]}' >&1
    exit 0
fi

# --- Execute Scripts ---

HOOKS_RUN=0
WARNINGS='[]'
HOOK_OUTPUT=""
FAILED_HOOK=""
FAILED_EXIT_CODE=0

for script in "${SCRIPTS[@]}"; do
    SCRIPT_NAME=$(basename "$script")
    OUTPUT_FILE=$(mktemp)

    # Run script with env vars, capturing output
    set +e
    SEMVER_BUMP_IN_PROGRESS=1 \
    BUMP_TYPE="$BUMP_TYPE" \
    OLD_VERSION="$OLD_VERSION" \
    NEW_VERSION="$NEW_VERSION" \
    bash "$script" > "$OUTPUT_FILE" 2>&1
    EXIT_CODE=$?
    set -e

    SCRIPT_OUTPUT=$(cat "$OUTPUT_FILE")
    rm -f "$OUTPUT_FILE"

    HOOKS_RUN=$((HOOKS_RUN + 1))

    if [ $EXIT_CODE -ne 0 ]; then
        if [ "$PHASE" = "pre-bump" ]; then
            # Pre-bump: abort on first failure
            HOOK_OUTPUT="$SCRIPT_OUTPUT"
            FAILED_HOOK="$SCRIPT_NAME"
            FAILED_EXIT_CODE=$EXIT_CODE
            break
        else
            # Post-bump: warn and continue
            WARNING=$(jq -n \
                --arg hook "$SCRIPT_NAME" \
                --arg code "$EXIT_CODE" \
                --arg output "$SCRIPT_OUTPUT" \
                '{hook:$hook,exit_code:($code|tonumber),output:$output}')
            WARNINGS=$(echo "$WARNINGS" | jq --argjson w "$WARNING" '. + [$w]')
        fi
    fi

    # Accumulate output
    if [ -n "$SCRIPT_OUTPUT" ]; then
        if [ -n "$HOOK_OUTPUT" ]; then
            HOOK_OUTPUT="${HOOK_OUTPUT}\n${SCRIPT_OUTPUT}"
        else
            HOOK_OUTPUT="$SCRIPT_OUTPUT"
        fi
    fi
done

# --- Build Result ---

if [ -n "$FAILED_HOOK" ]; then
    # Pre-bump failure
    jq -n \
        --arg status "failed" \
        --arg hook "$FAILED_HOOK" \
        --arg code "$FAILED_EXIT_CODE" \
        --arg output "$HOOK_OUTPUT" \
        --argjson hooks_run "$HOOKS_RUN" \
        --argjson prompt "$PROMPT_HOOK_CONTENT" \
        '{
            status: $status,
            hooks_run: $hooks_run,
            failed_hook: $hook,
            exit_code: ($code|tonumber),
            output: $output,
            prompt_hook: $prompt,
            warnings: []
        }' >&1
    exit 1
fi

# Success (possibly with post-bump warnings)
jq -n \
    --argjson hooks_run "$HOOKS_RUN" \
    --argjson prompt "$PROMPT_HOOK_CONTENT" \
    --argjson warnings "$WARNINGS" \
    --arg output "$HOOK_OUTPUT" \
    '{
        status: "ok",
        hooks_run: $hooks_run,
        prompt_hook: $prompt,
        warnings: $warnings,
        output: $output
    }' >&1
exit 0
