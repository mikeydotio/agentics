---
module: "plugins/atlas/tests (chunk 3)"
summary: "Bats tests for the tree-sitter helper, v2 update-flow economics, and the verify-cache staleness gate."
read_when: "Touching ts-helper precision, update-flow re-judging, or verify-cache"
sources:
  - path: plugins/atlas/tests/test-ts-helper.sh
    blob: bfbe414a82d20fc1fe63ab4da2ea4da05df097bd
  - path: plugins/atlas/tests/test-update-flow-v2.sh
    blob: e4bb12617e656b06bdb0f89cd231d60197e55d35
  - path: plugins/atlas/tests/test-update-flow.sh
    blob: 7c4643183c99a2ff6ce20afa169e0e7fdd6baed7
  - path: plugins/atlas/tests/test-verify-cache.sh
    blob: 75505fe992ce5ec73dff0eb3c070eca5d0a0510b
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/atlas/tests (chunk 3)

## Purpose

This chunk pins the deterministic tail of atlas v2's incremental map against real change. test-ts-helper.sh drives the actual tree-sitter backend on Swift fixtures to prove an overloaded same-named method resolves to its specific type where the regex floor can only mark the call ambiguous, and that a bare call never misresolves into a same-named method (issue #65's regression). test-update-flow(-v2).sh and test-verify-cache.sh prove the rest of the update loop's promises — zero re-judging on a pure body edit, delta-only re-judging on a real structural change, byte-identical untouched docs, mechanical renames/orphan-removal/conflict quarantine, and a repair-cache fingerprint that only invalidates on a real HEAD move or dirty tree, never on atlas's own .atlas/ runtime churn.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Api` | class | `plugins/atlas/tests/test-ts-helper.sh:209` | Fixture class whose @objc fetch() proves attribute-decorated methods still resolve via to_loc. |
| `ApiClient` | class | `plugins/atlas/tests/test-update-flow-v2.sh:22` | Baseline fixture class in the update-flow src/api module; its unedited `call()` anchors the body-edit stability tests. |
| `ApiClient` | class | `plugins/atlas/tests/test-update-flow-v2.sh:96` | Fixture class re-declared with a new `health()` method -- the structural change proven to trigger delta-only re-judging. |
| `ApiClient` | class | `plugins/atlas/tests/test-update-flow-v2.sh:123` | Same two-method fixture class re-emitted to prove editing src/api leaves the unrelated src/auth doc byte-identical. |
| `AuthService` | class | `plugins/atlas/tests/test-update-flow-v2.sh:14` | Baseline fixture class in the update-flow src/auth module; its `login`/`_sign` pair anchors the re-judging assertions. |
| `AuthService` | class | `plugins/atlas/tests/test-update-flow-v2.sh:72` | Re-emitted with only `login`'s body changed, backing the claim that a pure body edit re-judges zero cells. |
| `AuthService` | class | `plugins/atlas/tests/test-update-flow-v2.sh:141` | Re-emitted with `login`'s signature changed (added `mfa` param) -- the one case that re-judges exactly one contract cell. |
| `ComposeField` | class | `plugins/atlas/tests/test-ts-helper.sh:172` | Fixture class hosting dismiss(), proving a same-named method must NOT satisfy a bare top-level call to a free function. |
| `Engine` | class | `plugins/atlas/tests/test-ts-helper.sh:50` | Swift fixture class declaring an overloaded `run(_:)`; proves the tree-sitter backend resolves cross-file calls the regex backend can't. |
| `Pipeline` | class | `plugins/atlas/tests/test-ts-helper.sh:54` | Second Swift fixture class with its own same-named `run(_:)`, forcing `orchestrate` to disambiguate by variable type, not name. |
| `call` | def | `plugins/atlas/tests/test-update-flow-v2.sh:23` | Baseline `ApiClient.call`, a constant-returning stub whose declaration stays untouched across body-only edit tests. |
| `call` | def | `plugins/atlas/tests/test-update-flow-v2.sh:97` | Unchanged `call()` re-declared beside the new `health()`, isolating `health` as the test's only structural delta. |
| `call` | def | `plugins/atlas/tests/test-update-flow-v2.sh:124` | Unchanged `call()` re-declared again in the unrelated-doc test, confirming src/api edits don't perturb it. |
| `caller` | func | `plugins/atlas/tests/test-ts-helper.sh:215` | Fixture function whose a.fetch() call is asserted to resolve into Api.swift::fetch with confidence resolved. |
| `dismiss` | func | `plugins/atlas/tests/test-ts-helper.sh:173` | Fixture method on ComposeField; a bare dismiss() call must NOT resolve — methods aren't free-function call targets. |
| `fetch` | func | `plugins/atlas/tests/test-ts-helper.sh:211` | Fixture @objc-attributed method on Api; pins that attribute lines don't break to_loc span alignment for call resolution. |
| `health` | def | `plugins/atlas/tests/test-update-flow-v2.sh:100` | New method added to `ApiClient`; the real structural change whose contract cell is asserted to get (re-)judged. |
| `health` | def | `plugins/atlas/tests/test-update-flow-v2.sh:127` | Same new `health()` re-declared while isolating src/api's change from the untouched src/auth doc. |
| `login` | def | `plugins/atlas/tests/test-update-flow-v2.sh:15` | Baseline `AuthService.login` calling `_sign(1)`; its declaration anchors the update-flow re-judging assertions. |
| `login` | def | `plugins/atlas/tests/test-update-flow-v2.sh:73` | `login` re-declared with only its body changed (`_sign(987)`), proving a body edit alone re-judges nothing. |
| `login` | def | `plugins/atlas/tests/test-update-flow-v2.sh:142` | `login` re-declared with an added `mfa` parameter -- the signature change asserted to re-judge exactly its own contract. |
| `orchestrate` | func | `plugins/atlas/tests/test-ts-helper.sh:59` | Swift fixture function calling both classes' overloaded `run`; its edge resolution (ambiguous vs resolved) is what these tests assert. |
| `run` | func | `plugins/atlas/tests/test-ts-helper.sh:51` | Engine's fixture method; deliberately same-named as Pipeline's to force scope-based (not name-based) call resolution. |
| `run` | func | `plugins/atlas/tests/test-ts-helper.sh:55` | Pipeline's fixture method, same name/signature as Engine's, the overload the regex backend can only mark ambiguous. |
| `run` | func | `plugins/atlas/tests/test-ts-helper.sh:178` | Fixture top-level function bare-calling dismiss() and teardown(), driving the bare-call vs method-call resolution test. |
| `teardown` | func | `plugins/atlas/tests/test-ts-helper.sh:176` | Fixture top-level free function; a bare teardown() call from run() must resolve, unlike the same-pattern call to dismiss(). |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Every test in this chunk brackets itself with create_fixture_repo()/commit_all()/cleanup_fixture_repo(), an ephemeral throwaway git repo per test (plugins/atlas/tests/test-ts-helper.sh:47,71,87).
test-ts-helper.sh swaps ATLAS_TS_HELPER to a per-test wrapper binary so atlas's helper probe picks up a real tree-sitter-backed process instead of any installed one (plugins/atlas/tests/test-ts-helper.sh:36-41,78-79).
test-update-flow-v2.sh's _reproject fixes the deterministic map tail as load-bearing order: project -> ledger finalize --refresh-hashes -> index rebuild, matching the v1 protocol's finalize-then-index step (plugins/atlas/tests/test-update-flow-v2.sh:58-66).
verify-cache validity is scoped to a drift fingerprint keyed on HEAD plus working-tree dirtiness, and is explicitly proven immune to atlas's own gitignored .atlas/ runtime churn (plugins/atlas/tests/test-verify-cache.sh:91-104).

## External deps

- json — imported

## Gotchas

test-ts-helper.sh's tree-sitter regression tests SKIP silently (echo + return 0, still counted as passing) when no tree-sitter-capable Python is found, so a green run can exercise none of them locally (plugins/atlas/tests/test-ts-helper.sh:11-31).
test_ts_helper_attributed_method_still_resolves is documented as a no-op — still a valid regression guard — if the Swift grammar does not fold the @objc attribute into the method's node span (plugins/atlas/tests/test-ts-helper.sh:200-203).
