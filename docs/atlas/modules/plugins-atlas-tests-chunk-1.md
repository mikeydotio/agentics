---
module: "plugins/atlas/tests (chunk 1)"
summary: "Bash test suite covering atlas-cli extraction, hooks, INDEX/CLAUDE.md wiring, and the judgment-diff update engine."
read_when: "Changing atlas-cli or hook behavior, or writing/debugging atlas plugin tests"
sources:
  - path: plugins/atlas/tests/helpers/setup.sh
    blob: 67dcb11d42fa2aa4316c6d95170130c6e0169ee8
  - path: plugins/atlas/tests/run-tests.sh
    blob: febae8f36c0646a382a834d4bb81fac24f7ba8fb
  - path: plugins/atlas/tests/test-branch.sh
    blob: 2445f98bad189f0e3461ab325f2b02324d1e0e53
  - path: plugins/atlas/tests/test-commit.sh
    blob: e5409959bdfdd6ce369bef3f40d7ff0374b5ae22
  - path: plugins/atlas/tests/test-config.sh
    blob: 3e6b9d603355aaf173afd3f738637f4bb78f429d
  - path: plugins/atlas/tests/test-diffpack.sh
    blob: a3bce143e30dbdef734d31c870c6ebbf696d6ced
  - path: plugins/atlas/tests/test-doc.sh
    blob: a8fb82305896d7e1549bd0e213205fb5357c7012
  - path: plugins/atlas/tests/test-edge-cases.sh
    blob: 14b3fdae7719dd7bf5bec8ac8d5284a30e604a67
  - path: plugins/atlas/tests/test-extract-edges.sh
    blob: 02376b2a1f2fcd55a3c88775ea81ae111ef33057
  - path: plugins/atlas/tests/test-extract-treesitter.sh
    blob: 456d17db2d4b7c394e45ae3cecf0741c2abb0c32
  - path: plugins/atlas/tests/test-extract.sh
    blob: 6a4177f8d8b93db9a83b5fb5a640c1b1c89862ef
  - path: plugins/atlas/tests/test-hook.sh
    blob: 5545302a4317791ae60c63e45833dc34b822636f
  - path: plugins/atlas/tests/test-index.sh
    blob: 2874a1bcef0889b9e18d91f93c60b3737404f665
  - path: plugins/atlas/tests/test-init.sh
    blob: 1f85b244ea31d8dae57fbb880aad83337d1938f1
  - path: plugins/atlas/tests/test-judgment-diff.sh
    blob: 3e287756d3adcf77a4d8e6ca122b657d797a6913
references_modules: [plugins-semver-misc]
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/atlas/tests (chunk 1)

## Purpose

This chunk of the atlas plugin's bash test suite exercises atlas-cli's git/branch/commit plumbing, config parsing, the deterministic Structure Index (regex and tree-sitter backends, edge resolution, hash stability), the session-start staleness hook, INDEX/CLAUDE.md wiring, and the Ledger v2 judgment-diff/verify-set update engine — all driven through throwaway git fixture repos built with the shared helpers in helpers/setup.sh and discovered by run-tests.sh. What holds it together is the fixture-and-assertion contract (create_fixture_repo/run_atlas/assert_json_field) every test_*.sh file builds on, so each test asserts atlas-cli's JSON output shape without duplicating repo setup. If this chunk vanished, atlas-cli's core extraction guarantees — resolved-vs-ambiguous edges, signature/span hash independence, zero-LLM no-op pulls — would have no regression coverage.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AuthenticationService` | class | `plugins/atlas/tests/test-extract.sh:15` | Base fixture class (service.py) whose span covers its `login` method; anchors extract's span/signature hash-stability tests. |
| `AuthenticationService` | class | `plugins/atlas/tests/test-extract.sh:172` | Body-edit re-emission of the base fixture class (declaration unchanged); proves span_hash moves while signature_hash stays put. |
| `AuthenticationService` | class | `plugins/atlas/tests/test-extract.sh:204` | Declaration-edited variant (adds `(object)` base) proving signature_hash changes when the class declaration itself changes. |
| `Extra` | class | `plugins/atlas/tests/test-judgment-diff.sh:112` | Fixture class appended mid-test to prove a new public capability re-triggers module.purpose plus its own contract cell. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:13` | Base fixture class (svc.py) whose `start` calls `_boot`; anchors the judgment-diff no-op/body/signature-edit matrix. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:68` | Re-emitted fixture class, declaration unchanged, used to prove a pure body edit needs zero new judgment. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:88` | `(object)`-base variant proving only this symbol's contract re-judges on a public signature edit, not module prose. |
| `Service` | class | `plugins/atlas/tests/test-judgment-diff.sh:310` | Body-edit variant used to prove the ledger v2 structure block's signature_hash stays stable across a body-only edit. |
| `Svc` | struct | `plugins/atlas/tests/test-extract.sh:74` | Swift fixture struct wrapping `run(source:from:)`, guarding against parameter labels being misread as import statements. |
| `TokenStore` | class | `plugins/atlas/tests/test-extract.sh:23` | Standalone fixture class (tokens.py) padding the two-module extract fixture; unrelated to AuthenticationService. |
| `caller_one` | def | `plugins/atlas/tests/test-extract-edges.sh:21` | Fixture def (heredoc a.py) calling `unique_target` once, proving a uniquely-named callee resolves to one edge. |
| `caller_two` | def | `plugins/atlas/tests/test-extract-edges.sh:34` | Fixture def calling `dup`, which is declared in two files, proving duplicate names produce an ambiguous (not resolved) edge. |
| `docs` | module | `plugins/atlas/tests/test-extract.sh:238` | Not real code — markdown prose ('module docs describe the service.') the extractor's self-scan of this file mistakes for a module symbol. |
| `dup` | def | `plugins/atlas/tests/test-extract-edges.sh:26` | First of two identically-named fixture defs (b.py) that make calls to `dup` resolve as ambiguous, never a single target. |
| `dup` | def | `plugins/atlas/tests/test-extract-edges.sh:30` | Second identically-named fixture def (c.py); together with dup/b.py it forces `caller_two`'s call to `dup` ambiguous. |
| `fenced_example` | def | `plugins/atlas/tests/test-extract.sh:241` | Fenced-code-block fixture def proving extract must skip markdown code fences; extraction noise when atlas maps its own tests. |
| `handle` | def | `plugins/atlas/tests/test-judgment-diff.sh:342` | Fixture def calling `save` across modules (web to store), the resolved cross-module call seeding an edge.semantic key. |
| `handle` | def | `plugins/atlas/tests/test-judgment-diff.sh:379` | Caller-body-edited variant proving a change to the calling code re-keys its edge.semantic cell and orphans the old key. |
| `handle` | def | `plugins/atlas/tests/test-judgment-diff.sh:401` | Call-removed variant proving dropping a cross-module call retires the edge.semantic requirement and orphans its cell. |
| `helper` | def | `plugins/atlas/tests/test-extract.sh:19` | Fixture def calling `AuthenticationService()`, the base-variant companion used across the hash-stability test matrix. |
| `helper` | def | `plugins/atlas/tests/test-extract.sh:176` | Body-edit-variant companion to AuthenticationService, unchanged from the base fixture's `helper`. |
| `helper` | def | `plugins/atlas/tests/test-extract.sh:208` | Declaration-edit-variant companion to AuthenticationService, unchanged from the base fixture's `helper`. |
| `login` | def | `plugins/atlas/tests/test-extract.sh:16` | Fixture method calling `client.send("login")`, exercising extract's resolved cross-module edge from auth to api. |
| `login` | def | `plugins/atlas/tests/test-extract.sh:173` | Body-edit variant of the `login` method; its declaration is unchanged so signature_hash must stay stable. |
| `login` | def | `plugins/atlas/tests/test-extract.sh:205` | Re-declared `login` method under the `(object)`-base variant, used to prove signature_hash changes on declaration edits. |
| `never_called` | def | `plugins/atlas/tests/test-extract-edges.sh:47` | Uncalled fixture def establishing the baseline empty-set incident_edge_digest for symbols with zero resolved callers. |
| `orchestrate` | def | `plugins/atlas/tests/test-extract-treesitter.sh:73` | Fixture def whose call to `process` the stub tree-sitter helper scope-resolves via `to`, promoting it from ambiguous to resolved. |
| `ping` | def | `plugins/atlas/tests/test-judgment-diff.sh:113` | Trivial fixture method (`Extra.ping`) added only to trigger the new-public-symbol judgment-diff path; no real callers. |
| `process` | def | `plugins/atlas/tests/test-extract-treesitter.sh:65` | One of two same-named fixture defs (api.py); only tree-sitter's `to` field, not regex, distinguishes it from process#2. |
| `process` | def | `plugins/atlas/tests/test-extract-treesitter.sh:69` | Second same-named fixture def (worker.py) that keeps a regex-only call to `process` ambiguous absent tree-sitter's `to`. |
| `recurse` | def | `plugins/atlas/tests/test-extract-edges.sh:39` | Self-recursive fixture def proving self-calls are never recorded as an edge (no symbol-to-itself edge). |
| `run` | func | `plugins/atlas/tests/test-extract.sh:75` | Swift fixture method with parameter labels `source:`/`from:` that extract must not misparse as an import. |
| `save` | def | `plugins/atlas/tests/test-judgment-diff.sh:336` | Fixture def (store/db.py) called cross-module by `handle`; the resolved target feeding the edge.semantic judgment test. |
| `send` | def | `plugins/atlas/tests/test-extract.sh:29` | Fixture def (client.py) returning `AuthenticationService`, the resolved cross-module target reached from auth's `login`. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:14` | Fixture method calling `_boot`; the intra-module call whose hash stability anchors the diff-engine's body/sig-edit tests. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:69` | Re-emitted `start` method (declaration unchanged) used in the zero-judgment body-edit test. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:89` | `start` method under the `(object)`-base signature-edit variant; its call to `_boot` is unaffected. |
| `start` | def | `plugins/atlas/tests/test-judgment-diff.sh:311` | `start` method in the structure-digest test's body-edit variant, still calling `_boot(123456)`. |
| `unique_target` | def | `plugins/atlas/tests/test-extract-edges.sh:18` | Uniquely-named fixture def called once by `caller_one`, the canonical resolved-edge case for extract's resolver. |
| `unrelated_addition` | def | `plugins/atlas/tests/test-extract.sh:146` | Fixture def appended to a different file, proving an unrelated edit leaves another symbol's span_hash unchanged. |
| `use` | def | `plugins/atlas/tests/test-judgment-diff.sh:23` | Fixture def calling `_boot` from a second file; its later deletion orphans a cached judgment cell in the diff tests. |
| `uses_external` | def | `plugins/atlas/tests/test-extract-edges.sh:42` | Fixture def calling an undefined name, proving calls to unresolved symbols are dropped, not marked ambiguous. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `plugins-atlas-tests-chunk-1.ping -> plugins-semver-misc.set (calls)`

## Type notes

- Fixture repos are created via create_fixture_repo() in throwaway /tmp dirs — never $TMPDIR, which macOS Spotlight indexes and can stall file-heavy tests (plugins/atlas/tests/helpers/setup.sh:10-14).
- cleanup_fixture_repo() only rm -rf's paths matching /tmp/atlas-tests-* (plugins/atlas/tests/helpers/setup.sh:67-72), a path-prefix guard against deleting the wrong directory.
- Each test_* function runs in its own subshell inside run_test_file (plugins/atlas/tests/run-tests.sh:44-49), and test function names are unset after each file to prevent cross-file contamination (plugins/atlas/tests/run-tests.sh:65-67).
- Two module-doc fixture writers exist at different completeness tiers: write_module_doc() (frontmatter-only, intentionally lint-L1-failing) versus write_full_module_doc() (the complete canonical skeleton) — plugins/atlas/tests/helpers/setup.sh:78,146.

## External deps

- Foundation — imported
- json — imported
- os — imported
- src.api — imported
- src.auth.service — imported
- src.store.db — imported
- src.svc — imported
- sys — imported
- the — imported

## Gotchas

- test-extract.sh embeds markdown/Python fixture text (`module docs describe the service.` at plugins/atlas/tests/test-extract.sh:238, `def fenced_example():` at plugins/atlas/tests/test-extract.sh:241) specifically to prove extract skips markdown defs (test_extract_skips_markdown_defs, plugins/atlas/tests/test-extract.sh:233-254) — yet atlas's own self-map of this repo can pick up these same fixture strings as spurious symbols, since the extractor has no way to know a .sh file's heredoc content isn't real code.
- test_commit_retries_through_transient_index_lock (plugins/atlas/tests/test-commit.sh:76-90) races a backgrounded `rm` (0.8s sleep) against atlas-cli's internal index.lock backoff — a timing-sensitive test that could flake on a loaded CI runner.
