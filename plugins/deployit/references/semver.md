# Semver awareness

deployit integrates with the `semver` plugin so that builds carry a meaningful,
monotonic version and no two published builds of the same product share a version.
The integration is **decoupled**: deployit reads semver's on-disk artifacts
directly and never imports semver's code for display or comparison. The only place
it invokes semver is the deploy-time bump, which shells out to the semver CLI.

## When is semver "active"?

A project is semver-tracked when, **in the deploy cwd** (the project root):

- `./.semver/config.yaml` exists and contains `tracking: true`, and
- a readable `./VERSION` file exists.

This matches how `_derive_metadata` already treats cwd as the project root and how
`semver-cli` itself operates on cwd. Detection lives in
`_semver_active_version(cwd)` / `_parse_semver_config(cwd)` in `bin/deployit-cli`.

## What the web UI reports

Each build records a nullable `semver_version` in its metadata
(`serve/<id>/_meta.json` and the shared `index/builds.json`) — captured at deploy
time, because the backend serves builds from many machines and cannot read each
project's `VERSION` at render time.

`bin/deployit-backend` renders one version label per build (`_version_label`):

| Build recorded a `semver_version`? | Listing row / landing page shows |
| --- | --- |
| Yes | `<semver_version> (build <CFBundleVersion>)` — e.g. `v2.16.1 (build 16)` |
| No  | `build <CFBundleVersion>` — e.g. `build 16` |

When semver is off, the `project.yml` `MARKETING_VERSION` is **not** shown — the
build number is the discriminator. Pre-existing index entries (deployed before
this feature) have no `semver_version` and therefore fall back to the build number.

## The deploy-time bump guard

`/deployit deploy` runs `deployit preflight --platform <P>` first (see the
"Semver-aware deploy" section in `SKILL.md`). When semver is active, preflight
compares the current `VERSION` against the `semver_version` of the newest already
published build of the same `(bundle_id, platform)`:

- The shared index is best-effort `git pull`ed first so the comparison is fresh
  (skippable via `DEPLOYIT_SKIP_INDEX_PULL`). Comparison spans **all** origins in
  the shared index — "changed since the latest build" means since the latest build
  anyone published.
- `bump_needed` is true only when semver is active **and** the current version
  already labels that latest build (i.e. it has not changed). With no prior build,
  or an entry that predates `semver_version`, the deploy proceeds without a bump.

When `bump_needed`, the SKILL asks which component to bump (major/minor/patch —
labelled with the candidate versions from `_next_versions`) and then runs
`deployit bump --component <c>`, which executes:

```
semver-cli bump execute <c> --source force --force --dirty-action include \
    --plugin-root <semver-plugin-root>
```

- **`--dirty-action include`** folds any uncommitted changes into the
  `chore(release): <version>` commit ("auto-include & go" — no extra prompts).
- **`--force` / `--source force`** allow a version-only bump when there are no new
  commits.
- Tags are created per the project's `git_tagging` config; a pre-existing tag is
  non-fatal.
- The semver plugin's **shell** hooks run (because `--plugin-root` is passed); its
  interactive `PROMPT_HOOK.md` advisories are intentionally skipped, consistent
  with the no-prompts deploy flow.

The semver CLI is discovered by `_find_semver_cli`: `$DEPLOYIT_SEMVER_CLI` →
sibling plugin (`<deployit-root>/../semver/bin/semver-cli`) → a glob under
`~/.claude`. If it cannot be found, `bump` fails with guidance to bump manually,
and the deploy stops rather than shipping a stale version.

## Implications

- The build is archived **after** the bump, so its recorded `commit` and
  `build_id` reflect the `chore(release)` commit. If the host repo's Archive
  pre-action derives `CFBundleVersion` from git state, that may move too — the two
  version mechanisms are independent and complementary.
- The bump commits on the **current** branch (no off-branch prompt, by design).

## Non-goals

- deployit does **not** modify the app's `MARKETING_VERSION` or `Info.plist`. The
  semver version drives the reported/displayed version and the deploy guard only —
  it is display + release bookkeeping, not a change to the built binary's version.
