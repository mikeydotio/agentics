# Forge fixture teardown could delete a workspace before its owner released it

- **Date**: 2026-10-15
- **Severity/Impact**: One Forge setup-contract teardown failure stopped the Agentics release gate on 2026-10-14. Eight later test targets and strict release validation did not run. No production impact was established; release readiness remains unverified.
- **Status**: Fixed in `e7cb061d4db9b424278b5a15d8dd0a055c9e1e2e` on an unmerged development branch; focused validation passed.

## Summary

The Forge StoryHook setup fixture deleted its repository without first draining asynchronous work that could still own it. A deterministic reproduction exercised the actual Bats teardown and showed a real, exclusively locked inode being unlinked before its owner released it. The repair gives each fixture a private StoryHook identity and permits deletion only after successful, bounded normal shutdown of that same instance. Six regression methods and both real CLI documentation variants passed. The original release gate's `Directory not empty` writer and exact interleaving remain unidentified; the verified lesson is to couple fixture deletion to resource-owner shutdown.

## Timeline

All times are UTC. The introducing commit and a reliable last-known-good boundary for the intermittent historical failure were not established.

| Date/time | Evidence or change |
|---|---|
| 2026-10-14 23:04:40 | Baseline `ce7e306aabfb9533d66438f7f13a88ae83a649ed` contains the unconditional fixture teardown. This is a source anchor, not an attribution of introduction. |
| 2026-10-14 23:07:17.111000–23:24:12.681290 | `RELEASE-GATE-01` failed with exit 2. Forge reported 525 passing cases and one failure: teardown of the Codex setup-contract case reported `.git: Directory not empty`. The original workspace-lock residue and failure evidence were retained. |
| 2026-10-14 23:43:59 | `FORGE-LIFECYCLE-RED-01` failed during reproduction setup because macOS bare `mktemp -d` did not use the proposed temporary parent. It is preserved as a setup failure, not counted as a reproduction. A test-local allocation adapter corrected that assumption. |
| 2026-10-14 23:47:12.631263–23:47:14.462796 | `FORGE-LIFECYCLE-RED-02` established the narrower lifecycle defect against the unchanged fixture: its Bats case passed, but the independent owner-release assertion failed after teardown unlinked the held inode. |
| 2026-10-14 23:51 | Independent challenge accepted the conditional lifetime defect and required private-instance identity and shutdown-failure coverage before accepting a repair. Historical attribution remained unknown. |
| 2026-10-15, before focused validation | Independent source review found no must-fix finding in the three-file repair. It explicitly required real installed-CLI checks in addition to the controlled regression. |
| 2026-10-15 00:08:55.126382–00:10:26.478144 | The lifecycle regression and both real CLI variants passed; source fingerprints matched throughout. Individual durations and log hashes are below. |
| 2026-10-15 00:10:46.498193 | The shared test window was released early after resource-custody checks. |
| 2026-10-15 00:11:30 | Commit `e7cb061d4db9b424278b5a15d8dd0a055c9e1e2e` records the reviewed and focused-tested repair. No merge, release or installation occurred. |

## Root cause & trigger

The verified chain is limited to the fixture's lifetime contract:

1. **Defect:** At baseline `ce7e306aabfb9533d66438f7f13a88ae83a649ed`, `plugins/forge/bin/forge-storyhook-setup-contract.bats:24–25` removed the repository directly. Fixture completion had no shutdown boundary for an asynchronous workspace owner; the suite-level parent could remain alive.
2. **Exposure:** The reproduction's external StoryHook stand-in admitted a separate process and waited for its real exclusive `flock` before acknowledging the verifying transition. The blocked transition returned while that owner was still alive. The handshake established the order without a probabilistic race.
3. **Failure:** Actual Bats teardown deleted the workspace before owner release. The owner's receipt recorded `links_before_release=0` and `same_inode_after_release=false`; release occurred only through test cleanup. The lifecycle assertion failed even though the Bats case itself returned success.
4. **Intervention:** The repaired fixture drains its private owner before removal. The success regression observes a still-linked, unchanged inode at release; error and timeout scenarios observe preserved workspace and store before the regression cleans up its own resources.

**ODC classification:** Timing/Serialization · Missing · concurrency/teardown trigger. The demonstrated trigger is teardown while an admitted owner remains active. No filesystem-lock malfunction is needed to produce the failure.

Inspected StoryHook source supports asynchronous state acknowledgement and a normal stop that waits for daemon lifetime-lock release. Its equivalence to the installed build was not established. The real CLI passes supply focused runtime evidence for the repaired shutdown path; they do not identify the original historical writer or reproduce the historical `Directory not empty` scheduling. The reason that historical failure surfaced in that particular release run remains unknown.

## Contributing factors

- The fixture's temporary repository lifetime was shorter than the suite-owned daemon lifetime. A successful state transition did not establish that all workspace users had stopped.
- Isolating only a temporary directory was insufficient: an inherited explicit store path or daemon identity could select another instance. A stop request needed the same private identity as every work request.
- The original contract cases asserted command results, leaving teardown ordering unobserved. A lock can remain held on an inode after its pathname has been deleted.
- Failure cleanup needed its own preservation contract. A fixture root underneath Bats or suite cleanup could disappear after a failed stop despite the local teardown retaining it.

## The fix

**Verdict: SURGICAL.** Commit `e7cb061d4db9b424278b5a15d8dd0a055c9e1e2e` repairs the fixture ownership boundary without changing product lock primitives or tracker data semantics.

[`forge-storyhook-setup-contract.bats`](../../plugins/forge/bin/forge-storyhook-setup-contract.bats) captures the executable, owner PID and exclusive fixture root before project creation. The root contains the repository, private home/store/state, ownership receipt and shutdown diagnostics, outside Bats and suite-store cleanup. Every StoryHook invocation uses that captured identity, including teardown after partial setup failure.

[`fixture_story.py`](../../plugins/forge/tests/fixture_story.py) validates the identity, builds the private environment and removes inherited credentials, control overrides and Git redirection. Normal `daemon stop` writes to a regular log file and has a fixed ten-second client deadline. Missing identity, nonzero stop or timeout fails loudly and preserves the root; only successful normal shutdown permits deletion. The helper does not force-stop a daemon or retry removal.

The following recorded commands are repository-root equivalents; local executable paths are normalized. Each run used a bounded supervisor and an exclusive shared test-lane lock.

| Command | Invocation |
|---|---|
| C1 | `make test validate-release` |
| C2 | `python3 -B -S plugins/forge/tests/codex_fixture_lifecycle_test.py FixtureLifecycle.test_workspace_owner_is_quiescent_before_fixture_deletion` |
| C3 | `python3 -B -S -m unittest discover -s plugins/forge/tests -p codex_fixture_lifecycle_test.py -v` |
| C4 | `bats plugins/forge/bin/forge-storyhook-setup-contract.bats` |
| C5 | `env FORGE_SETUP_SKILL="$PWD/plugins/forge/codex/skills/decompose/SKILL.md" bats plugins/forge/bin/forge-storyhook-setup-contract.bats` |

Durations below are supervisor elapsed time, not summed test-case time. C2 ran the preserved pre-fix regression; it is historical evidence, not a claim that the current test should fail.

| Run | Command | Result | Duration | Log SHA-256 |
|---|---|---|---:|---|
| `RELEASE-GATE-01` | C1 | Failed, exit 2; historical gate remains failed | 1015.714802 s | `2780a8eb5b71a902133dbc6bb0c02b9e4286c7bd5ca35cc67cece7bbf76001cb` |
| `FORGE-LIFECYCLE-RED-02` | C2 | Expected lifecycle assertion failure, exit 1 | 1.976013 s | `8f22b0afcdcce15f96d6863583528a44c671e15971a7b4b504b16b00bde7f308` |
| `FORGE-LIFECYCLE-GREEN-01` | C3 | Passed, exit 0; six methods/seven scenarios | 23.033052 s | `f38f4f2f0ad07992e37ade170bfd1cbf112fbecf53463cf0cdef9c4bee08cfc6` |
| `FORGE-LIFECYCLE-REAL-CLAUDE-01` | C4 | Passed, exit 0; five real CLI cases | 3.361031 s | `6c34b817a63f82ab0f0abb34248ebb07bee7447744b5a0b3a5c1341a9903fadd` |
| `FORGE-LIFECYCLE-REAL-CODEX-01` | C5 | Passed, exit 0; five real CLI cases | 3.485029 s | `6c34b817a63f82ab0f0abb34248ebb07bee7447744b5a0b3a5c1341a9903fadd` |

The regression ran at 00:08:55.126382–00:09:18.018782 UTC, the Claude variant at 00:09:51.894456–00:09:55.116516, and the Codex variant at 00:10:23.136066–00:10:26.478144 on 2026-10-15. Both real variants emitted identical passing TAP logs. The investigation recorded StoryHook `3.0.3 (119)`, build `e66f69a4db2e`; no historical gate-launch binary hash exists to prove byte identity across earlier runs.

All three focused runs preserved their source fingerprints, reported no supervisor errors and needed no supervisor cleanup signals. The window began at 00:08:54.671246 UTC with a 00:18:54.671246 deadline and was released at **00:10:46.498193 UTC**: 111.826948 seconds wall time, including 29.879112 seconds of combined supervisor execution. Fresh custody checks found no known owned controller/child groups, no matching test processes, no new StoryHook processes and no remaining private fixture roots; the shared lock was free. General absence of detached processes is not attested.

The suite wrapper and sibling fixtures remain outside this patch. The regression retains the repository's existing macOS temporary-path assumptions; Linux portability was not validated. No full gate, reverse-intervention run, release, installation or merge followed the repair. No issue was latched, and no issue comment was posted. Original failures and lock residue remain preserved.

## Preventative action — killing the class

[`plugins/forge/tests/codex_fixture_lifecycle_test.py`](../../plugins/forge/tests/codex_fixture_lifecycle_test.py) exercises the actual Bats fixture with an external transport stand-in and a separate owner holding a real lock. Its six named methods cover seven scenarios:

| Regression method | Enforced contract |
|---|---|
| `test_workspace_owner_is_quiescent_before_fixture_deletion` | Two successful fixtures use distinct private identities; each releases the still-linked inode before deletion. |
| `test_nonzero_stop_preserves_workspace_and_store` | A failed normal stop preserves the owned tree and store. |
| `test_stop_timeout_preserves_workspace_and_store` | The real ten-second helper deadline preserves resources while failing the fixture. |
| `test_missing_identity_preserves_workspace_without_addressing_a_daemon` | An unavailable receipt cannot authorize a stop request or deletion. |
| `test_partial_setup_drains_admitted_owner` | Failed setup still drains an owner already admitted under the private identity. |
| `test_partial_setup_and_failed_stop_preserve_admitted_owner` | Failed setup plus failed shutdown preserves the owner and its resources. |

Every scenario also checks that work and stop share the private identity, inherited control fields are removed, an independently held foreign store inode is unchanged, and the caller's tool home is preserved. Error-path preservation is asserted before test-owned cleanup.

Ordinary Forge discovery already reaches this file: [`Makefile`](../../Makefile) `test-forge` calls [`plugins/forge/tests/run-tests.sh`](../../plugins/forge/tests/run-tests.sh), which discovers [`plugins/forge/bin/forge-codex.bats`](../../plugins/forge/bin/forge-codex.bats); its `codex_*test.py` discovery includes the new regression. The actual fixture is also exercised against the real CLI for both documentation variants. These guards make deletion-before-release and wrong-instance shutdown observable within this fixture's scope; they do not certify all sibling fixtures.

## Lessons

- Capture private ownership before work can be admitted, and carry that identity through shutdown. A temporary pathname alone does not isolate a daemon or store.
- Test the resource boundary directly. A successful command or even a successful `rm` can conceal deletion of a still-owned inode.
- An uncertain shutdown must preserve evidence and resources. Keep the fixture root outside cleanup scopes that would defeat that contract.
- Keep historical attribution separate from a reproduced invariant. A focused repair can be demonstrated without claiming to know an uncaptured writer, and its passing checks cannot replace an unrun release gate.
