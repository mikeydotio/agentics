#!/usr/bin/env bash
# Read-only source identity preflight. Candidate acceptance is not release proof.
set -euo pipefail

# Report a verification failure without discarding a producer's stderr.
die() { printf 'plugin-content: %s\n' "$*" >&2; exit 1; }

# Invalid calls must be distinguishable from a valid call that found drift.
usage() {
    printf 'usage: check-plugin-content.sh [--mode candidate|release] [--repo DIR]\n' >&2
    exit 2
}

mode=release
repo=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode) [ "$#" -ge 2 ] || usage; mode=$2; shift 2 ;;
        --repo) [ "$#" -ge 2 ] && [ -n "$2" ] || usage; repo=$2; shift 2 ;;
        *) usage ;;
    esac
done
case "$mode" in candidate|release) ;; *) usage ;; esac
command -v git >/dev/null 2>&1 || die 'git is required'

# A caller's Git hook environment must not redirect --repo into another index.
for variable in ${!GIT_@}; do unset "$variable"; done
export GIT_OPTIONAL_LOCKS=0 GIT_NO_REPLACE_OBJECTS=1

if [ -z "$repo" ]; then
    repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || die 'cannot resolve repository'
fi
repo=$(git -C "$repo" rev-parse --show-toplevel) || die 'cannot resolve repository'

# Keep source comparisons independent of user diff drivers and filemode settings.
git_source() { git -C "$repo" -c core.filemode=true -c core.fsmonitor=false "$@"; }

head=$(git_source rev-parse --verify 'HEAD^{commit}') || die "cannot resolve HEAD in $repo"
git_source cat-file -e "$head^{tree}" || die "cannot read HEAD tree in $repo"
[ -f "$repo/VERSION" ] && [ ! -L "$repo/VERSION" ] || die "missing regular VERSION in $repo"
# Bash substitution drops NULs and final newlines. Reject NULs and retain all
# newlines until removing the one optional line terminator in the file contract.
if IFS= read -r -d '' version < "$repo/VERSION"; then die "invalid VERSION: NUL byte in $repo"; fi
version=$(cat "$repo/VERSION" && printf '.') || die "cannot read VERSION in $repo"
version=${version%.}
version=${version%$'\n'}
version=${version#v}
# SemVer's numeric prerelease identifiers cannot have leading zeroes; build
# identifiers can. Bash ERE avoids a dependency on a separate version parser.
number='(0|[1-9][0-9]*)'
pre='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
semver="^$number\.$number\.$number(-$pre(\.$pre)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"
[[ "$version" =~ $semver ]] || die "invalid VERSION in $repo"
tag="refs/tags/v$version"

paths=(
    ':(top,literal)VERSION'
    ':(top,literal).claude-plugin/marketplace.json'
    ':(top)plugins/'
    ':(top,exclude,glob)plugins/*/tests/**'
    ':(top,exclude,glob)plugins/**/*.bats'
    ':(top,exclude,glob)plugins/*/README.md'
)

scratch=$(mktemp -d "${TMPDIR:-/tmp}/agentics-content.XXXXXX") || die 'cannot create evidence directory'
trap 'rm -rf "$scratch"' EXIT
diff_args=(--no-ext-diff --no-textconv --no-renames --ignore-submodules=none --name-only -z)

# These flags explicitly tell Git not to inspect working files. Do not change
# the user's index or certify evidence that the diff below cannot establish.
git_source ls-files -v -z -- "${paths[@]}" > "$scratch/index-flags" \
    || die 'cannot inspect shipped index flags'
while IFS= read -r -d '' entry; do
    case "$entry" in
        [a-zS]' '*)
            printf 'Unverifiable shipped path: %q\n' "${entry:2}" >&2
            die 'index flags hide working content; use a full checkout without assume-unchanged or skip-worktree flags'
            ;;
    esac
done < "$scratch/index-flags"

# Each producer is checked before reading its NUL records. Separate layers catch
# a staged change even when the working copy restores the original bytes.
git_source diff "${diff_args[@]}" --cached "$head" -- "${paths[@]}" > "$scratch/staged" \
    || die 'cannot compare staged shipped content'
git_source diff "${diff_args[@]}" -- "${paths[@]}" > "$scratch/unstaged" \
    || die 'cannot compare working shipped content'
# No --exclude-standard: ignored runtime files can enter a copied installation.
git_source ls-files --others -z -- "${paths[@]}" > "$scratch/untracked" \
    || die 'cannot enumerate untracked shipped content'

# Listing and peeling are separate: absent tags are candidate evidence; a tag
# that exists but cannot name a readable commit is always a verification error.
tag_object=$(git_source for-each-ref --format='%(objectname)' "$tag") \
    || die "cannot inspect release tag $tag"
state='baseline-unavailable'
if [ -n "$tag_object" ]; then
    release=$(git_source rev-parse --verify "$tag^{commit}") \
        || die "cannot resolve release tag $tag to a commit"
    git_source cat-file -e "$release^{tree}" || die "cannot read release tag $tag tree"
    git_source diff "${diff_args[@]}" "$release" "$head" -- "${paths[@]}" > "$scratch/committed" \
        || die "cannot compare release tag $tag with HEAD"
    state='release-matched'
    for layer in committed staged unstaged untracked; do
        if [ -s "$scratch/$layer" ]; then state='unreleased-changes'; fi
    done
fi

printf 'plugin-content: %s mode=%s version=%s HEAD=%s\n' "$state" "$mode" "$version" "$head"
for layer in committed staged unstaged untracked; do
    if [ -s "$scratch/$layer" ]; then
        printf '%s shipped paths:\n' "$layer"
        while IFS= read -r -d '' path; do printf '  %q\n' "$path"; done < "$scratch/$layer"
    fi
done
if [ "$state" = baseline-unavailable ]; then
    printf 'Release tag %s is absent; obtain the exact release tag before strict validation.\n' "$tag"
fi
if [ "$mode" = candidate ]; then
    printf 'Candidate evidence evaluated; release readiness is not certified.\n'
elif [ "$state" != release-matched ]; then
    die 'release source is not validated; do not publish or install it as this version'
else
    printf 'Release source matches its tag; installed-cache parity is not certified.\n'
fi
