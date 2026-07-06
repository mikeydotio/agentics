# `set` and `init` — explicit version + one-shot initialization

Two commands complement `bump` (which only increments major/minor/patch):

- **`/semver set <vX.Y.Z>`** — assign an explicit target version.
- **`/semver init [vX.Y.Z]`** — enable tracking + auto-bump and initialize in one step.

Both are **interactive** commands modeled on `bump run`/`bump execute`: the router
calls a `run` subcommand that gathers state and, on the happy path, executes in the
same call; when interaction is needed it returns a `questions` array for the SKILL
Question Loop, which then calls the `execute` subcommand with the collected flags.
Both thread `--plugin-root` so post-bump user hooks (e.g. this repo's
`01-sync-plugin-versions.sh`) fire and keep manifests in sync.

## `set`

`set` behaves like `bump` but takes an explicit target instead of an increment:
validate + prefix the target, generate a changelog entry from commits since the
last version, write VERSION, commit `chore(release): <ver>`, and tag.

- **Forward / non-sequential** (`v1.2.3` → `v5.0.0`): proceeds silently — the point
  of `set`. Creates a real commit + tag; `/semver validate` stays green.
- **Lower / equal-or-backward** target: asks a `backward_version` question
  (`--allow-backward` to proceed).
- **Re-cut of the current version** (target == current VERSION, nothing new to
  commit): a **coherent re-tag / no-op**, never an empty commit. If the version tag
  is missing or points off the commit that last set VERSION, it is (re)placed there;
  otherwise nothing changes. This deliberately diverges from a literal "create an
  empty commit and tag it" because an empty commit shares its parent's tree and so
  never becomes VERSION's last-touch commit — which would break `validate` check 4
  (`tag_correct_commit`). See [sync-validation.md](sync-validation.md).
- **Tag conflict** (target tag already exists elsewhere): `tag_conflict` question
  (`--overwrite-tag` moves it — flagged as destructive in the display — or
  `--skip-tag`).
- **Dirty tree / wrong branch / broken sync**: same questions as `bump`.
- **First version via set** (tracking on, no VERSION yet): creates VERSION +
  initial changelog + tag.
- **Tracking inactive**: errors and points at `/semver init`.
- Honors the `SEMVER_BUMP_IN_PROGRESS` re-entrancy guard; rolls back
  (`git checkout VERSION CHANGELOG.md`) on commit failure.

## `init`

`init` detects existing artifacts (config/tracking, VERSION, CHANGELOG, version
tags, archive) **read-only** before doing anything.

- **No artifacts** → clean init in one call: writes config with `tracking: true` +
  `auto_bump: true`, seeds VERSION (arg or `v0.1.0`), creates the changelog, injects
  the CLAUDE.md block, commits, and tags the **new init commit** (now the latest
  commit — this keeps `validate` check 4 green because that commit is VERSION's
  last-touch commit). On commit failure the partial files are cleaned up.
- **Artifacts present** → returns an assessment (`artifacts` snapshot) plus a single
  `init_existing` question whose options are computed from the state — never a blind
  re-init:

  | Option | Shown when | Follow-up |
  |--------|-----------|-----------|
  | Enable tracking + auto-bump | config exists, tracking or auto-bump off | `init execute --mode enable` |
  | Adopt existing setup | VERSION/tags exist, no config | `init execute --mode adopt` |
  | Re-initialize at a version | always | `init execute --mode reinit --version <v>` |
  | Check integrity | tracking coherent | `validate` |
  | Repair sync issues | artifacts incoherent | `repair diagnose` |
  | Cancel | always | — |

`init` overlaps with `tracking start [--version]`; internally both share
`_init_fresh_core` (the config/VERSION/CHANGELOG/CLAUDE.md/commit/tag body).
`tracking start` remains the granular, option-rich initializer; `init` is the
quick "adopt semver now" entry point that always seeds a version, enables
auto-bump, and guards against clobbering an already-initialized repo.
