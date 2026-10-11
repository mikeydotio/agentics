# AGE-114 implementation report

Implemented the approved explicit `dispatch-not-sent` event in the isolated candidate only. The original reproduction now reconciles while retaining the interrupted task and absent payload. No BDocs records, installed plugins, credentials, tracker records, version files, or source-owner files were changed. No working-tree commit, native build, deployment, installation, or additional agent dispatch occurred.

## Changes

- `plugins/agents/bin/delivery_model.py`: terminal-only event admission, exact duplicate no-op/conflicting duplicate rejection, structured history append, and use of validated dispatch resolution during reconciliation. Task statuses, attempts, payloads, shutdown flags and deadlines remain unchanged.
- `plugins/agents/bin/delivery_validation.py`: exact original session/batch/task/digest/current-attempt checks; explicit true attestation; nonempty reason, evidence reference, reviewer identity and valid SHA256 syntax; rejection of known native identity, dispatch history, payload, claimed shutdown/integrity and unsupported event fields. Persisted attestations are revalidated on every read, and reconciled states with unresolved sends fail closed.
- `plugins/agents/references/delivery.md`: documents the owner attestation and its limits, same-session scope, preserved failure, duplicates and continuing shutdown/integrity/artifact-review gates.
- Corresponding runtime/docs copies under `plugins/rca` and `plugins/forge` generated with the repository sync script.
- `plugins/agents/tests/test_delivery_not_sent.py`: nine regression methods through production persistence and actual source-copy CLIs for Agents/RCA/Forge.
- `plugins/agents/tests/test_delivery_mutations.py`: five new negative controls in private copies, with an unchanged baseline, plus shell-runner coverage of the new suite leg.
- `plugins/agents/tests/test-delivery.sh`: runs the added no-send suite.

The complete 12-file list and SHA256 hashes are in `candidate-file-sha256.json`. `tracked-candidate.patch` excludes the new untracked test file, which remains present at the listed source path.

## Test evidence

All invocations below completed with exit 0, run serially with 30-second subprocess bounds:

| Command | Result |
|---|---|
| `python3 -B .rca/dispatch-not-sent-a11/repro.py` | Exact original failure now green; no successful work synthesized |
| `bash tests/with-isolated-store.sh bash plugins/agents/tests/test-delivery.sh` | 4 mutation/runner methods, 20 existing delivery methods, 9 new no-send methods; synchronized copies checked |
| `bash tests/with-isolated-store.sh bash plugins/rca/tests/test-delivery.sh` | 4 methods pass |
| `bash tests/with-isolated-store.sh bats plugins/forge/bin/forge-delivery.bats` | Both Bats wrappers pass, covering all 5 Forge production delivery methods and 2 delivery-contract methods |
| `python3 -B scripts/sync-agent-delivery.py --check` | All consumer copies identical |
| `git diff --check` | Clean |

Exact commands, exit codes and elapsed times: `focused-results-final.json`. Complete output is retained in the matching `*-final.stdout`/`*.stderr` files. Only documentation line wrapping changed after the final runtime suite; synchronization and whitespace checks were rerun.

The new methods cover both terminal failure outcomes, all three owners and both hosts; original history/task/deadline preservation; missing/wrong identity and evidence fields; stale revision; known native sends; payload injection; nonterminal/successful/reconciled refusal; same/conflicting duplicates; an unresolved second attempt; actual survivors and separate integrity/artifact gates; current versus retired reader retry identity; malformed, removed, renamed, duplicate or contradictory evidence on reload; and all three actual packaged CLIs. These are bounded protocol tests, not authentication or actual native transport proof.

## Red/green trail and limitations

Before runtime edits, `red-repro.stderr` preserves the exact uncertain-native-dispatch refusal. `red-regressions.stderr` preserves 42 failures and 3 errors from the first eight new methods against original runtime. Subsequent trigger-derived red tests exposed two additional invalid reload conditions each: claimed task shutdown/integrity (`red-stopped-integrity.stderr`) and removed/renamed evidence (`red-removed-evidence.stderr`). Both are now rejected.

The first full affected-stack attempt stopped in the new mutation harness because its output assertion expected unittest `FAIL` when a removed repair correctly produced unittest `ERROR`. That harness assertion was corrected to require explicit failed-test output, and mutation restoration moved into `finally`; no product assertion was weakened. Original failed output remains in `agents-delivery.stderr` and `focused-results.json`. The next and final complete focused stacks passed.

No deviation from approved file scope. Narrow validation was strengthened to reject impossible stopped/integrity claims on an undispatched task and to recheck unresolved sends when loading a reconciled record. The same uncertainty predicate is shared by finish and reload to avoid drift.

The recording owner attests independently reviewed evidence. The helper does not authenticate reviewer identities, dereference evidence, compare its contents to the supplied hash, or prove absence of native calls. Unknown sends and cross-session recovery remain unsupported. Independent review and actual BDocs application are still pending owner action. This is an unreleased 3.9.5-based candidate; no release/version-keyed installation is claimed.
