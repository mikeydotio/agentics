---
module: overview/ARCHITECTURE
summary: "System shape, module relationships, and cross-plugin invariants of the agentics marketplace"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: 088cf433c74004bea0260499a1ce974e88d18c53
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: 3b82860a4e840245fa1449d96c384a9c2c8e50eb
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: ad506c787b7ef73863647bfbd6cb26101ea6f8ed
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: 600c20486c317a4db6fc6970135358248a8bbccc
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: 721b49a9fc222d41dae57e284c42a17dcbd09ac4
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: aa6212dd7650ad146440ed6f683df8c79e5d6394
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: de373849ff4f4de4bbb2c238d271bf9991ad1ef9
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 462ae66f83abcf85bdb5da96a41d3894ab720307
  - path: docs/atlas/modules/plugins-atlas-tests.md
    blob: 4d1d998a47c7939a737b644a6dfdd4ce95a37be4
  - path: docs/atlas/modules/plugins-council.md
    blob: 7ee137f5295b0474bdd206931472fba43b49dd96
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: 47e6424c7ccb7ffb494ee7942273e43327a9d8d1
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: 5e6ef0c6d6eed29d92b3287e5c559ee2fd228809
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 30b3427b30351ff10a785e6541678e58c4e37de6
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: d1a0facfab693ea70103d2bd6fcbd3e785cc638a
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: 3c0c7079c2a2f0df056338df7e790f254effb8f5
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 278a042c295064ca06a90dc5934e9c9862669277
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: 9de076edef8762e399fa6a73c351cddead63a288
  - path: docs/atlas/modules/plugins-forge-bin.md
    blob: cb3b89d6e7be89d90b7d165b64bdb2c1274fea44
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: b5f873c89149522119e436611c38d853209b5ade
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: 3c43247f526cbac11d1a1393c2e9363243fcdd7b
  - path: docs/atlas/modules/plugins-forge-references.md
    blob: 1bfd018b6e13c470e09182c68128989a7296e792
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: c3021afbac4423d524e47e7036798cd509f5b5c4
  - path: docs/atlas/modules/plugins-freshen.md
    blob: d32244604362e25737d79a921cbee5ac18ebc19b
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 6240c82c2192940de89b02721f3d725fc3b738f5
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 06676c68b40d47146d0c0401ed1664569d63f549
  - path: docs/atlas/modules/plugins-rca.md
    blob: f2021f279bbafbf3757d52786b1bcf4acd510984
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: 532f3d5e96ab9b8fb8a47fdca660d8d9c9196804
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: 2d0165c3183fc3a3ee61b0ec1a94c9185519c374
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: 2b2dd5420fc63bb88968b99f1a6004d384c18adc
  - path: docs/atlas/modules/plugins-semver-tests.md
    blob: eadf06f2ff905fb879d52ccef8b68ae6e2b32102
  - path: docs/atlas/modules/root-misc.md
    blob: d87850042ca13cbda5dbf5db36b7c90a3bd3e51e
  - path: docs/atlas/modules/tests.md
    blob: 4c69deac8c9f836000b9258905f8a99c58159bb6
scopes:
  - tree: plugins
    sha: 1aeb8d775b58d2b80eccbceda1dd0d01c4bdebda
  - tree: tests
    sha: f726161a1df6bcd639771ffdde7d527eaba66cdf
  - tree: docs
    sha: c69259ae6f048bf17be1358d5191830599def1b1
generator: cartographer/1
baseline: b1e1f9d1dbced518c625c38bb87814de5af1a1b7
---

# Architecture

## System shape

Agentics is a Claude Code plugin marketplace: the root manifest binds independently developed
plugins under `plugins/` into one installable catalog, and two test layers — per-plugin bash
suites plus a root bats suite — gate every push through `make test`. Plugins share no runtime;
they compose through files on disk, hook events, and subagent spawning.

Inside a plugin one layer cake repeats: a thin SKILL.md router owns protocol only; a
deterministic bin/ layer (bash + jq routers, stdlib-only python3 CLIs) owns everything
checkable and answers with a single JSON object per run; references/ docs carry normative
contracts that agents load at spawn time; hooks stay inert unless the plugin's gate artifact
exists. The agents plugin is the horizontal seam — a shared library of agent prompt contracts
that forge, rca, atlas, and council spawn by inlining a definition plus a pipeline override.

Two micro-plugins serve the rest at runtime: freshen relays `/clear` + re-invocation through
tmux send-keys, and hook-guard is the circuit breaker Stop hooks source first. greenlight
(PreToolUse Bash triage) is fully self-contained. Cross-session state always lives in
namespaced artifact directories, never in conversation.

## Module relationships

- `plugins-forge-skills -> plugins-agents-agents-chunk-1 (calls)`
- `plugins-forge-skills -> plugins-agents-agents-chunk-2 (calls)`
- `plugins-forge-skills -> plugins-agents-agents-chunk-3 (calls)`
- `plugins-forge-agent-overrides -> plugins-agents-agents-chunk-1 (extends)`
- `plugins-forge-agent-overrides -> plugins-agents-agents-chunk-3 (extends)`
- `plugins-rca -> plugins-agents-agents-chunk-1 (calls)`
- `plugins-rca -> plugins-agents-agents-chunk-2 (calls)`
- `plugins-atlas-misc -> plugins-agents-agents-chunk-1 (calls)`
- `plugins-atlas-misc -> plugins-agents-agents-chunk-2 (extends)`
- `plugins-council -> plugins-agents-agents-chunk-2 (calls)`
- `plugins-council -> plugins-agents-agents-ux (calls)`
- `plugins-agents-misc -> plugins-agents-agents-chunk-1 (reads)`
- `plugins-agents-agents-chunk-1 -> plugins-atlas-references (reads)`
- `plugins-forge-skills -> plugins-forge-bin (calls)`
- `plugins-forge-skills -> plugins-forge-references (reads)`
- `plugins-forge-skills -> plugins-freshen (calls)`
- `plugins-forge-bin -> plugins-freshen (calls)`
- `plugins-forge-hooks -> plugins-freshen (emits)`
- `plugins-forge-hooks -> plugins-forge-skills (reads)`
- `plugins-forge-hooks -> plugins-hook-guard (calls)`
- `plugins-freshen -> plugins-hook-guard (calls)`
- `plugins-semver-misc -> plugins-semver-hooks (calls)`
- `plugins-semver-hooks -> plugins-semver-misc (calls)`
- `plugins-semver-misc -> plugins-semver-references (implements)`
- `plugins-semver-hooks -> plugins-forge-skills (reads)`
- `plugins-deployit-misc -> plugins-deployit-bin (calls)`
- `plugins-deployit-bin -> plugins-deployit-assets (reads)`
- `plugins-deployit-bin -> plugins-semver-misc (calls)`
- `plugins-deployit-bin -> plugins-deployit-tests-chunk-2 (calls)`
- `plugins-atlas-misc -> plugins-atlas-references (reads)`
- `plugins-atlas-tests -> plugins-atlas-misc (calls)`
- `plugins-semver-tests -> plugins-semver-misc (calls)`
- `plugins-deployit-tests-chunk-1 -> plugins-deployit-bin (calls)`
- `root-misc -> tests (calls)`

## Data flow

A forge run is the representative pipeline; each hop below crosses a module boundary.

- `/forge` runs plugins-forge-bin's forge-state.sh; `.forge/` artifact presence selects the step
- The dispatched step skill spawns shared agents with forge override blocks concatenated on
- Each step writes one artifact plus a handoff; forge-step-exit.sh commits and queues freshen
- freshen's Stop hook tmux-sends `/clear`; its SessionStart hook re-invokes `/forge` clean
- The fresh session re-derives state and dispatches the next step; context never accumulates
- After execute, review and validate run in parallel; triage labels each finding FIX or ESCALATE
- FIX re-enters at plan; deploy stays gated on `.forge/DEPLOY-APPROVAL.md` and explicit approval
- An abrupt Stop checkpoints via plugins-forge-hooks; SessionStart injects resume context

## Key invariants

- Every plugin manifest is registered in the root registry — `.claude-plugin/marketplace.json:8`
- Pipeline state derives from on-disk artifacts, never conversation — `plugins/forge/README.md:56`
- Deterministic CLIs print one JSON object per run — `plugins/semver/bin/semver-cli:82`
- Hooks are inert without their activation gate — `plugins/forge/hooks/session-start.sh:26`
- Stop hooks run stop_guard_check before any work — `plugins/hook-guard/lib/stop-guard.sh:25`
- tmux send-keys is the only context-clear channel — `plugins/freshen/bin/freshen.sh:21`
- Python tooling is stdlib-only, no third-party imports — `plugins/semver/bin/semver-cli:8`
- Overrides add, never replace — `plugins/agents/references/cross-plugin-usage.md:66`
- Generator never commits; evaluator never edits — `plugins/forge/skills/execute/SKILL.md:31-32`
- Never trigger `/semver bump` from a hook — `plugins/semver/hooks/run-user-hooks.sh:41`
- `make test` is the aggregate pre-push gate — `Makefile:7`

<!-- atlas:index-facts -->
- .claude-plugin/marketplace.json is the sole plugin registry; plugins live under plugins/<name>/
- Plugins: agents, atlas, council, deployit, forge, freshen, greenlight, hook-guard, rca, semver
- plugins/agents/agents/ is the shared agent library; forge, rca, atlas, and council spawn from it
- Spawning inlines the shared agent definition plus the plugin's agent-overrides/<x>-context.md
- State = artifact dirs: .forge/ .rca/<slug>/ .semver/ .atlas/ .freshen/; resume derives from files
- Skills are thin routers; bin/ scripts (bash+jq or stdlib-only python3) own deterministic work
- CLIs emit one JSON object with ok + display per run; skills halt and show display on ok:false
- Hooks stay silent when their plugin is inactive and build all JSON with jq, never printf
- Stop hooks source hook-guard's stop_guard_check; a SessionStart reset re-arms the breaker
- freshen delivers /clear + re-invocation only via tmux send-keys; outside tmux it no-ops
- Forge steps exit uniformly: write artifact + handoff, commit, queue freshen, STOP
- Forge triage: FIX re-enters at plan (max 3 cycles, 10 yolo); ESCALATE pauses for the user
- Tests are mock-free bash harnesses driving real CLIs in throwaway /tmp git repos
- make test aggregates the semver, deployit, atlas, and root bats suites; pre-push runs it
<!-- /atlas:index-facts -->
