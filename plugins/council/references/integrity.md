# Council repository integrity

Both hosts use `bin/council-state.py`. Read this contract before `init` or recovery.
This is persistent-change detection, not a permission sandbox or proof of model compliance.

## Capture and required gates

Run `init` with optional `repository_root`: an absolute path in the caller's Git worktree.
The default is the worktree containing the invocation directory. The helper persists the
resolved identity, including linked-worktree administration. Later commands use that identity.
Non-Git inputs fail explicitly. Do not stage sitting artifacts until the sitting ends.

`BASELINE.json` is immutable pre-dispatch evidence, bound to `STATE.json` by SHA-256,
schema and council identity. It records HEAD (including unborn/detached identity), semantic
index paths/modes/object IDs/stages, and two matching working-tree inventories. Regular files
are hashed; existence, type, executable bits and symlink target text are compared. Names use
lossless JSON escapes. File timestamps alone and `git status` never prove unchanged contents.

The helper checks before `begin-phase`, `record kind:dispatch-attempted`, every `delivery`,
and other active state changes. `advance` verifies before exposing phase-complete findings.
Later `begin-phase` verifies before consuming the slate. `recover` verifies before reusing
accepted findings. `finish outcome:decision` verifies before publishing a decision.

For every required gate, require exit zero, exactly one valid JSON object, `ok:true`, and
`integrity.status:"clean"`. Also require the expected state/action; a clean check does not
override an expired deadline or liveness abort. Missing, malformed or contradictory output
is unverified. Do not dispatch, tally, consume phase findings, or return a decision from it.
`status` is read-only historical inspection, not a new integrity observation or permission.

## Coverage and exclusions

All working-tree files are inventoried, including ignored files and pre-existing untracked
content. There is no wildcard exclusion for untracked, ignored, or `.council` content.
Directories are checked for existence/type/executable mode, not modification timestamps.
The fixed exclusions are:

- Git administration. A content-sensitive Git metadata cache covers HEAD, refs, packed refs,
  index, split-index files, configuration and worktree linkage. Changed metadata is interpreted
  again by Git; a stat-cache refresh is not a semantic index change.
  Global/system Git configuration is disabled for these reads. Local include sections
  bypass the semantic cache because their external contents are not fingerprinted.
- This sitting's exact chair artifact names: `QUESTION.md`, `PANEL.md`, `STATE.json`,
  `.state.lock`, `LIVENESS.md`, `BASELINE.json`, `INTEGRITY.json`, `ABORT.md`, `DECISION.md`,
  `proposals-round-1.md`, `vote-round-1.md`, `deliberation.md`, `proposals-round-2.md`,
  and `vote-round-2.md`. These paths must remain regular files, never redirects.
- Only attempt directories registered by the helper beneath this sitting's `scratch/`.
  Sitting and scratch containers cannot be symlinks. Retired attempts remain owned so late
  measurement output does not become a false source edit. Other scratch paths are checked.
- Nested repository interiors, including submodules. Their boundary types and outer index
  gitlinks remain checked; each excluded interior is listed explicitly. No claim is made
  about their HEAD, index, or internal files. Changes to those inputs need a separate sitting
  rooted in that repository or an isolated measurement copy.

Tracked files cannot become exempt chair or scratch output. Symlinks are never followed;
their external target contents are outside coverage. ACLs, extended attributes and ownership
are outside this content/executable-mode contract. Special files, unsupported metadata layouts,
read failures, or observed changes during capture fail closed.
The current metadata cache supports Git's files reference backend; reftable storage and
symlink Git metadata fail explicitly. It does not certify the entire Git object database.

## Failure and reconciliation

`integrity.status` is `clean`, `drift`, or `unverified`. Failure records the checkpoint,
baseline identity, changed paths, HEAD change, coverage exclusions and diagnostics.
The helper persists an aborted state, writes `INTEGRITY.json` and `ABORT.md`, returns
`ok:false` with nonzero exit, and exposes only bounded cleanup actions. A write failure
can leave durable state without rendered Markdown; preserve stdout/stderr and use recovery.
If chair output overlaps a tracked file, the helper refuses artifact writes and reports the
conflicting paths on its error channel. Reporting must not overwrite tracked evidence.

Stop accepting findings immediately. The helper preserves old payloads and the rejected event
in `invalidated_findings` and removes the usable slate. Earlier phase Markdown is historical,
invalid evidence. Do not restore, reset, discard, stage, or commit changed inputs. A concurrent
user edit is preserved. Changed inputs do not identify their author; do not blame a member.
If source or artifact evidence cannot be read safely, preserve it and report the error.

Stop only owned writers using the existing 30-second cleanup window. Unchanged recovery
retains the original baseline and deadlines. Legacy active state without a baseline cannot
be upgraded by capturing its post-dispatch files. Contaminated sittings remain aborted.

After explicit reconciliation, create a new slug and `init` with:

```json
{"reconciliation":{"previous_directory":"/absolute/prior/sitting",
                   "reason":"Inputs and invalid findings reviewed; fresh evaluation required",
                   "writers_stopped":true}}
```

The prior sitting must be aborted in the same repository. The stopped flag is the chair's
attestation from actual host observations. If a writer remains reachable and running, do not
assert it. Preserve the old artifacts and baseline. Start independent research again under
the new baseline; never promote contaminated responses into accepted findings. Do not silently
start a new sitting to evade reconciliation. Existing caller authorization governs reconvening.

## Measurement limit

Fingerprints cannot detect writes restored between observations. A changing tree is not an
atomic filesystem snapshot. Two matching inventories reject observed races, not every possible
write race. Mutating experiments belong in disposable copies/worktrees inside owned scratch.
The chair must not measure a tree concurrently available to experiment writers. Preserve
legitimate specialist measurement tools; a prompt rule is not a host permission boundary.

Sources: [Git filenames and index entries](https://git-scm.com/docs/git-ls-files),
[Git repository layout](https://git-scm.com/docs/gitrepository-layout),
[Git index format](https://git-scm.com/docs/gitformat-index), and
[Python no-follow filesystem APIs](https://docs.python.org/3/library/os.html).
