---
module: "plugins/atlas/tests (chunk 2)"
summary: "Bash tests pinning atlas-cli subcommand contracts: judgment cache, ledger, lint, lock, partition, project, migrate."
read_when: "Changing atlas-cli lint/ledger/judgment/migrate or debugging its tests"
sources:
  - path: plugins/atlas/tests/test-judgment.sh
    blob: af04c676f7be538a1a184e6ebbefb16a8b7a6524
  - path: plugins/atlas/tests/test-ledger.sh
    blob: 64f3e8c235303750f1b3e11c73d01c90000dd0fa
  - path: plugins/atlas/tests/test-lint-v2.sh
    blob: 113dbe773c1f53430dfd949550b0b7df43fcf3c9
  - path: plugins/atlas/tests/test-lint.sh
    blob: 907a2947c520f999bede2d287e078d94569efe26
  - path: plugins/atlas/tests/test-lock.sh
    blob: 9b6c39e83aab4b0db326b19e51dd4111553d463b
  - path: plugins/atlas/tests/test-map-flow-v2.sh
    blob: 4e0f08ef5185f77e818524d0080a5d29125b3ed2
  - path: plugins/atlas/tests/test-migrate.sh
    blob: f8db113200229e97180f2e6cd15d3deedee34eed
  - path: plugins/atlas/tests/test-partition.sh
    blob: 4671fae665fdc132eabd409016d982e10c51501e
  - path: plugins/atlas/tests/test-project.sh
    blob: 6d3f5f45571b8c2aa1a58ca4e40f32dde57c920c
  - path: plugins/atlas/tests/test-repair.sh
    blob: 4650cd406baa0f22472e1d9f5ffc972f752b6c67
  - path: plugins/atlas/tests/test-scan.sh
    blob: d6e16e7826cb57aed7cf3fd327a3dfd9501b2f61
  - path: plugins/atlas/tests/test-status.sh
    blob: fdde9f2ee86018efefcd6e1794a0a90d04cf1be0
  - path: plugins/atlas/tests/test-ts-helper.sh
    blob: 3db8e153f220d68e757dec015e758b14663ca956
  - path: plugins/atlas/tests/test-update-flow-v2.sh
    blob: e4bb12617e656b06bdb0f89cd231d60197e55d35
references_modules: [plugins-semver-misc]
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/atlas/tests (chunk 2)

## Purpose

This chunk of atlas-cli's bash test suite covers the Judgment Cache's per-kind invalidation keys, the blob-SHA ledger, lint v1/v2, the mkdir-atomic lock, partitioning, doc projection, v1-to-v2 migration, repair mechanics, file scanning, staleness tiers, the optional tree-sitter backend, and the full map/update flows end-to-end. Every test drives the real atlas-cli binary against throwaway git fixture repos, simulating only the cartographer's judgment output so the pipeline's own logic is never mocked. If this module vanished, atlas v2's headline claim -- a pure body edit re-judges nothing while a structural change re-judges only its delta -- and the mechanical correctness of every atlas-cli subcommand would have no regression coverage.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ApiClient` | class | `plugins/atlas/tests/test-map-flow-v2.sh:24` | Fixture class in the map-flow src/api module; `call()` cross-calls src-auth's `_sign`, the resolved edge the flow test asserts. |
| `ApiClient` | class | `plugins/atlas/tests/test-update-flow-v2.sh:22` | Baseline fixture class in the update-flow src/api module; its unedited `call()` anchors the body-edit stability tests. |
| `ApiClient` | class | `plugins/atlas/tests/test-update-flow-v2.sh:96` | Fixture class re-declared with a new `health()` method -- the structural change proven to trigger delta-only re-judging. |
| `ApiClient` | class | `plugins/atlas/tests/test-update-flow-v2.sh:123` | Same two-method fixture class re-emitted to prove editing src/api leaves the unrelated src/auth doc byte-identical. |
| `AuthService` | class | `plugins/atlas/tests/test-map-flow-v2.sh:14` | Fixture class in the map-flow src/auth module; `login()` calls the local `_sign` helper that `ApiClient.call` also invokes. |
| `AuthService` | class | `plugins/atlas/tests/test-project.sh:13` | Fixture class in the project-flow src/auth module; its public surface is asserted to render under '## Public API'. |
| `AuthService` | class | `plugins/atlas/tests/test-update-flow-v2.sh:14` | Baseline fixture class in the update-flow src/auth module; its `login`/`_sign` pair anchors the re-judging assertions. |
| `AuthService` | class | `plugins/atlas/tests/test-update-flow-v2.sh:72` | Re-emitted with only `login`'s body changed, backing the claim that a pure body edit re-judges zero cells. |
| `AuthService` | class | `plugins/atlas/tests/test-update-flow-v2.sh:141` | Re-emitted with `login`'s signature changed (added `mfa` param) -- the one case that re-judges exactly one contract cell. |
| `Engine` | class | `plugins/atlas/tests/test-ts-helper.sh:50` | Swift fixture class declaring an overloaded `run(_:)`; proves the tree-sitter backend resolves cross-file calls the regex backend can't. |
| `Pipeline` | class | `plugins/atlas/tests/test-ts-helper.sh:54` | Second Swift fixture class with its own same-named `run(_:)`, forcing `orchestrate` to disambiguate by variable type, not name. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:14` | Judgment-cache fixture class; declaration (not `run`'s body) is what its symbol.contract key derives from. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:50` | Re-declared with `run`'s body changed only, proving a pure body edit keeps the contract key stable. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:70` | Re-declared as `PublicAPI(object)` -- the added base class is what makes the contract key change. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:118` | Re-declared after `_engine` in file order, proving symbol reordering leaves module.purpose's key stable. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:208` | Re-declared as `PublicAPI(object)` again, to prove only its own contract key re-stales, leaving other cached cells intact. |
| `Service` | class | `plugins/atlas/tests/test-lint-v2.sh:23` | Fixture class in `_lint_fixture`; `start()` calls `_boot`, the private helper the v2 lint clean-map tests hinge on. |
| `Service` | class | `plugins/atlas/tests/test-migrate.sh:11` | Fixture class in the v1-mapped repo (`_v1_mapped_fixture`) whose v1 doc prose `migrate-v1` re-keys into the Judgment Cache. |
| `call` | def | `plugins/atlas/tests/test-map-flow-v2.sh:25` | Fixture method cross-calling `_sign` in src-auth; the map-flow test asserts this renders as a resolved cross-module edge. |
| `call` | def | `plugins/atlas/tests/test-update-flow-v2.sh:23` | Baseline `ApiClient.call`, a constant-returning stub whose declaration stays untouched across body-only edit tests. |
| `call` | def | `plugins/atlas/tests/test-update-flow-v2.sh:97` | Unchanged `call()` re-declared beside the new `health()`, isolating `health` as the test's only structural delta. |
| `call` | def | `plugins/atlas/tests/test-update-flow-v2.sh:124` | Unchanged `call()` re-declared again in the unrelated-doc test, confirming src/api edits don't perturb it. |
| `caller` | def | `plugins/atlas/tests/test-migrate.sh:137` | Templated fixture function (`caller$i`) generated once per sibling file so every call to `run` is deliberately ambiguous. |
| `health` | def | `plugins/atlas/tests/test-update-flow-v2.sh:100` | New method added to `ApiClient`; the real structural change whose contract cell is asserted to get (re-)judged. |
| `health` | def | `plugins/atlas/tests/test-update-flow-v2.sh:127` | Same new `health()` re-declared while isolating src/api's change from the untouched src/auth doc. |
| `login` | def | `plugins/atlas/tests/test-map-flow-v2.sh:15` | Fixture method calling the local `_sign`; establishes `AuthService` as `_sign`'s in-module caller alongside `ApiClient`. |
| `login` | def | `plugins/atlas/tests/test-project.sh:14` | Fixture method in `AuthService` calling local `_hash_token`; Load-bearing status is driven by `send`'s cross-module call, not by this one. |
| `login` | def | `plugins/atlas/tests/test-update-flow-v2.sh:15` | Baseline `AuthService.login` calling `_sign(1)`; its declaration anchors the update-flow re-judging assertions. |
| `login` | def | `plugins/atlas/tests/test-update-flow-v2.sh:73` | `login` re-declared with only its body changed (`_sign(987)`), proving a body edit alone re-judges nothing. |
| `login` | def | `plugins/atlas/tests/test-update-flow-v2.sh:142` | `login` re-declared with an added `mfa` parameter -- the signature change asserted to re-judge exactly its own contract. |
| `orchestrate` | func | `plugins/atlas/tests/test-ts-helper.sh:59` | Swift fixture function calling both classes' overloaded `run`; its edge resolution (ambiguous vs resolved) is what these tests assert. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:15` | Fixture method calling `_engine(1)`; its declaration is what `PublicAPI`'s symbol.contract key is keyed on. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:51` | Same method with only its body changed (`_engine(99999)`), used to prove pure body edits don't restale the key. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:71` | Method under the re-declared `PublicAPI(object)`; its class's changed declaration is what restales the key here. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:119` | Method re-declared after `_engine` in file order; proves reordering doesn't perturb cached keys. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:209` | Method reused under a re-declared base class to prove only this symbol's key re-stales, not the whole cache. |
| `run` | def | `plugins/atlas/tests/test-migrate.sh:134` | Fixture function duplicated verbatim across 6 sibling files, making every cross-file call to it unresolvably ambiguous. |
| `run` | func | `plugins/atlas/tests/test-ts-helper.sh:51` | Engine's fixture method; deliberately same-named as Pipeline's to force scope-based (not name-based) call resolution. |
| `run` | func | `plugins/atlas/tests/test-ts-helper.sh:55` | Pipeline's fixture method, same name/signature as Engine's, the overload the regex backend can only mark ambiguous. |
| `send` | def | `plugins/atlas/tests/test-project.sh:23` | Fixture function cross-calling src-auth's `_hash_token`; the resolved edge and the module's sole edge.semantic cell. |
| `start` | def | `plugins/atlas/tests/test-lint-v2.sh:24` | Fixture method calling `_boot(1)`; gives `_boot` a same-file public caller for the v2 lint fixture. |
| `start` | def | `plugins/atlas/tests/test-migrate.sh:12` | Fixture method of the v1 `Service` class body; the migrated round-trip contract prose belongs to `Service`, not `start`. |
| `use` | def | `plugins/atlas/tests/test-lint-v2.sh:33` | Fixture function in `other.py` importing and calling `_boot(2)`, `_boot`'s cross-file caller that v2 lint tests need. |
| `use_engine` | def | `plugins/atlas/tests/test-judgment.sh:24` | Fixture caller in `caller.py` that imports and invokes `_engine(2)`, giving `_engine` its first cross-file caller. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_boot` | def | `plugins/atlas/tests/test-lint-v2.sh:27` | Cross-file private helper called by both `Service.start` (same file) and `use` in other.py; the fixture's single referenced private symbol is what the v2 lint clean-map tests and load-bearing detection exercise. |
| `_sign` | def | `plugins/atlas/tests/test-map-flow-v2.sh:18` | Cross-module private helper: called locally by `AuthService.login` and remotely by `ApiClient.call` in src-api -- the map-flow test's canonical resolved cross-module edge and load-bearing candidate. |

## Relationships

- `plugins-atlas-tests-chunk-2.start -> plugins-semver-misc.write (calls)`
- `plugins-atlas-tests-chunk-2.use -> plugins-semver-misc.write (calls)`

## Type notes

Every test builds a disposable git fixture repo via `create_fixture_repo`/`seed_file`/`commit_all` (e.g. plugins/atlas/tests/test-ledger.sh:9) and tears it down with `cleanup_fixture_repo`; no state crosses tests. The finalize order -- `project`, then `ledger finalize --refresh-hashes`, then `index rebuild` -- is treated as load-bearing sequencing, not incidental, per `_reproject()` in plugins/atlas/tests/test-update-flow-v2.sh:61-66 and the comment at plugins/atlas/tests/test-map-flow-v2.sh:75-76. `test_lock_concurrent_single_winner` (plugins/atlas/tests/test-lock.sh:87-118) is the module's only real-concurrency test, forking 4 racer subshells under `set +e` to prove the mkdir-based lock yields exactly one winner. test-ts-helper.sh's four tests self-skip (exit 0) via `_ts_python()` (plugins/atlas/tests/test-ts-helper.sh:21-29) when no tree-sitter-capable Python is importable, keeping that compiled dependency optional for the core suite.

## External deps

- re — imported
- src.auth.service — imported
- src.core — imported
- src.svc — imported
- sys — imported

## Gotchas

The extractor treats these tests' bash-heredoc fixtures as real repo symbols: near-identical minimal fixtures recur verbatim across files (`class Service:` at plugins/atlas/tests/test-lint-v2.sh:23 and plugins/atlas/tests/test-migrate.sh:11; `class AuthService:`/`_sign` at plugins/atlas/tests/test-map-flow-v2.sh:14-18 and plugins/atlas/tests/test-update-flow-v2.sh:14-18), so any structure/fan-in view of this module is dominated by fixture-name collisions, not real production call graphs. One concrete case: `use()` at plugins/atlas/tests/test-lint-v2.sh:33 only calls `_boot`, and `start()` at plugins/atlas/tests/test-migrate.sh:12 only returns `1` -- neither calls anything named `write` -- yet each resolves in this module's structure/edge data to an unrelated `write` symbol in another plugin, the same name-collision hazard surfacing as a spurious cross-module edge.
