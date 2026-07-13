---
module: "plugins/atlas/tests (chunk 1)"
summary: "Bash test suite for atlas-cli git/config/extract/covers/diffpack/doc/index/init/hook behaviors."
read_when: "Changing atlas-cli behavior or writing/debugging atlas plugin tests"
sources:
  - path: plugins/atlas/tests/helpers/setup.sh
    blob: 96567a779d4fb3e2362c930d986faf2ec0071a2d
  - path: plugins/atlas/tests/run-tests.sh
    blob: febae8f36c0646a382a834d4bb81fac24f7ba8fb
  - path: plugins/atlas/tests/test-branch.sh
    blob: 2445f98bad189f0e3461ab325f2b02324d1e0e53
  - path: plugins/atlas/tests/test-commit.sh
    blob: e5409959bdfdd6ce369bef3f40d7ff0374b5ae22
  - path: plugins/atlas/tests/test-config.sh
    blob: 3e6b9d603355aaf173afd3f738637f4bb78f429d
  - path: plugins/atlas/tests/test-covers.sh
    blob: 033151338295a689fa08a1f864a905579710f00f
  - path: plugins/atlas/tests/test-diffpack.sh
    blob: a3bce143e30dbdef734d31c870c6ebbf696d6ced
  - path: plugins/atlas/tests/test-doc.sh
    blob: a8fb82305896d7e1549bd0e213205fb5357c7012
  - path: plugins/atlas/tests/test-edge-cases.sh
    blob: 14b3fdae7719dd7bf5bec8ac8d5284a30e604a67
  - path: plugins/atlas/tests/test-extract-edges.sh
    blob: 7bb385266753a6609c2b1173ecd2213cebb2ed47
  - path: plugins/atlas/tests/test-extract-treesitter.sh
    blob: 1f22c836c2c3e76c85ea125bdc0c3659f5d7bf32
  - path: plugins/atlas/tests/test-extract.sh
    blob: 6a4177f8d8b93db9a83b5fb5a640c1b1c89862ef
  - path: plugins/atlas/tests/test-hook.sh
    blob: 5545302a4317791ae60c63e45833dc34b822636f
  - path: plugins/atlas/tests/test-index.sh
    blob: 6a1cb880ea30f63346165f476b75dcf39fc57245
  - path: plugins/atlas/tests/test-init.sh
    blob: e49e647be93e9eaa3a2eb2884ce58f4b11963e14
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/atlas/tests (chunk 1)

## Purpose

This is the bash test suite for atlas-cli's deterministic, non-LLM subcommands — git branch/commit safety, config parsing, structure extraction (edge-confidence tiers, tree-sitter fallback, orthogonal hashes), coverage/staleness reporting, doc mutation, INDEX assembly, CLAUDE.md init/remove, and the SessionStart staleness hook. Each test spins up a throwaway git fixture repo, drives atlas-cli through run_atlas, and asserts exact JSON error codes and field values (not just exit codes), because those JSON contracts are what forge/atlas orchestrator skills and cartographer agents depend on. Losing this coverage would let regressions in edge resolution, cache determinism, or the mid-merge/non-git refusal contracts silently corrupt a committed map or swallow a user's staged git work.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AuthenticationService` | class | `plugins/atlas/tests/test-extract.sh:15` | Base fixture class (service.py) whose span covers its `login` method; anchors extract's span/signature hash-stability tests. |
| `AuthenticationService` | class | `plugins/atlas/tests/test-extract.sh:172` | Body-edit re-emission of the base fixture class (declaration unchanged); proves span_hash moves while signature_hash stays put. |
| `AuthenticationService` | class | `plugins/atlas/tests/test-extract.sh:204` | Declaration-edited variant (adds `(object)` base) proving signature_hash changes when the class declaration itself changes. |
| `Svc` | struct | `plugins/atlas/tests/test-extract.sh:74` | Swift fixture struct wrapping `run(source:from:)`, guarding against parameter labels being misread as import statements. |
| `TokenStore` | class | `plugins/atlas/tests/test-extract.sh:23` | Standalone fixture class (tokens.py) padding the two-module extract fixture; unrelated to AuthenticationService. |
| `UniqueType` | class | `plugins/atlas/tests/test-extract-edges.sh:20` | Heredoc fixture class: a unique TYPE name resolves to a `calls` edge from caller_one (test_resolved_edge_for_unique_type_name). |
| `caller_func` | def | `plugins/atlas/tests/test-extract-edges.sh:29` | Heredoc fixture proving a corpus-unique FUNC name produces no resolved edge, unlike a unique TYPE (issue #65). |
| `caller_one` | def | `plugins/atlas/tests/test-extract-edges.sh:26` | Fixture def (heredoc a.py) calling `unique_target` once, proving a uniquely-named callee resolves to one edge. |
| `caller_two` | def | `plugins/atlas/tests/test-extract-edges.sh:42` | Fixture def calling `dup`, which is declared in two files, proving duplicate names produce an ambiguous (not resolved) edge. |
| `docs` | module | `plugins/atlas/tests/test-extract.sh:238` | Not real code — markdown prose ('module docs describe the service.') the extractor's self-scan of this file mistakes for a module symbol. |
| `dup` | def | `plugins/atlas/tests/test-extract-edges.sh:34` | First of two identically-named fixture defs (b.py) that make calls to `dup` resolve as ambiguous, never a single target. |
| `dup` | def | `plugins/atlas/tests/test-extract-edges.sh:38` | Second identically-named fixture def (c.py); together with dup/b.py it forces `caller_two`'s call to `dup` ambiguous. |
| `fenced_example` | def | `plugins/atlas/tests/test-extract.sh:241` | Fenced-code-block fixture def proving extract must skip markdown code fences; extraction noise when atlas maps its own tests. |
| `helper` | def | `plugins/atlas/tests/test-extract.sh:19` | Fixture def calling `AuthenticationService()`, the base-variant companion used across the hash-stability test matrix. |
| `helper` | def | `plugins/atlas/tests/test-extract.sh:176` | Body-edit-variant companion to AuthenticationService, unchanged from the base fixture's `helper`. |
| `helper` | def | `plugins/atlas/tests/test-extract.sh:208` | Declaration-edit-variant companion to AuthenticationService, unchanged from the base fixture's `helper`. |
| `login` | def | `plugins/atlas/tests/test-extract.sh:16` | Fixture method calling `client.send("login")`, exercising extract's resolved cross-module edge from auth to api. |
| `login` | def | `plugins/atlas/tests/test-extract.sh:173` | Body-edit variant of the `login` method; its declaration is unchanged so signature_hash must stay stable. |
| `login` | def | `plugins/atlas/tests/test-extract.sh:205` | Re-declared `login` method under the `(object)`-base variant, used to prove signature_hash changes on declaration edits. |
| `never_called` | def | `plugins/atlas/tests/test-extract-edges.sh:55` | Uncalled fixture def establishing the baseline empty-set incident_edge_digest for symbols with zero resolved callers. |
| `orchestrate` | def | `plugins/atlas/tests/test-extract-treesitter.sh:73` | Fixture def whose call to `process` the stub tree-sitter helper scope-resolves via `to`, promoting it from ambiguous to resolved. |
| `process` | def | `plugins/atlas/tests/test-extract-treesitter.sh:65` | One of two same-named fixture defs (api.py); only tree-sitter's `to` field, not regex, distinguishes it from process#2. |
| `process` | def | `plugins/atlas/tests/test-extract-treesitter.sh:69` | Second same-named fixture def (worker.py) that keeps a regex-only call to `process` ambiguous absent tree-sitter's `to`. |
| `recurse` | def | `plugins/atlas/tests/test-extract-edges.sh:47` | Self-recursive fixture def proving self-calls are never recorded as an edge (no symbol-to-itself edge). |
| `run` | func | `plugins/atlas/tests/test-extract.sh:75` | Swift fixture method with parameter labels `source:`/`from:` that extract must not misparse as an import. |
| `send` | def | `plugins/atlas/tests/test-extract.sh:29` | Fixture def (client.py) returning `AuthenticationService`, the resolved cross-module target reached from auth's `login`. |
| `unique_func` | def | `plugins/atlas/tests/test-extract-edges.sh:23` | Heredoc fixture function; called only by caller_func to test that unique FUNC names are excluded from resolved edges (issue #65). |
| `unrelated_addition` | def | `plugins/atlas/tests/test-extract.sh:146` | Fixture def appended to a different file, proving an unrelated edit leaves another symbol's span_hash unchanged. |
| `uses_external` | def | `plugins/atlas/tests/test-extract-edges.sh:50` | Fixture def calling an undefined name, proving calls to unresolved symbols are dropped, not marked ambiguous. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Fixture repos are throwaway git repos created under /tmp — never $TMPDIR, since macOS Spotlight indexes $TMPDIR and file-heavy fixture trees eventually stall test runs (plugins/atlas/tests/helpers/setup.sh:10-14). cleanup_fixture_repo only rm -rf's paths matching /tmp/atlas-tests-* as a safety guard against deleting anything else (plugins/atlas/tests/helpers/setup.sh:67-72). Each discovered test_* function runs in its own subshell for isolation and is unset afterward so state and function names never leak across test files (plugins/atlas/tests/run-tests.sh:43-49, plugins/atlas/tests/run-tests.sh:64-67).

## External deps

- Foundation — imported
- json — imported
- os — imported
- src.api — imported
- src.auth.service — imported
- sys — imported
- the — imported

## Gotchas

Fixture repos live under /tmp (not $TMPDIR) specifically to dodge macOS Spotlight's indexing stalls on file-heavy fixture trees (plugins/atlas/tests/helpers/setup.sh:10-14). test-extract-edges.sh embeds Python fixture source in a bash heredoc (`class UniqueType:` at plugins/atlas/tests/test-extract-edges.sh:20); atlas's own regex extractor, when run over this test module, parses that heredoc content as real .sh-file symbols since it doesn't understand shell heredocs. test_commit_retries_through_transient_index_lock races a background `rm` against atlas-cli's internal retry backoff using a fixed 0.8s sleep — a timing-dependent test (plugins/atlas/tests/test-commit.sh:76-90).
