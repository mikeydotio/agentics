# Plugin content validation (AGE-84)

## Problem and ownership

The v3.9.1 candidate gate compares every shipped plugin file to the release tag.
Ordinary development therefore fails before its behavior is tested, including
central-verifier merge checkouts. The guard also reports missing tags as passing
skips. AGE-84 owns both defects. AGE-102 already retired global push enforcement;
this repair stays in the repository and needs no verifier adapter.

SemVer section 3 preserves released content identity, not identity between every
development commit and the last release: <https://semver.org/>. A green candidate
suite cannot establish release readiness or installed-cache freshness.

## Interfaces

`bash scripts/check-plugin-content.sh [--mode candidate|release] [--repo DIR]`

The defaults are release mode and the repository containing the script. An
explicit repository is resolved to its top level. Unknown arguments, missing
values and invalid modes exit 2; verification errors and strict mismatches exit 1.
No command modifies the repository, tags, version, or installed files.

| Evidence | Candidate | Release |
|---|---|---|
| Tag, HEAD, index and working content match | release-matched, exit 0 | release-matched, exit 0 |
| Committed or local shipped changes | unreleased-changes, exit 0 | unreleased-changes, exit 1 |
| Exact version tag absent | baseline-unavailable, exit 0 | baseline-unavailable, exit 1 |
| Invalid VERSION, repository, HEAD, tag object or Git command | exit 1, contextual diagnostic | exit 1, contextual diagnostic |

Every successful candidate result explicitly states that release readiness is
not certified. Checkout topology, branch names and bypass environment variables
do not select policy. A PR-base comparison is insufficient: inherited drift also
matters for release identity. A missing tag never proves matching content.

## Evidence and implementation

One pathspec includes VERSION, the marketplace manifest and plugins/**. Preserve
the previous exclusions for plugins/*/tests/**, plugins/**/*.bats and
plugins/*/README.md. Both host manifests and runtime reference documents count.

Read a complete SemVer string with optional leading v and trailing newline;
reject malformed versions. Resolve HEAD and the exact refs/tags/v<VERSION> to
commits. Check command exit statuses before interpreting their output. Resolve
the tag object separately from peeling it so a non-commit/corrupt tag cannot be
classified as absent.

Check tag-to-HEAD, HEAD-to-index and index-to-worktree independently. A staged
change reversed only in the working tree must still be reported. Also enumerate
untracked shipped files, including ignored files that could enter a local copy.
Git NUL-delimited records preserve unusual filenames; diagnostic paths use Bash
shell escaping. Disable external diff/textconv and force file-mode detection.
Private scratch files retain producer exit status and binary delimiters.
Disable fsmonitor caching, and fail with context if shipped index entries carry
assume-unchanged or skip-worktree flags: Git intentionally omits working-file
checks in those states. Do not clear flags or change the user's index.

The checker sets LC_ALL=C before parsing ASCII Git markers and SemVer. Locale
collation can otherwise include uppercase H in [a-z], incorrectly rejecting
ordinary index entries. Regression coverage varies the caller's LC_ALL,
LC_COLLATE and LANG while preserving clean, drifted and hidden-file verdicts.
See the [Bash range rules](https://www.gnu.org/s/bash/manual/html_node/Pattern-Matching.html).

## Entry points and limits

`test-plugin-content-drift` runs production-CLI regressions followed by explicit
candidate evaluation. It stays in the central verifier's ordinary test graph.
`validate-release` combines existing manifest-version validation with strict
content validation and is required before publication or normal version-keyed
installation from a checkout. It is not part of candidate testing.

There is no marketplace publication executable in this repository. The preflight
is a repository command and documented operator contract, not an interception of
external installers. Disposable package smokes still test candidate packaging.
They neither certify a release nor inspect the user's active cache. Source
validation never substitutes for checking the actual installed runtime after
supported installation. No installed artifact is patched by this repair.

## Regression and delivery requirements

Exercise the production CLI with real disposable Git repositories: both tag
kinds, each checkout form, all change kinds/layers, both host manifests,
exclusions, missing and invalid evidence, SemVer boundaries, unusual filenames,
and failing Git commands. Pin strict defaults and Make target wiring with both
positive and negative controls. Python unittest owns fixtures only, not policy.

Reuse AGE-102's narrow dispatch-sentinel ignore repair and its tests in a separate
commit. Record red/green evidence and focused checks on AGE-84. The final worktree
action is the move to verifying; central verification owns the full suite and
delivery. There are no version, publication, installation or release steps here.
