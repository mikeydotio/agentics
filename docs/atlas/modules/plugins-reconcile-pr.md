---
module: plugins/reconcile-pr
summary: "State machine that rebases a PR onto its base in an isolated worktree and force-pushes under a leased guard."
read_when: "Touching reconcile-pr's rebase machine, push guard, or conflict flow"
sources:
  - path: plugins/reconcile-pr/.claude-plugin/plugin.json
    blob: 2cb64ff6430a4bcfba162a7930b2dbdeea94b9da
  - path: plugins/reconcile-pr/README.md
    blob: f80668fbd527ffd096f174662ba67c34648f6ab5
  - path: plugins/reconcile-pr/bin/reconcile-pr.sh
    blob: e86472f23d63075a1fecd4fbe2f023d1e7e63cf7
  - path: plugins/reconcile-pr/references/reconciliation.md
    blob: 1fc5dbd0d2f4d72aa1eae200b0f67521f51fdcc4
  - path: plugins/reconcile-pr/skills/reconcile-pr/SKILL.md
    blob: ded9588eec1b3aa28930822a7ecba637a1e5cd2e
  - path: plugins/reconcile-pr/tests/fakes/gh
    blob: c4d21bf4db9d6af23e61207f862f92df9bc59268
  - path: plugins/reconcile-pr/tests/lib.sh
    blob: 5aa00bab6d36bb17467c4f2f64f4a03b49c7ed76
  - path: plugins/reconcile-pr/tests/run-tests.sh
    blob: d48bed8eb69f2f16e83eedf19aaf7aa7d10cb233
  - path: plugins/reconcile-pr/tests/test-arg-validation.sh
    blob: 53b82518eaf5b083d78f580e0aacfbeb70515309
  - path: plugins/reconcile-pr/tests/test-conflict-flow.sh
    blob: f64c6594ea3dda171972ed2102789b8262c6727b
  - path: plugins/reconcile-pr/tests/test-empty-after-resolution.sh
    blob: aa17aa4c908a0a9171745c6c3c1703a83ac6536b
  - path: plugins/reconcile-pr/tests/test-preflight.sh
    blob: c0f6056667a41cd93887837af77133bd6e439d83
  - path: plugins/reconcile-pr/tests/test-push-guard.sh
    blob: 4eb3e20ed996de92061345174f893f7e3a5bf69a
  - path: plugins/reconcile-pr/tests/test-rebase-clean.sh
    blob: 6b8b74b22557cb8042aefbfffca2702bae2df5ed
  - path: plugins/reconcile-pr/tests/test-test-gate.sh
    blob: 4b3ddc876966351dc096132b684ecaa6d44cd6de
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/reconcile-pr

## Purpose

reconcile-pr's bin/reconcile-pr.sh is a 9-subcommand deterministic state machine that rebases a stale GitHub PR branch onto its base inside an isolated git worktree, then hands the LLM only the three judgment calls a script can't make — resolving each conflict, verifying the reconciled tree, and writing the summary comment (plugins/reconcile-pr/skills/reconcile-pr/SKILL.md:13-17). The idea holding it together is defusing two ways an agent-driven rebase silently corrupts a PR: git's rebase-time HEAD/ours=base, theirs=PR inversion (relabeled base_side/pr_side so neither the script nor the model ever reasons in ours/theirs — plugins/reconcile-pr/bin/reconcile-pr.sh:33-37), and an unguarded force-push (a destination-ref check plus an explicit-OID --force-with-lease that never falls back to bare --force — plugins/reconcile-pr/bin/reconcile-pr.sh:38-42). Without this module, reconciling a conflicted PR would mean an agent resolving conflicts under git's inverted labels and force-pushing freehand — exactly the two failure modes it exists to make structurally impossible.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

State is owned per-PR under .claude/worktrees/reconcile-pr/<pr>/ (state_dir, plugins/reconcile-pr/bin/reconcile-pr.sh:107): meta.json (repo/base/head/remote_oid/base_oid, written once at start — plugins/reconcile-pr/bin/reconcile-pr.sh:364-369) plus conflicts.log. cmd_start refuses to begin if that directory already exists, so at most one reconcile is in flight per PR (plugins/reconcile-pr/bin/reconcile-pr.sh:302). The worktree is created by `git worktree add` inside cmd_start (plugins/reconcile-pr/bin/reconcile-pr.sh:358-362) and destroyed only through the single teardown() function shared by abort and cleanup (plugins/reconcile-pr/bin/reconcile-pr.sh:258-264, called at :605 and :631) — there is no other removal path. remote_oid recorded at start (plugins/reconcile-pr/bin/reconcile-pr.sh:367-369) is read back unmodified at push time (plugins/reconcile-pr/bin/reconcile-pr.sh:498) and pinned into --force-with-lease (plugins/reconcile-pr/bin/reconcile-pr.sh:547); it is never refreshed mid-flow, so a branch that moved since start always fails the lease rather than silently re-arming the guard. Each subcommand invocation is single-shot and stateless between calls — all cross-call state is the meta.json/conflicts.log/worktree triad — and every code path emits exactly one JSON object on stdout (plugins/reconcile-pr/bin/reconcile-pr.sh:11-12), funneled through the fail/refuse emitters (plugins/reconcile-pr/bin/reconcile-pr.sh:63-73).

## External deps


## Gotchas

Rebase inverts git's own ours/theirs labels — HEAD/`<<<<<<<` is the base branch and `theirs`/`>>>>>>>` is the PR's replayed commit, the opposite of `git merge` — so the script never uses those words and relabels them base_side/pr_side instead (plugins/reconcile-pr/bin/reconcile-pr.sh:33-37; spelled out with a marker table in plugins/reconcile-pr/references/reconciliation.md:20-36). A reconcile worktree shares `.git` with the main checkout but not untracked/ignored files, so RECONCILE_PR_TEST_CMD must include any dependency install (e.g. `npm ci && npm test`) or the test gate fails spuriously (plugins/reconcile-pr/references/reconciliation.md:85-87). teardown() silences ALL git output including stdout, because `git branch -D` prints "Deleted branch …" to stdout and would otherwise corrupt the caller's single-JSON-object contract (plugins/reconcile-pr/bin/reconcile-pr.sh:255-257).
