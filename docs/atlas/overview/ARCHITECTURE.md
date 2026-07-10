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
    blob: 1914aaa3678fc5ab17443b3a9c9d1c84a93579b4
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
    blob: 5f8d23fff5c7682e20d4b4143679f28b945cef2b
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 3ee390a3ede83da8fce921a6529154456831a447
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-1.md
    blob: 1d4798201c1ad94362c47a560dc5ded9a0081917
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-2.md
    blob: 8a7cf46ec3fc63ccb251851ada2432638341b79a
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-3.md
    blob: bdbebf3c665e85168dcce04beb45ea1488e42e04
  - path: docs/atlas/modules/plugins-council.md
    blob: f2bac52bfbf1a0cf6dca0f3a5dbaac0c57bb36b2
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: bdae424dba7a580acd58eeb04a62bb410651a0fd
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: c99c106e416f55363387c0afcf2c61d75fa1381d
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 6954089d12f75324623ac3f1efdc20dd2fea7b5f
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: fd6d5b05370f301b92148de977392593722547d3
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: f174c69e4fa40880f993b798c0f985efeabd6eef
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 482c907017c3084752d4b184cbf7707b85a9c417
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-3.md
    blob: 95d7a472bd68c7da45dc99fd78be46949fa02f0a
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
    blob: e1071d77b40e41a83dcccb49f87c2feee43a6ea5
  - path: docs/atlas/modules/plugins-forge-references-chunk-1.md
    blob: 2afa3865c4fae1349519a6577ac53d714d15c84d
  - path: docs/atlas/modules/plugins-forge-references-chunk-2.md
    blob: 87eae3702c7040ec3badecd02ee25f5419b4c151
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: 03955da6003626919c72277f90450acbaae24630
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 04362241a3691fdcd149ed29410dc385900cbe87
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 234b1c288231f7df9f9374b888ec2bf91c8626d2
  - path: docs/atlas/modules/plugins-handle-issue.md
    blob: 9237cac4374e0966be86fb35ed1ef87a41e6bd9c
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 6d512477ba6a8331a0618231495400bc42a3298c
  - path: docs/atlas/modules/plugins-rca.md
    blob: 2059f6cbd5db90a04b7e34cb7ad09a6c5ba22b2f
  - path: docs/atlas/modules/plugins-reconcile-pr.md
    blob: 631faf429b255a4c3e4a9b8d788d33dbbff8d26c
  - path: docs/atlas/modules/plugins-semver-bin-chunk-1.md
    blob: 43db4365d275c874b9f3a8d2a537467ce80d098c
  - path: docs/atlas/modules/plugins-semver-bin-chunk-2.md
    blob: 2f148213e6c84b2227668b2416293e665fb54558
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: fc144ea7b9e4c74850f76cf9b413b8b88ab8b5b1
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: 1ccc8540a4605edff2b858acb75367e36416f7aa
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: f7fd7ba435d49347ee01f2b65b47d08c34950d08
  - path: docs/atlas/modules/plugins-semver-tests-chunk-1.md
    blob: 17811e6532744904637bf66b701436677ea36cd8
  - path: docs/atlas/modules/plugins-semver-tests-chunk-2.md
    blob: fbfc73348f80cfb23228a74d1153afb07bf50f4e
  - path: docs/atlas/modules/root-misc.md
    blob: d67afab0f151d2bb7e36fc12a2d4c0ac68f976c3
  - path: docs/atlas/modules/tests.md
    blob: a38143ec06d116e409beaeca5821572afa5a34a1
scopes:
  - tree: .claude-plugin
    sha: f6e7348a80bba985f26726fff6d5115e2be8efa6
  - tree: .semver
    sha: 7bd57a20e51cccf5a5209419e6d8ecfa3e7ca7d6
  - tree: docs
    sha: 0da0f8b1f8e8a53367fac861c3fa0e7387da537e
  - tree: plugins
    sha: 6eafa35ae9169c1b04889c185e5b0f2d6a2b7fb3
  - tree: tests
    sha: a8d69b27c9cffe295e1efaa3ed7186d4fb6a5260
generator: cartographer/4
baseline: 134d628a77fb9540e6c1f561e02d9a1e192e6552
---

# Architecture

## System shape

Agentics is a Claude Code plugin marketplace: `.claude-plugin/marketplace.json` registers twelve independently-versioned plugins (agents, atlas, council, deployit, forge, freshen, greenlight, handle-issue, hook-guard, rca, reconcile-pr, semver), each living under `plugins/<name>/` with its own `plugins/<name>/.claude-plugin/plugin.json` manifest. Within every plugin the same layered pattern repeats: a thin-router `SKILL.md` (one `AskUserQuestion` at a time) dispatches to deterministic `bin/` scripts — bash+jq or stdlib-only python3 CLIs emitting one JSON object with an `ok`+`display` contract — for anything computable, and to `references/*.md` protocol docs for detailed procedure, so the skill itself stays a router rather than a procedure. Judgment that can't be computed (module purpose, release notes, triage verdicts) is usually pushed into an optional fourth layer: `agent-overrides/<name>-context.md` files that narrow a generic shared-agent role to the plugin's own state and artifact contract. reconcile-pr is the one plugin that skips this fourth layer entirely: it ships no `agent-overrides/` directory and spawns no shared agent, and its `SKILL.md` instead performs the handful of judgment calls a script can't make — conflict-side labeling, tree verification, summary prose — directly, collapsing the pattern to three layers for that plugin alone.

The one real code-sharing seam is `plugins/agents/agents/`, a library of self-contained agent spawn contracts (YAML frontmatter + role body) that forge, rca, atlas, and council all inline verbatim rather than importing at runtime — a consumer concatenates the shared agent file with its own override doc into one spawn prompt. Beyond that library, plugins are deliberately independent at the runtime-code level: deployit's CLI coordinates with semver only by discovering `semver-cli` as a subprocess (never an import), and atlas, forge, rca, and reconcile-pr each own a fully self-contained deterministic backend with no cross-plugin function calls. Large module-edge counts linking atlas/deployit bin scripts to the semver module are regex-extractor artifacts from common method-name collisions (`get`/`write`/`add`), not real call edges, and should not be read as runtime dependencies.

State is never held in conversation context across a pipeline's steps; each stateful plugin owns a gitignored artifact directory instead (`.forge/`, `.rca/<slug>/`, `.atlas/`, `.semver/`, `.freshen/`), and every resumption decision is derived from which files are present. `plugins-reconcile-pr` varies this pattern rather than breaking it: state is scoped per pull request inside an isolated git worktree at `.claude/worktrees/reconcile-pr/<pr>/` (a `meta.json` plus a `conflicts.log`), and its `start` subcommand refuses to begin if that directory already exists, capping concurrency to one reconcile per PR; `plugins-handle-issue`, by contrast, is fully stateless — each `dispatch` run persists nothing at all. The remaining cross-cutting seams are hook-mediated rather than call-mediated: semver's post-bump hook one-way-stamps `VERSION` into every other plugin's manifest; freshen's Stop/SessionStart hooks are the sole tmux mechanism any plugin uses to `/clear` and re-invoke between steps, driven by a signal file a plugin queues rather than a direct call; hook-guard's shared circuit breaker is sourced by any plugin's Stop hook to halt runaway loops; and greenlight's PreToolUse hook gates every Bash tool call regardless of which plugin is active — including the git/gh commands reconcile-pr and handle-issue issue. This hook layer is where plugins actually touch each other at runtime — everywhere else, a plugin's `bin/` is a closed deterministic world.

## Module relationships

- `plugins-atlas-bin-chunk-1 -> plugins-semver-bin-chunk-1 (calls)`

## Data flow

A forge pipeline step (plugins-forge-skills) is representative of how a stateful action crosses this codebase. The router's SKILL.md calls forge-state.sh (plugins-forge-bin-chunk-3) to derive the current state purely from .forge/ artifact presence plus a storyhook query, then dispatches to the matching step skill. That step spawns a specialist from the shared agent library (plugins-agents-agents-chunk-1/2/3), inlining the matching plugins-forge-agent-overrides context so the generic role knows forge's artifact paths and story state; during execute, every Bash call the spawned agent issues is gated by greenlight's PreToolUse hook (plugins-greenlight). The step writes its .forge/ artifact and exits through the canonical step-exit path (forge-step-exit.sh, plugins-forge-bin-chunk-3): commit, update state.json, and queue a freshen signal file. Freshen's Stop hook (plugins-freshen) tmux-sends /clear plus the next invocation, confirmed by a pane read-back and guarded from runaway repetition by hook-guard's shared circuit breaker (plugins-hook-guard); the next session's SessionStart hook (plugins-forge-hooks) reads state.json and injects a resume summary, closing the loop without any state surviving in conversation context. Triage findings route through plugins-agents-agents-chunk-3's triager into either a FIX re-entry at plan or an ESCALATE pause for the human.

An /atlas update follows the same skeleton with a different payload: plugins-atlas-misc's orchestrator dispatches every CLI call through the single router in plugins-atlas-bin-chunk-2, which forwards to atlas-cli (plugins-atlas-bin-chunk-1) for scan/partition/extract — optionally shelling out to the standalone tree-sitter helper (plugins-atlas-helpers-ts-helper) for resolved call edges instead of regex-ambiguous ones. judge-plan computes exactly the content-addressed judgment keys invalidated by the diff; only those are handed to a cartographer agent (plugins-agents-agents-chunk-1), narrowed by plugins-atlas-agent-overrides' cell contract, which returns judgment cells rather than markdown. judgment ingest merges the cells into the cache, and project deterministically joins the structure index and judgment cache into the committed module docs and INDEX — a no-change rebuild never invokes the model at all.

A /reconcile-pr run traces the codebase's other major flow shape: a deterministic bash script driving explicit state-machine subcommands, with the skill layer supplying only the judgments a script can't make. plugins-reconcile-pr's SKILL.md drives bin/reconcile-pr.sh through preflight → start → resolve/continue → test → push → comment → cleanup; start creates an isolated git worktree under .claude/worktrees/reconcile-pr/<pr>/ and records a meta.json (repo/base/head/remote_oid/base_oid) before any conflict work begins. On each conflict the script hands control back to the skill, which labels the conflicted hunks base_side/pr_side — relabeled from git's rebase-time inversion of ours/theirs — rather than resolving them itself; once the tree is conflict-free the skill verifies the reconciled tree preserves both sides' behavior, then the script runs the test gate and pushes under a force-push safety guard (a destination-ref check plus an explicit-OID --force-with-lease pinned to the remote_oid captured at start, never a bare --force) before the skill writes the summary comment. No shared agent from plugins/agents/agents/ is spawned anywhere in this flow, and every Bash command the skill issues while driving the script is still gated by greenlight's PreToolUse hook, the same as any other plugin.

<!-- atlas:index-facts -->
- Claude Code plugin marketplace; marketplace.json is the sole plugin registry.
- 12 plugins live under plugins/<name>/, each with its own bin/, skills/, references/.
- Skills are thin routers; bin/ scripts (bash+jq or python3) do deterministic work.
- plugins/agents/agents/ is the shared agent library forge/rca/atlas/council spawn from.
- Artifact dirs: .forge/ .rca/<slug>/ .atlas/ .semver/ .freshen/; presence drives resume.
- hook-guard is a shared circuit breaker any Stop hook sources to halt runaway loops.
- greenlight is a PreToolUse hook gating Bash: deterministic allow/warn plus AI fallback.
- Atlas v2 separates deterministic extraction/projection from LLM judgment cells.
- Plugins share no runtime code except the agent library, semver stamp, freshen signals.
- reconcile-pr never force-pushes bare; uses explicit-OID --force-with-lease.
<!-- /atlas:index-facts -->
