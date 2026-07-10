---
module: "plugins/atlas/tests (chunk 2)"
summary: "Bash CLI tests pinning atlas v2 contracts: partition, judgment, ledger, lint, project, migrate, lock, status, repair."
read_when: "Changing atlas-cli lint/ledger/judgment/migrate or debugging its tests"
sources:
  - path: plugins/atlas/tests/test-judgment-diff.sh
    blob: 0befd62aab7e2a08f9e26956f95e5f0dc94d6e79
  - path: plugins/atlas/tests/test-judgment.sh
    blob: 45cfd07fc433ffe48db7b8eb29ab15369e3c6b4b
  - path: plugins/atlas/tests/test-ledger.sh
    blob: 64f3e8c235303750f1b3e11c73d01c90000dd0fa
  - path: plugins/atlas/tests/test-lint-v2.sh
    blob: 113dbe773c1f53430dfd949550b0b7df43fcf3c9
  - path: plugins/atlas/tests/test-lint.sh
    blob: 907a2947c520f999bede2d287e078d94569efe26
  - path: plugins/atlas/tests/test-lock.sh
    blob: 9b6c39e83aab4b0db326b19e51dd4111553d463b
  - path: plugins/atlas/tests/test-map-flow-v2.sh
    blob: 2ee2facdd0c23e52e2107160fb629f88a43e78a3
  - path: plugins/atlas/tests/test-migrate.sh
    blob: f8db113200229e97180f2e6cd15d3deedee34eed
  - path: plugins/atlas/tests/test-partition.sh
    blob: 4671fae665fdc132eabd409016d982e10c51501e
  - path: plugins/atlas/tests/test-project.sh
    blob: f5ed70c14b5590486e464f91ecbd5fd4171146aa
  - path: plugins/atlas/tests/test-repair.sh
    blob: 4650cd406baa0f22472e1d9f5ffc972f752b6c67
  - path: plugins/atlas/tests/test-scan.sh
    blob: d6e16e7826cb57aed7cf3fd327a3dfd9501b2f61
  - path: plugins/atlas/tests/test-status.sh
    blob: fdde9f2ee86018efefcd6e1794a0a90d04cf1be0
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/atlas/tests (chunk 2)

## Purpose

This chunk is the bash CLI test suite pinning the behavioral contracts of atlas-cli v2's incremental-mapping engine: deterministic partitioning, the Judgment Cache (judge-plan/ingest/diff/prune/verify-set), the blob-SHA ledger (finalize/diff/set-verified), deterministic projection, lint's v1 mechanical checks plus v2 placeholder/divergence checks, migrate-v1, the mkdir-atomic lock, staleness status, and the repair/full-map-flow CLI integrations. What holds it together is proving atlas v2's core promise one orthogonal-hash invalidation case at a time — a body-only edit re-judges nothing, a signature edit re-judges exactly its own key, and a no-op pull costs zero LLM calls. If this chunk vanished, those invalidation guarantees would be unverified and free to silently regress into false-clean staleness or full re-judging on every pull.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ApiClient` | class | `plugins/atlas/tests/test-map-flow-v2.sh:24` | Fixture class in the map-flow src/api module; `call()` cross-calls src-auth's `_sign`, the resolved edge the flow test asserts. |
| `AuthService` | class | `plugins/atlas/tests/test-map-flow-v2.sh:14` | Fixture class in the map-flow src/auth module; `login()` calls the local `_sign` helper that `ApiClient.call` also invokes. |
| `AuthService` | class | `plugins/atlas/tests/test-project.sh:13` | Fixture class in the project-flow src/auth module; its public surface is asserted to render under '## Public API'. |
| `Extra` | class | `plugins/atlas/tests/test-judgment-diff.sh:112` | Fixture class appended mid-test to prove a new public capability re-triggers module.purpose plus its own contract cell. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:14` | Judgment-cache fixture class; declaration (not `run`'s body) is what its symbol.contract key derives from. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:50` | Re-declared with `run`'s body changed only, proving a pure body edit keeps the contract key stable. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:70` | Re-declared as `PublicAPI(object)` -- the added base class is what makes the contract key change. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:118` | Re-declared after `_engine` in file order, proving symbol reordering leaves module.purpose's key stable. |
| `PublicAPI` | class | `plugins/atlas/tests/test-judgment.sh:208` | Re-declared as `PublicAPI(object)` again, to prove only its own contract key re-stales, leaving other cached cells intact. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:13` | Base fixture class (svc.py) whose `start` calls `_boot`; anchors the judgment-diff no-op/body/signature-edit matrix. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:68` | Re-emitted fixture class, declaration unchanged, used to prove a pure body edit needs zero new judgment. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:88` | `(object)`-base variant proving only this symbol's contract re-judges on a public signature edit, not module prose. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:310` | Body-edit variant used to prove the ledger v2 structure block's signature_hash stays stable across a body-only edit. |
| `Service` | class | `plugins/atlas/tests/test-lint-v2.sh:23` | Fixture class in `_lint_fixture`; `start()` calls `_boot`, the private helper the v2 lint clean-map tests hinge on. |
| `Service` | class | `plugins/atlas/tests/test-migrate.sh:11` | Fixture class in the v1-mapped repo (`_v1_mapped_fixture`) whose v1 doc prose `migrate-v1` re-keys into the Judgment Cache. |
| `Store` | class | `plugins/atlas/tests/test-judgment-diff.sh:336` | Store(req) only guarantees construction; the class body is `pass` — no state, method, or behavior is exposed to callers. |
| `call` | def | `plugins/atlas/tests/test-map-flow-v2.sh:25` | Fixture method cross-calling `_sign` in src-auth; the map-flow test asserts this renders as a resolved cross-module edge. |
| `caller` | def | `plugins/atlas/tests/test-migrate.sh:137` | Templated fixture function (`caller$i`) generated once per sibling file so every call to `run` is deliberately ambiguous. |
| `handle` | def | `plugins/atlas/tests/test-judgment-diff.sh:342` | Fixture def calling `save` across modules (web to store), the resolved cross-module call seeding an edge.semantic key. |
| `handle` | def | `plugins/atlas/tests/test-judgment-diff.sh:379` | Caller-body-edited variant proving a change to the calling code re-keys its edge.semantic cell and orphans the old key. |
| `handle` | def | `plugins/atlas/tests/test-judgment-diff.sh:401` | Call-removed variant proving dropping a cross-module call retires the edge.semantic requirement and orphans its cell. |
| `login` | def | `plugins/atlas/tests/test-map-flow-v2.sh:15` | Fixture method calling the local `_sign`; establishes `AuthService` as `_sign`'s in-module caller alongside `ApiClient`. |
| `login` | def | `plugins/atlas/tests/test-project.sh:14` | Fixture method in `AuthService` calling local `_hash_token`; Load-bearing status is driven by `send`'s cross-module call, not by this one. |
| `ping` | def | `plugins/atlas/tests/test-judgment-diff.sh:113` | Trivial fixture method (`Extra.ping`) added only to trigger the new-public-symbol judgment-diff path; no real callers. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:15` | Fixture method calling `_engine(1)`; its declaration is what `PublicAPI`'s symbol.contract key is keyed on. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:51` | Same method with only its body changed (`_engine(99999)`), used to prove pure body edits don't restale the key. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:71` | Method under the re-declared `PublicAPI(object)`; its class's changed declaration is what restales the key here. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:119` | Method re-declared after `_engine` in file order; proves reordering doesn't perturb cached keys. |
| `run` | def | `plugins/atlas/tests/test-judgment.sh:209` | Method reused under a re-declared base class to prove only this symbol's key re-stales, not the whole cache. |
| `run` | def | `plugins/atlas/tests/test-migrate.sh:134` | Fixture function duplicated verbatim across 6 sibling files, making every cross-file call to it unresolvably ambiguous. |
| `send` | def | `plugins/atlas/tests/test-project.sh:23` | Fixture function cross-calling src-auth's `_hash_token`; the resolved edge and the module's sole edge.semantic cell. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:14` | Fixture method calling `_boot`; the intra-module call whose hash stability anchors the diff-engine's body/sig-edit tests. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:69` | Re-emitted `start` method (declaration unchanged) used in the zero-judgment body-edit test. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:89` | `start` method under the `(object)`-base signature-edit variant; its call to `_boot` is unaffected. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:311` | `start` method in the structure-digest test's body-edit variant, still calling `_boot(123456)`. |
| `start` | def | `plugins/atlas/tests/test-lint-v2.sh:24` | Fixture method calling `_boot(1)`; gives `_boot` a same-file public caller for the v2 lint fixture. |
| `start` | def | `plugins/atlas/tests/test-migrate.sh:12` | Fixture method of the v1 `Service` class body; the migrated round-trip contract prose belongs to `Service`, not `start`. |
| `use` | def | `plugins/atlas/tests/test-judgment-diff.sh:23` | Fixture def calling `_boot` from a second file; its later deletion orphans a cached judgment cell in the diff tests. |
| `use` | def | `plugins/atlas/tests/test-lint-v2.sh:33` | Fixture function in `other.py` importing and calling `_boot(2)`, `_boot`'s cross-file caller that v2 lint tests need. |
| `use_Engine` | def | `plugins/atlas/tests/test-judgment.sh:24` | use_Engine() returns a fresh `_Engine(2)` instance each call; it exists only to give `_Engine` a resolved cross-file caller. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `_boot` | def | `plugins/atlas/tests/test-lint-v2.sh:27` | Cross-file private helper called by both `Service.start` (same file) and `use` in other.py; the fixture's single referenced private symbol is what the v2 lint clean-map tests and load-bearing detection exercise. |

## Relationships

## Type notes

Structure extraction over this chunk indexes the Python source embedded in `<<'PY'` heredocs inside fixture-builder functions (e.g. plugins/atlas/tests/test-judgment-diff.sh:12-19, plugins/atlas/tests/test-map-flow-v2.sh:13-20) — classes like `Service`/`AuthService`/`Store` and functions like `handle`/`use` are fixture code under test, not real atlas-cli symbols; the `.sh` files themselves are pure bash.
Partition caps asserted throughout: min_files=3, max_files=15, max_bytes=120000, and `seed_file` defaults to 100-byte files so file-count caps (not byte caps) dominate unless a test seeds large files explicitly (plugins/atlas/tests/test-partition.sh:4-6, plugins/atlas/tests/test-partition.sh:91-104).
Staleness tiers are percentage-of-stale-docs thresholds pinned via a 5-module fixture so boundaries land cleanly: 20% stale -> tier 1, 40% -> tier 2, 60% -> tier 3, and any conflict marker forces tier 3 regardless of percentage (plugins/atlas/tests/test-status.sh:4-5, plugins/atlas/tests/test-status.sh:95-105).
test-repair.sh exercises only the deterministic CLI surface the /atlas repair skill depends on (branch naming, `ledger finalize --except`, the lint commit gate); the map-repairer agent's doc edits are simulated by rewriting doc bodies directly with sed/heredocs rather than spawning the real agent (plugins/atlas/tests/test-repair.sh:2-6).

## External deps

- re — imported
- src.auth.service — imported
- src.core — imported
- src.store.db — imported
- src.svc — imported
- sys — imported

## Gotchas

test-lock.sh's concurrency test wraps each racer in `set +e` because the shared harness runs under `set -e`, and a losing racer's expected nonzero exit would otherwise abort the whole suite (plugins/atlas/tests/test-lock.sh:99-101).
test_ledger_unicode_frontmatter_round_trips pins that repeated ledger-finalize/set-verified cycles must not turn an em-dash into a `\u2014` escape in frontmatter — guarding a real unicode round-trip bug class (plugins/atlas/tests/test-ledger.sh:256-277).
