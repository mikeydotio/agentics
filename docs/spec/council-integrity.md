# AGE-77: Detect Council input changes and preserve user work

## Summary

Add content-sensitive integrity checks to Council’s shared state helper. Both hosts must verify repository inputs before dispatch, result acceptance, phase progression, recovery, and final decisions.

The current helper validates delivery and deadlines but does not fingerprint repository inputs. AGE-81 supplies the state machinery; AGE-105 fixes its clock. AGE-55 governs Forge integrity and includes restoration behavior that Council must not inherit. These changes do not replace AGE-77.

## Implementation sequence

1. Run `story comment AGE-77 <your-exact-approved-plan>`. Pass this entire approved plan verbatim as one safely quoted argument. Confirm success before editing files or running tests.
2. Repeat `story show AGE-77 --json`, `story help obviation-review`, and `story load-context --story AGE-77 --format json`. Review every candidate’s complete discussion, relationships, and linked evidence without output truncation. Repeat on resumption.
3. Record the design decisions below using **Context / Question / Decision / Rationale**. Save the contract in `docs/spec/council-integrity.md`.
4. Add failing production-helper regressions. Implement the repair, host integration, and documentation. Commit the fix with its tests.
5. Record focused test results, limitations, and commit IDs on AGE-77. Check for unintended changes.
6. Run `story move AGE-77 verifying` from this worktree as the absolute last action, then stop.

## Integrity mechanism and interfaces

### Durable baseline

Add a focused Python standard-library module under Council’s `bin` directory. Integrate it into `council_store.execute`; do not create a second host-specific integrity implementation.

- Add optional `repository_root` to `init`. Default to the Git worktree containing the invocation directory. Persist the resolved worktree identity; never rediscover it from a later command’s working directory.
- Reject a missing or unsupported repository explicitly. Support linked worktrees and an unborn HEAD.
- Before returning usable initial state, persist an immutable baseline manifest. Bind its digest and schema version to `STATE.json`.
- Record HEAD identity and semantic index entries: path, object ID, mode, and merge stage. Avoid raw index-byte comparison, which can confuse stat-cache refreshes with staged-content changes.
- Inventory working-tree entries, including tracked, untracked, and ignored files. Record existence, type, executable bits, regular-file SHA-256, and symlink target.
- Preserve unusual filenames through NUL-delimited Git output and reversible filesystem-byte encoding. Do not parse human-readable status output. Git documents the required filename and index formats. [Git ls-files documentation](https://git-scm.com/docs/git-ls-files)
- Do not follow symlinks. Check file identity and metadata around hashing; reject observed changes during capture. Use two matching inventories before accepting a baseline or verification result.
- Use atomic writes and the existing state lock. Missing, corrupt, mismatched, unreadable, or incomplete evidence never becomes a clean result.

### Coverage and exclusions

Use fixed, documented exclusions rather than caller-provided wildcard exclusions:

- Exclude Git administrative storage.
- Exclude only this sitting’s named chair artifacts and helper-owned scratch directories recorded by attempt identity.
- Never exempt tracked files through the sitting exclusion.
- Check sitting and scratch container types; reject symlink redirection.
- Include unrelated files inside the sitting directory and all other sittings.
- Record submodule gitlinks and boundary-path types, but explicitly exclude nested repository interiors. List those exclusions in the manifest and result.
- Check symlink targets as link text, not the target’s external contents.
- Unsupported special files and traversal errors produce an unverified result.

Use no-follow filesystem operations to preserve these boundaries. [Python filesystem documentation](https://docs.python.org/3/library/os.html)

### Runtime enforcement

Add a structured integrity result with `status` (`clean`, `drift`, or `unverified`), baseline identity, checkpoint, changed paths, and diagnostic details.

Enforce verification:

- Before `begin-phase` and each `dispatch-attempted` event.
- Before accepting every delivery.
- During `advance`, before exposing phase-complete findings.
- Before later phases consume prior findings.
- During `recover`.
- Before `finish outcome:decision`.

`status` remains read-only inspection. Its output does not authorize dispatch or use of findings without the corresponding checked transition.

On drift or unverified evidence:

- Persist an integrity failure and abort the sitting.
- Return an explicit failed result and only cleanup actions.
- Preserve received payloads as invalid evidence; exclude them from proposals, tallies, and decisions.
- Write changed-path and failure diagnostics without copying source-file contents.
- Preserve current files, index, HEAD, earlier artifacts, and baseline.
- Never restore, reset, discard, stage, or commit another actor’s changes.
- Report “inputs changed”; do not attribute the change to a member without evidence.
- If diagnostic persistence fails, return a contextual nonzero error. Never permit progression.

Preserve AGE-81’s retry, deadline, and cleanup rules and AGE-105’s clock behavior. Integrity failure is not a seat retry.

### Recovery and host integration

Update both host skills, Codex orchestration, the shared protocol, liveness reference, and Council README.

- Replace status-only comparisons with mandatory helper results at every required boundary.
- Legacy active sittings without trustworthy baselines cannot resume accepting findings.
- An unchanged interrupted sitting retains its baseline and original deadlines under existing recovery rules.
- A contaminated sitting remains aborted. Fresh evaluation requires explicit reconciliation, confirmation that owned writers have stopped, and a new sitting with a new baseline.
- Add reconciliation metadata to fresh `init`: prior sitting path and a nonempty explanation. Preserve the prior sitting; never reuse its findings as validated results.
- Require mutating experiments to use disposable copies or worktrees. The chair must not measure a tree while experiment writers can modify it.
- State the limit: fingerprints detect persistent changes at observation points, not writes restored between checks. This is detection, not a host permission sandbox.

## Test plan

Add separate AGE-77 behavioral and host-contract tests. Register them in Council’s existing runner without weakening existing tests.

| Scenario | Required evidence |
|---|---|
| Unchanged repository, both hosts | Complete valid sitting succeeds |
| Clean-file edit; second edit to dirty file | Result rejected despite unchanged status classification |
| Index-only change; HEAD movement | Drift reported with preserved Git state |
| Additions, deletions, renames | Exact affected paths reported |
| Executable, file-type, and symlink changes | Drift detected without following external targets |
| Pre-existing untracked and ignored files | Content changes detected |
| Spaces, tabs, newlines, Unicode filenames | Lossless manifest and diagnostics |
| Allowed chair and owned scratch writes | Clean result; unrelated sitting writes still detected |
| Missing, corrupt, unreadable baseline | Unverified result; no dispatch or acceptance |
| Interrupted capture or diagnostic write | Failure remains visible; no replacement baseline |
| Resume unchanged or contaminated sitting | Original baseline retained, or explicit abort |
| Concurrent user edit | Findings invalidated; edit preserved; no member blamed |
| Late-phase and final-decision drift | No contaminated phase or decision accepted |
| Submodule and symlink boundaries | Coverage limits explicitly reported |

Use real temporary Git repositories and the production CLI. Inject only external I/O failures, clock inputs, and transport events. Assert preserved bytes, index content, HEAD, baseline, and rejected payload evidence.

Add targeted mutations in disposable copies. Require a passing baseline before proving that removed checks, status-only fingerprints, widened exclusions, and swallowed read failures are caught.

Run only AGE-77’s added or changed tests, with `TMPDIR=/tmp`, bytecode disabled, Python warnings treated as errors, and the existing isolated-store wrapper. Central verification owns every other test.

## Defaults and submission boundaries

- No new dependency, service, watcher, automatic restoration, or permission restrictions on specialist tools.
- Preserve version v3.9.5 and existing voting mechanics.
- Record later decisions immediately before dependent work.
- Apply the supplied adoption rules to additional defects; read `story help scope-rubric` before prerequisite or blocking decisions.
- Commit locally. Do not push, create or link a PR, run the full suite, release, or close AGE-77.
- On verifier return, preserve published history and rerun only exact named failing cases permitted by the user.
