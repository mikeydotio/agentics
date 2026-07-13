---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: 065fe444f9b560ddff3bda26a43905d23dba40fa
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: afaafff3b3c905150e219b0691ca27fb5df3813d
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: 11239fbf8e653ca94a714d791c57c36e908e8a0d
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: c01f936bc20b66925ad2801c4be17e3161d9a289
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: 2fe5178ace4ec68d553819078cd39bf9c081af5c
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: 5896e19763a59e7dd120a1082eb185c6aa98c752
  - path: docs/atlas/modules/plugins-atlas-agent-overrides.md
    blob: 4d1dad48609393ef8311cfcbc65966b1bb38febe
  - path: docs/atlas/modules/plugins-atlas-bin-chunk-1.md
    blob: 0f80eda48c0c6ba31d7a7b527768a7147c26d021
  - path: docs/atlas/modules/plugins-atlas-bin-chunk-2.md
    blob: 6d8aab0ab6b3ac819c4a5205fb9c8ad7f6ce9096
  - path: docs/atlas/modules/plugins-atlas-helpers-ts-helper.md
    blob: 469d365d7180e706259a5a323708beaa21ccc97f
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: 271992bdebcac2217cefafc05f2f70ef509e2169
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: f10896e0aad21c257000ce61bf663b67f5959011
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-1.md
    blob: 451661d1e46536be034e1e7069a9d62104a2b07c
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-2.md
    blob: c85b8df975facbfc03121c0185315ea0eafa7bbb
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-3.md
    blob: bdbebf3c665e85168dcce04beb45ea1488e42e04
  - path: docs/atlas/modules/plugins-council.md
    blob: c0e5770c6aea3bf9f5b5b29f62527ca2189f5220
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: aa6ce2aee689858c7491087d56ccb44c63310dfa
  - path: docs/atlas/modules/plugins-deployit-bin-chunk-1.md
    blob: 6ebfbbb1441be2b9e67cbe1ebd37963cdd5ebdaf
  - path: docs/atlas/modules/plugins-deployit-bin-chunk-2.md
    blob: e4a4c85f1bd7fac93142dd5d1512659ca1bd4c06
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 15c7c58baae4d34cd900ac3618a2d44dfb5681b6
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: ccc52d0b57d350979ca6e0d662476118db0e9b61
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: 85887614887ce17e4167be7951ebd57239721687
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 03a27f5326decdedb5fd20a6bfb6e435cd74067f
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-3.md
    blob: f2b0563f1c44abe44d0221b2886b0d5dc5cc3f14
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
    blob: fdad8172b8e6a37c6cdc4cd4a2707cc2b617bb84
  - path: docs/atlas/modules/plugins-forge-references-chunk-1.md
    blob: 2afa3865c4fae1349519a6577ac53d714d15c84d
  - path: docs/atlas/modules/plugins-forge-references-chunk-2.md
    blob: 87eae3702c7040ec3badecd02ee25f5419b4c151
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: 03955da6003626919c72277f90450acbaae24630
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 569483f68a318090fc3c1705c5bc63ff2f275a5f
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: f218ac72d755ed243e3b630a5f4395baf4e43888
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: de636b264fd17d838f38877ca0cc4fdf0c37921d
  - path: docs/atlas/modules/plugins-issue-misc.md
    blob: 2d7ec4f0cbf45495f97846218c4e67ff512a7e1f
  - path: docs/atlas/modules/plugins-issue-tests-chunk-1.md
    blob: 33e66a7b92998cd1639c1e16e7fba58504a3fdc7
  - path: docs/atlas/modules/plugins-issue-tests-test.md
    blob: 3e0d40982f04b770d8bd96b861c4ccd3de09b2b6
  - path: docs/atlas/modules/plugins-rca-agent-overrides.md
    blob: 0a2a34958f69f549dfaf6fac3154d4c5fd3a46b2
  - path: docs/atlas/modules/plugins-rca-bin.md
    blob: 3cdbf8dd21f5b87074dbfcfc2027a0b75a46909e
  - path: docs/atlas/modules/plugins-rca-misc.md
    blob: c69686be31b4502579428e825d5d41bca2028e08
  - path: docs/atlas/modules/plugins-rca-references.md
    blob: 38f53622b9d2a1fd9ff345f478358aad3a56de85
  - path: docs/atlas/modules/plugins-rca-skills.md
    blob: ac91f58984bdcd034a6be18263543efa0e2724af
  - path: docs/atlas/modules/plugins-rca-tests.md
    blob: 8d3d85eb4595c606a7361ed7d7a79174f7619447
  - path: docs/atlas/modules/plugins-reconcile-pr.md
    blob: 732c66273291a6ea1974c60b3f24b1a97102dfe2
  - path: docs/atlas/modules/plugins-semver-bin-chunk-1.md
    blob: 4f9432a741940ecc15f357b10e4bf232259ae92f
  - path: docs/atlas/modules/plugins-semver-bin-chunk-2.md
    blob: 2f148213e6c84b2227668b2416293e665fb54558
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: fc144ea7b9e4c74850f76cf9b413b8b88ab8b5b1
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: 4c8ea6c8b6fbc927d6ec04755da4e44dcfce9e26
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: f7fd7ba435d49347ee01f2b65b47d08c34950d08
  - path: docs/atlas/modules/plugins-semver-tests-chunk-1.md
    blob: 17811e6532744904637bf66b701436677ea36cd8
  - path: docs/atlas/modules/plugins-semver-tests-chunk-2.md
    blob: 3f2b8472a7f41c205cf477363300f0bc94f15f52
  - path: docs/atlas/modules/root-misc.md
    blob: 00d2b60a9ffe754d193c5ebc128a8e33249016d5
  - path: docs/atlas/modules/tests.md
    blob: 81be3d1395504312e71932a45906f2b64ac382ff
scopes:
  - tree: .claude-plugin
    sha: 5beb3e27bc66b60f4f7e4a06e5fd97d9f699efef
  - tree: .semver
    sha: 7bd57a20e51cccf5a5209419e6d8ecfa3e7ca7d6
  - tree: docs
    sha: 13729557921abbcad72d90c1dbcf94ebc11f41b1
  - tree: plugins
    sha: b020dd3e363225f98d27695046a6bdf354966db5
  - tree: tests
    sha: 2775cc24b162a93e143a8e74e8dda61e7bff7f19
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Architecture

## System shape

Agentics is a Claude Code plugin marketplace: `.claude-plugin/marketplace.json` registers twelve independently-versioned plugins (agents, atlas, council, deployit, forge, freshen, greenlight, hook-guard, issue, rca, reconcile-pr, semver), each living under `plugins/<name>/` with its own `plugins/<name>/.claude-plugin/plugin.json` manifest. Within every plugin the same layered pattern repeats: a thin-router `SKILL.md` (one `AskUserQuestion` at a time) dispatches to deterministic `bin/` scripts — bash+jq or stdlib-only python3 CLIs emitting one JSON object with an `ok`+`display` contract — for anything computable, and to `references/*.md` protocol docs for detailed procedure, so the skill itself stays a router rather than a procedure. Judgment that can't be computed (module purpose, release notes, triage verdicts, root-cause verdicts) is pushed into an optional fourth layer: `agent-overrides/<name>-context.md` files that narrow a generic shared-agent role to the plugin's own state and artifact contract. forge and rca are now the two plugins that fully exhibit this four-layer fractal — rca's earlier five-phase single-skill design was rebuilt into seven per-step skills (plugins-rca-skills), each paired to its own deterministic bin/ CLI (plugins-rca-bin) and per-step agent-overrides context (plugins-rca-agent-overrides), mirroring forge's skills/bin/agent-overrides split rather than being a one-off shape. reconcile-pr is the one plugin that skips the fourth layer entirely: it ships no `agent-overrides/` directory and spawns no shared agent, and its `SKILL.md` instead performs the handful of judgment calls a script can't make — conflict-side labeling, tree verification, summary prose — directly, collapsing the pattern to three layers for that plugin alone.

The one real code-sharing seam is `plugins/agents/agents/`, a library of self-contained agent spawn contracts (YAML frontmatter + role body) that forge, rca, atlas, and council all inline verbatim rather than importing at runtime — a consumer concatenates the shared agent file with its own override doc into one spawn prompt. Beyond that library, plugins are deliberately independent at the runtime-code level: deployit's CLI coordinates with semver only by discovering `semver-cli` as a subprocess (never an import) and is itself the sole writer of a shared git-backed build index; atlas, forge, rca, and reconcile-pr each own a fully self-contained deterministic backend with no cross-plugin function calls. Large module-edge counts linking atlas/deployit bin scripts to the semver module are regex-extractor artifacts from common method-name collisions (`get`/`write`/`add`), not real call edges, and should not be read as runtime dependencies.

State is never held in conversation context across a pipeline's steps; each stateful plugin owns a gitignored artifact directory instead (`.forge/`, `.rca/<slug>/`, `.atlas/`, `.semver/`, `.freshen/`), and every resumption decision is derived from which files are present. `plugins-reconcile-pr` varies this pattern rather than breaking it: state is scoped per pull request inside an isolated git worktree at `.claude/worktrees/reconcile-pr/<pr>/`, and its `start` subcommand refuses to begin if that directory already exists, capping concurrency to one reconcile per PR; `plugins-issue-misc`, by contrast, is fully stateless — each `dispatch` run persists nothing at all. Atlas's own backend is the sharpest layer boundary in the repo: `plugins-atlas-bin-chunk-1`'s deterministic extractor produces a structure index (symbols, signatures, resolved/ambiguous call edges) entirely separately from the LLM-authored judgment cache it merges in — a cartographer agent only ever returns content-addressed judgment cells for the keys `judge-plan` says are invalidated by a diff, never markdown — and `project` deterministically joins structure + judgment into the committed docs, so a no-change rebuild never invokes a model at all. The remaining cross-cutting seams are hook-mediated rather than call-mediated: semver's post-bump hook one-way-stamps `VERSION` into every other plugin's manifest; freshen's Stop/SessionStart hooks are the sole tmux mechanism any plugin uses to `/clear` and re-invoke between steps; hook-guard's shared circuit breaker is sourced by any plugin's Stop hook to halt runaway loops; and greenlight's PreToolUse hook gates every Bash tool call regardless of which plugin is active. This hook layer is where plugins actually touch each other at runtime — everywhere else, a plugin's `bin/` is a closed deterministic world.

## Module relationships

- `plugins-atlas-bin-chunk-1 -> plugins-semver-bin-chunk-1 (calls)`

## Data flow

A forge pipeline step (plugins-forge-skills) is representative of how a stateful action crosses this codebase. The router's SKILL.md calls forge-state.sh (plugins-forge-bin-chunk-3) to derive the current state purely from .forge/ artifact presence plus a storyhook query, then dispatches to the matching step skill. That step spawns a specialist from the shared agent library (plugins-agents-agents-chunk-1/2/3), inlining the matching plugins-forge-agent-overrides context so the generic role knows forge's artifact paths and story state; during execute, every Bash call the spawned agent issues is gated by greenlight's PreToolUse hook (plugins-greenlight). The step writes its .forge/ artifact and exits through the canonical step-exit path (forge-step-exit.sh, plugins-forge-bin-chunk-3): commit, update state.json, and queue a freshen signal file. Freshen's Stop hook (plugins-freshen) tmux-sends /clear plus the next invocation, confirmed by a pane read-back and guarded from runaway repetition by hook-guard's shared circuit breaker (plugins-hook-guard); the next session's SessionStart hook (plugins-forge-hooks) reads state.json and injects a resume summary, closing the loop without any state surviving in conversation context. Triage findings route through plugins-agents-agents-chunk-3's triager into either a FIX re-entry at plan or an ESCALATE pause for the human.

A /rca investigation now follows the same layered shape as forge, not the plugin's earlier five-phase single-skill design: rca's orchestrator (plugins-rca-skills) walks seven step skills — intake, reproduce, locate, diagnose, report, fix, postmortem — each invoking deterministic CLIs (plugins-rca-bin: forensics, bisect, repro, hotspots, stack, scaffold, status, worktree) for git archaeology and disposable-worktree hypothesis falsification, and spawning shared agents narrowed by per-step context in plugins-rca-agent-overrides (evidence, experiment, fix, report, postmortem). The pipeline is reproduction-gated — a defect must be confirmed to reproduce before fix work proceeds — and closes with an ODC-classified, committed blameless postmortem, per plugins-rca-references and plugins-rca-misc. State persists to .rca/<slug>/ artifacts exactly like forge's .forge/, confirming the skills/bin/agent-overrides fractal as the repo's default shape for multi-step pipeline plugins rather than a forge-only pattern.

An /atlas update follows the same skeleton with a different payload: plugins-atlas-misc's orchestrator dispatches every CLI call through the single router in plugins-atlas-bin-chunk-2, which forwards to atlas-cli (plugins-atlas-bin-chunk-1) for scan/partition/extract — optionally shelling out to the standalone tree-sitter helper (plugins-atlas-helpers-ts-helper) for resolved call edges instead of regex-ambiguous ones. judge-plan computes exactly the content-addressed judgment keys invalidated by the diff; only those are handed to a cartographer agent (plugins-agents-agents-chunk-1), narrowed by plugins-atlas-agent-overrides' cell contract, which returns judgment cells rather than markdown. judgment ingest merges the cells into the cache, and project deterministically joins the structure index and judgment cache into the committed module docs and INDEX — a no-change rebuild never invokes the model at all.

A /reconcile-pr run traces the codebase's other major flow shape: a deterministic bash script driving explicit state-machine subcommands, with the skill layer supplying only the judgments a script can't make. plugins-reconcile-pr's SKILL.md drives bin/reconcile-pr.sh through preflight → start → resolve/continue → test → push → comment → cleanup; start creates an isolated git worktree under .claude/worktrees/reconcile-pr/<pr>/ and records a meta.json (repo/base/head/remote_oid/base_oid) before any conflict work begins. On each conflict the script hands control back to the skill, which labels the conflicted hunks base_side/pr_side — relabeled from git's rebase-time inversion of ours/theirs — rather than resolving them itself; once the tree is conflict-free the skill verifies the reconciled tree preserves both sides' behavior, then the script runs the test gate and pushes under a force-push safety guard (a destination-ref check plus an explicit-OID --force-with-lease pinned to the remote_oid captured at start, never a bare --force) before the skill writes the summary comment. No shared agent from plugins/agents/agents/ is spawned anywhere in this flow, and every Bash command the skill issues while driving the script is still gated by greenlight's PreToolUse hook, the same as any other plugin.

<!-- atlas:index-facts -->
- Claude Code plugin marketplace; marketplace.json is the registry.
- 12 plugins; thin-router skills over deterministic bin/ CLIs.
- plugins/agents/agents/ is the shared agent library.
- Artifact dirs .forge/.rca/.atlas/.semver/.freshen/ drive resume.
- rca: 7-step reproduction-gated root-cause pipeline.
- greenlight: PreToolUse Bash gate (deterministic + AI).
- Atlas v2 splits extraction/projection from LLM judgment.
- reconcile-pr uses --force-with-lease, never bare force.
<!-- /atlas:index-facts -->
