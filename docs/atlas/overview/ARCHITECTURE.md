---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: 26f5baa88725df5adc0e9c78de7843ff9a1042e2
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: ca030670e871f62db7b140b41cb28826dbcd952b
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: 54aaf6c336b4983457db178c8b30c16531f13d38
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: c01f936bc20b66925ad2801c4be17e3161d9a289
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: 05d36f4cfa2e299646dda9b62cf600ff94bba650
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: 1eff07f91f67d123c4f55dee199f6c493d81c8b2
  - path: docs/atlas/modules/plugins-atlas-agent-overrides.md
    blob: 4d1dad48609393ef8311cfcbc65966b1bb38febe
  - path: docs/atlas/modules/plugins-atlas-bin-chunk-1.md
    blob: e2b19fb5988ab633012d76931631e82b5872ed72
  - path: docs/atlas/modules/plugins-atlas-bin-chunk-2.md
    blob: 6d8aab0ab6b3ac819c4a5205fb9c8ad7f6ce9096
  - path: docs/atlas/modules/plugins-atlas-helpers-ts-helper.md
    blob: 469d365d7180e706259a5a323708beaa21ccc97f
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: 63591ba20c998f3a35a57d796c909e1de75df00b
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 3ee390a3ede83da8fce921a6529154456831a447
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-1.md
    blob: 1d4798201c1ad94362c47a560dc5ded9a0081917
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-2.md
    blob: 8a7cf46ec3fc63ccb251851ada2432638341b79a
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-3.md
    blob: bdbebf3c665e85168dcce04beb45ea1488e42e04
  - path: docs/atlas/modules/plugins-council.md
    blob: 4eba0787fdd5f846c07e65313ee6b075f21475d2
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: aa6ce2aee689858c7491087d56ccb44c63310dfa
  - path: docs/atlas/modules/plugins-deployit-bin-chunk-1.md
    blob: 345b9e98fd4cb52c0f9485820913487e0e1dbeeb
  - path: docs/atlas/modules/plugins-deployit-bin-chunk-2.md
    blob: e4a4c85f1bd7fac93142dd5d1512659ca1bd4c06
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: b45370230a4c8f6f1d58f4cbe2be77e8b5b8dd2e
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: ccc52d0b57d350979ca6e0d662476118db0e9b61
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: 85887614887ce17e4167be7951ebd57239721687
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 03a27f5326decdedb5fd20a6bfb6e435cd74067f
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-3.md
    blob: 16b6f14379ff3be787209cd621115a21cfb7d99b
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: 93a5f727595bcce96a6efa407304e2d7f2930db3
  - path: docs/atlas/modules/plugins-forge-bin-chunk-1.md
    blob: 36909a7a18e7b8f82ca7a55d57b475b8dacd6098
  - path: docs/atlas/modules/plugins-forge-bin-chunk-2.md
    blob: 51070b3ccc9078b160fe5ce04283f7fd98293cc4
  - path: docs/atlas/modules/plugins-forge-bin-chunk-3.md
    blob: 33d934c408257859bfd504b00308a22612425f58
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: 966b4c064d43f9460289aa22e7debce4a30704f5
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: bb204f8164e2a90ece605752cd4ac73f19dbbad5
  - path: docs/atlas/modules/plugins-forge-references-chunk-1.md
    blob: 2afa3865c4fae1349519a6577ac53d714d15c84d
  - path: docs/atlas/modules/plugins-forge-references-chunk-2.md
    blob: 87eae3702c7040ec3badecd02ee25f5419b4c151
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: 03955da6003626919c72277f90450acbaae24630
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 36ee76916bf57fc64cd6b539706411019c234697
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 5f2d470885c2601d0541cd3f4876f4001ca74c0f
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 88befd5bddd2b14fede25eeb5618def6614ec555
  - path: docs/atlas/modules/plugins-issue-misc.md
    blob: 0fb19fdd0aeceb14a4640fcd48e4a3d359971f7d
  - path: docs/atlas/modules/plugins-issue-tests.md
    blob: 8171af4d41d513718f6e85f428c4779823480ff3
  - path: docs/atlas/modules/plugins-rca.md
    blob: f75d2b6c0d838dbf409ec35f93aa0475b1f69993
  - path: docs/atlas/modules/plugins-reconcile-pr.md
    blob: fda736e111b3fc16e29ace755b1194a9ee4fced7
  - path: docs/atlas/modules/plugins-semver-bin-chunk-1.md
    blob: 43db4365d275c874b9f3a8d2a537467ce80d098c
  - path: docs/atlas/modules/plugins-semver-bin-chunk-2.md
    blob: 2f148213e6c84b2227668b2416293e665fb54558
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: fc144ea7b9e4c74850f76cf9b413b8b88ab8b5b1
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: 8a74544406055efe8df5daefa4fbe42c53e6aa89
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: f7fd7ba435d49347ee01f2b65b47d08c34950d08
  - path: docs/atlas/modules/plugins-semver-tests-chunk-1.md
    blob: 17811e6532744904637bf66b701436677ea36cd8
  - path: docs/atlas/modules/plugins-semver-tests-chunk-2.md
    blob: fbfc73348f80cfb23228a74d1153afb07bf50f4e
  - path: docs/atlas/modules/root-misc.md
    blob: 0f8209b072ff49972641be87019ca4de21b4d114
  - path: docs/atlas/modules/tests.md
    blob: 81be3d1395504312e71932a45906f2b64ac382ff
scopes:
  - tree: .claude-plugin
    sha: d4f0e018b15260976f0e6ea67e820e26ccbae92f
  - tree: .semver
    sha: 7bd57a20e51cccf5a5209419e6d8ecfa3e7ca7d6
  - tree: docs
    sha: f85b5bbc53ae787a22371dae0d65f807b9d1eed4
  - tree: plugins
    sha: 6dc9975661f39dcae7599146beb50b679c04015d
  - tree: tests
    sha: 2775cc24b162a93e143a8e74e8dda61e7bff7f19
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Architecture

## System shape

Agentics is a Claude Code plugin marketplace: `.claude-plugin/marketplace.json` registers twelve independently-versioned plugins (agents, atlas, council, deployit, forge, freshen, greenlight, hook-guard, issue, rca, reconcile-pr, semver), each living under `plugins/<name>/` with its own `plugins/<name>/.claude-plugin/plugin.json` manifest. Within every plugin the same layered pattern repeats: a thin-router `SKILL.md` (one `AskUserQuestion` at a time) dispatches to deterministic `bin/` scripts — bash+jq or stdlib-only python3 CLIs emitting one JSON object with an `ok`+`display` contract — for anything computable, and to `references/*.md` protocol docs for detailed procedure, so the skill itself stays a router rather than a procedure. Judgment that can't be computed (module purpose, release notes, triage verdicts) is usually pushed into an optional fourth layer: `agent-overrides/<name>-context.md` files that narrow a generic shared-agent role to the plugin's own state and artifact contract. reconcile-pr is the one plugin that skips this fourth layer entirely: it ships no `agent-overrides/` directory and spawns no shared agent, and its `SKILL.md` instead performs the handful of judgment calls a script can't make — conflict-side labeling, tree verification, summary prose — directly, collapsing the pattern to three layers for that plugin alone.

The one real code-sharing seam is `plugins/agents/agents/`, a library of self-contained agent spawn contracts (YAML frontmatter + role body) that forge, rca, atlas, and council all inline verbatim rather than importing at runtime — a consumer concatenates the shared agent file with its own override doc into one spawn prompt. Beyond that library, plugins are deliberately independent at the runtime-code level: deployit's CLI coordinates with semver only by discovering `semver-cli` as a subprocess (never an import) and is itself the sole writer of a shared git-backed build index, classifying each push failure (ruleset/protected → PR fallback; non-fast-forward → retry from a fresh origin/main; auth → preserve-and-fail without a PR attempt) so concurrent deploys can never corrupt it; atlas, forge, rca, and reconcile-pr each own a fully self-contained deterministic backend with no cross-plugin function calls. Large module-edge counts linking atlas/deployit bin scripts to the semver module are regex-extractor artifacts from common method-name collisions (`get`/`write`/`add`), not real call edges, and should not be read as runtime dependencies.

State is never held in conversation context across a pipeline's steps; each stateful plugin owns a gitignored artifact directory instead (`.forge/`, `.rca/<slug>/`, `.atlas/`, `.semver/`, `.freshen/`), and every resumption decision is derived from which files are present. `plugins-reconcile-pr` varies this pattern rather than breaking it: state is scoped per pull request inside an isolated git worktree at `.claude/worktrees/reconcile-pr/<pr>/` (a `meta.json` plus a `conflicts.log`), and its `start` subcommand refuses to begin if that directory already exists, capping concurrency to one reconcile per PR; `plugins-issue-misc`, by contrast, is fully stateless — each `dispatch` run persists nothing at all. The remaining cross-cutting seams are hook-mediated rather than call-mediated: semver's post-bump hook one-way-stamps `VERSION` into every other plugin's manifest; freshen's Stop/SessionStart hooks are the sole tmux mechanism any plugin uses to `/clear` and re-invoke between steps, driven by a signal file a plugin queues rather than a direct call; hook-guard's shared circuit breaker is sourced by any plugin's Stop hook to halt runaway loops; and greenlight's PreToolUse hook gates every Bash tool call regardless of which plugin is active — including the git/gh commands that both reconcile-pr's rebase machine and the issue plugin's dispatch/complete flows run. This hook layer is where plugins actually touch each other at runtime — everywhere else, a plugin's `bin/` is a closed deterministic world.

## Module relationships

- `plugins-atlas-bin-chunk-1 -> plugins-semver-bin-chunk-1 (calls)`

## Data flow

A forge pipeline step (plugins-forge-skills) is representative of how a stateful action crosses this codebase. The router's SKILL.md calls forge-state.sh (plugins-forge-bin-chunk-3) to derive the current state purely from .forge/ artifact presence plus a storyhook query, then dispatches to the matching step skill. That step spawns a specialist from the shared agent library (plugins-agents-agents-chunk-1/2/3), inlining the matching plugins-forge-agent-overrides context so the generic role knows forge's artifact paths and story state; during execute, every Bash call the spawned agent issues is gated by greenlight's PreToolUse hook (plugins-greenlight). The step writes its .forge/ artifact and exits through the canonical step-exit path (forge-step-exit.sh, plugins-forge-bin-chunk-3): commit, update state.json, and queue a freshen signal file. Freshen's Stop hook (plugins-freshen) tmux-sends /clear plus the next invocation, confirmed by a pane read-back and guarded from runaway repetition by hook-guard's shared circuit breaker (plugins-hook-guard); the next session's SessionStart hook (plugins-forge-hooks) reads state.json and injects a resume summary, closing the loop without any state surviving in conversation context. Triage findings route through plugins-agents-agents-chunk-3's triager into either a FIX re-entry at plan or an ESCALATE pause for the human.

An /atlas update follows the same skeleton with a different payload: plugins-atlas-misc's orchestrator dispatches every CLI call through the single router in plugins-atlas-bin-chunk-2, which forwards to atlas-cli (plugins-atlas-bin-chunk-1) for scan/partition/extract — optionally shelling out to the standalone tree-sitter helper (plugins-atlas-helpers-ts-helper) for resolved call edges instead of regex-ambiguous ones. judge-plan computes exactly the content-addressed judgment keys invalidated by the diff; only those are handed to a cartographer agent (plugins-agents-agents-chunk-1), narrowed by plugins-atlas-agent-overrides' cell contract, which returns judgment cells rather than markdown. judgment ingest merges the cells into the cache, and project deterministically joins the structure index and judgment cache into the committed module docs and INDEX — a no-change rebuild never invokes the model at all.

A /reconcile-pr run traces the codebase's other major flow shape: a deterministic bash script driving explicit state-machine subcommands, with the skill layer supplying only the judgments a script can't make. plugins-reconcile-pr's SKILL.md drives bin/reconcile-pr.sh through preflight → start → resolve/continue → test → push → comment → cleanup; start creates an isolated git worktree under .claude/worktrees/reconcile-pr/<pr>/ and records a meta.json (repo/base/head/remote_oid/base_oid) before any conflict work begins. On each conflict the script hands control back to the skill, which labels the conflicted hunks base_side/pr_side — relabeled from git's rebase-time inversion of ours/theirs — rather than resolving them itself; once the tree is conflict-free the skill verifies the reconciled tree preserves both sides' behavior, then the script runs the test gate and pushes under a force-push safety guard (a destination-ref check plus an explicit-OID --force-with-lease pinned to the remote_oid captured at start, never a bare --force) before the skill writes the summary comment. No shared agent from plugins/agents/agents/ is spawned anywhere in this flow, and every Bash command the skill issues while driving the script is still gated by greenlight's PreToolUse hook, the same as any other plugin.

<!-- atlas:index-facts -->
- Claude Code plugin marketplace; marketplace.json is the sole plugin registry.
- 12 plugins under plugins/<name>/; thin-router skills, deterministic bin/ scripts.
- plugins/agents/agents/ is the shared agent library forge/rca/atlas/council spawn.
- Artifact dirs .forge/ .rca/ .atlas/ .semver/ .freshen/; presence drives resume.
- greenlight is a PreToolUse hook gating Bash: deterministic allow/warn plus AI.
- Atlas v2 separates deterministic extraction/projection from LLM judgment cells.
- reconcile-pr never force-pushes bare; uses explicit-OID --force-with-lease.
- Plugins share no runtime code except agent library, semver stamp, freshen signals.
<!-- /atlas:index-facts -->
