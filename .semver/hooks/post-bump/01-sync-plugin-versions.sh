#!/usr/bin/env bash
# 01-sync-plugin-versions.sh — One-way propagate the marketplace VERSION into the
# `version` field of the top-level .claude-plugin/marketplace.json and of every
# plugin's .claude-plugin/plugin.json.
#
# WHY: the agentics marketplace versions everything together. A change to any
# plugin bumps the single repo VERSION, and every manifest is stamped with it
# so each machine can tell at a glance whether its installed code is stale.
# Deliberately over-eager: unchanged plugins get the new version too, so a bump
# can never *miss* a manifest. VERSION is the single source of truth — manifest
# versions are derived and never read back (one-way).
#
# TWO MODES, auto-detected:
#   * Bump mode (run by /semver bump as a post-bump hook): SEMVER_BUMP_IN_PROGRESS=1
#     and NEW_VERSION are set. The post-bump hook fires AFTER semver has already
#     committed and tagged the release, so this script folds the freshly-synced
#     manifests INTO that release commit (git commit --amend) and moves the tag
#     onto the amended commit. That force-move is safe because the tag was created
#     seconds earlier in this same bump and has NOT been pushed — the opposite of
#     the post-push tag-drift hazard.
#   * Standalone mode (e.g. `bash .semver/hooks/post-bump/01-sync-plugin-versions.sh`):
#     reads the VERSION file, syncs the manifests, and stops. It touches no git
#     state, leaving the edits staged for you to commit. Use it to seed the field
#     initially or to repair drift the test guard reports.
#
# Idempotent: re-running when everything already matches is a no-op (0 updated),
# and in bump mode no amend/retag happens unless a manifest actually changed.
#
# Exit codes: 0 on success (including already-in-sync); 1 on error. As a post-bump
# hook a non-zero exit only warns — it never blocks or rolls back the release.

set -euo pipefail

# Repo root is fixed relative to this script: <root>/.semver/hooks/post-bump/<this>
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# --- Resolve the version to stamp -------------------------------------------
# Bump mode hands us NEW_VERSION (prefixed, e.g. "v2.22.0"); standalone reads the
# VERSION file. The prefixed form is the git tag name; plugin.json takes bare semver.
RAW_VERSION="${NEW_VERSION:-}"
if [ -z "$RAW_VERSION" ]; then
    if [ ! -f "$REPO_ROOT/VERSION" ]; then
        echo "sync-plugin-versions: no NEW_VERSION env and no $REPO_ROOT/VERSION" >&2
        exit 1
    fi
    RAW_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
fi

BARE_VERSION="${RAW_VERSION#v}"
if [ -z "$BARE_VERSION" ]; then
    echo "sync-plugin-versions: empty version after normalization (raw='$RAW_VERSION')" >&2
    exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "sync-plugin-versions: jq is required" >&2; exit 1; }

# --- Discover manifests ------------------------------------------------------
# The top-level marketplace.json plus every plugin.json. Both are JSON objects
# with a "name" key, which is all the jq filter below assumes.
shopt -s nullglob
manifests=()
[ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ] && manifests+=("$REPO_ROOT/.claude-plugin/marketplace.json")
manifests+=("$REPO_ROOT"/plugins/*/.claude-plugin/plugin.json)
shopt -u nullglob
if [ ${#manifests[@]} -eq 0 ]; then
    echo "sync-plugin-versions: no manifests found under $REPO_ROOT" >&2
    exit 1
fi

# Set `version` immediately after `name` (idiomatic manifest position), or update
# it in place if already present, preserving every other key and its order. Works
# for both manifest shapes — crucially it never drops marketplace.json's $schema,
# owner, or plugins array.
JQ_SET='
  to_entries as $e
  | (if any($e[]; .key == "version")
     then ($e | map(if .key == "version" then .value = $v else . end))
     else (($e | map(.key) | index("name")) // (($e | length) - 1)) as $after
          | ($e[:($after + 1)] + [{key: "version", value: $v}] + $e[($after + 1):])
     end)
  | from_entries
'

changed=0
changed_paths=()
for f in "${manifests[@]}"; do
    current="$(jq -r '.version // ""' "$f")"
    [ "$current" = "$BARE_VERSION" ] && continue

    tmp="$(mktemp "${f}.XXXXXX")"
    if jq --arg v "$BARE_VERSION" "$JQ_SET" "$f" > "$tmp"; then
        mv "$tmp" "$f"
    else
        rm -f "$tmp"
        echo "sync-plugin-versions: jq failed on $f" >&2
        exit 1
    fi
    changed=$((changed + 1))
    changed_paths+=("$f")
done

# --- Bump mode: fold the synced manifests into the tagged release commit ------
if [ "${SEMVER_BUMP_IN_PROGRESS:-}" = "1" ] && [ "$changed" -gt 0 ]; then
    # Stage only the manifests we touched — never `-A`, so any unrelated working-
    # tree changes (e.g. files just restored from a pre-bump stash) stay out of
    # the release commit.
    git -C "$REPO_ROOT" add -- "${changed_paths[@]}"
    git -C "$REPO_ROOT" commit --amend --no-edit --quiet
    echo "sync-plugin-versions: folded $changed manifest(s) into release commit ${RAW_VERSION}"

    # Re-point the release tag onto the amended commit if semver created one.
    if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/${RAW_VERSION}" >/dev/null 2>&1; then
        git -C "$REPO_ROOT" tag -f "$RAW_VERSION" >/dev/null
        echo "sync-plugin-versions: moved tag ${RAW_VERSION} onto amended commit"
    fi
fi

printf 'sync-plugin-versions: %s across %d manifest(s) (%d updated)\n' \
    "$BARE_VERSION" "${#manifests[@]}" "$changed"
exit 0
