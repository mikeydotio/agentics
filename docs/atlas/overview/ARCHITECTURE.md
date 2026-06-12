---
module: overview/ARCHITECTURE
summary: "System shape, module relationships, and cross-plugin invariants of the agentics marketplace"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: 83f97b238db9d35cb8dc26fa9e9eca3aa86c07ff
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: 9f93adcafa6255045a843dd2c1274d235b97ac97
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: ef3742fcb7d78418c4f9cb60c3b8b24f2a0d5e74
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: 75996ab298a96cb7a7e3e4faf8db2892caa5c44f
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: 93e546126e74b366acd2e58c900bd07e2a6d4766
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: 1b7e2f101fe5a67313d58196adb202cfae5dd82c
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: 417a8429598db1d7587c9df980e6a89067d7a8b0
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 9bcf60683ca69585b6277603f68bb82c4cdf13f1
  - path: docs/atlas/modules/plugins-atlas-tests.md
    blob: 0e0bc56b3eb6492412b8c162495b9274896f0622
  - path: docs/atlas/modules/plugins-council.md
    blob: 3f13dbba9eab880139632767c967a135d1f35fbd
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: b9542c222709d51d45b5c10eb2ef0e9a308b71e3
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: bfbf4bda712d68baa19c3fbf77aeffebd7de0d0a
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 171c93fa1547f7df5b2d80dccc48992bca180fbc
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: 6715a61600d5c7174a5b3a6e3f84ca98b5111f36
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: f042ec81a2655c1f52d6bd0bb75a62e9b891b784
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 84d8e00fc6229b1ff5aa841cc5fef722389d3508
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: fdf0e8e6761b017fda7d899e51fb1fd50d9ef154
  - path: docs/atlas/modules/plugins-forge-bin.md
    blob: 00a8ff52bbef2942767e4a7d7c0f0f4de82951d3
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: 8a1ae344cb407ced61494f9cb24bdee8c9414e22
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: 46bd67479a04a2237321068d2126a82ce0a1782f
  - path: docs/atlas/modules/plugins-forge-references.md
    blob: e80666efd0846f232ada151d949c478dcc34e43e
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: b7c19956fda9d0c509cadcfa51b9825b2921e62f
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 6e095f4f3c63c14d97eaab2f8ed5e44d7d041923
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 816272cb74ca60909160d3b0c1b4494672637e8b
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 5704253d35f7d407530fd8ba79a341763dbf195f
  - path: docs/atlas/modules/plugins-rca.md
    blob: 7d05b3bc42e78748adbe8af0095ab699c292968c
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: b18a49019caa60fc6c0a57fb8311cf4efde4bba1
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: 874e33238961a11dc026092fc94aa22d91c2a2ba
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: c9e5d73a6e8e489f559fb77f1899c54360809681
  - path: docs/atlas/modules/plugins-semver-tests.md
    blob: 1e5da4704bb1b156495e771d35234862141adf0e
  - path: docs/atlas/modules/root-misc.md
    blob: 7a46591e6608b5a1508d4929c22a61c34cc8ee93
  - path: docs/atlas/modules/tests.md
    blob: 9d72ed08c7b45fd7fc6c474366e62d2dfee2292a
scopes:
  - tree: plugins
    sha: 224db90f5191521372b88f72de14a57d7f6e5552
  - tree: tests
    sha: f726161a1df6bcd639771ffdde7d527eaba66cdf
generator: cartographer/1
baseline: 6c8b6fd6abf561a6044b7fd6b40950bffb56c8f2
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
- Atlas maps update incrementally via the blob-SHA ledger; unchanged docs never reach an LLM
- Tests are mock-free bash harnesses driving real CLIs in throwaway /tmp git repos
- make test aggregates the semver, deployit, atlas, and root bats suites; pre-push runs it
<!-- /atlas:index-facts -->
