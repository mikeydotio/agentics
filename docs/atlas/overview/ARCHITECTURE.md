---
module: overview/ARCHITECTURE
summary: "System shape, module relationships, and cross-plugin invariants of the agentics marketplace"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: 16d26af7b173860f1176b5f18741ce99502f4e56
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: e3bb6f399defe7e48fc18eb4260f163d2c91d6dd
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: 29594d9fcd8c96256e4bb73679b1643d466b716c
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: 2f51efc14bb8f7953aee8ce1ce4d65c950ae669e
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: f92d2dda653d0075814cd3947915655a30e5b82b
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: 075228f0c0aa9a6c2889a38ea5af7a5e623eb57e
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: 3c8134fdd0aa2861bcb3eb49d1ced77b16c376c7
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 6eae408b4b2db5491400ff2716e683da986ffff7
  - path: docs/atlas/modules/plugins-atlas-tests.md
    blob: 5ffce3b30b82a1a8aca03ad1b59229187de33c6c
  - path: docs/atlas/modules/plugins-council.md
    blob: a9776eaa1839130575e4b5294ce9092084498934
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: 0cc746ce2f241a1d5a995fade38cf620423ed402
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: 002060baf98539410eaf94a3de127be09f05c24e
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: d100ed9ab0dffa400fe80ada7906d1842af44752
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: 75f6e1586e96755406291176da2d76dd4a5a2632
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: 33105d48390d6d41b55fd15e031c23c00711c66e
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: c864cf274759cdd836c63cd8b04903bcd76182d0
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: 8121848f2ae9283251097b61ee0e1677c020344d
  - path: docs/atlas/modules/plugins-forge-bin.md
    blob: 243f38c21cc575b264fb66e21b574acff0707147
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: 1165d446626bc0b1d8b201458d6d9c3b4554806d
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: a18f1c2df1cb40bb7bbe1a004cbe52e3c7889d29
  - path: docs/atlas/modules/plugins-forge-references.md
    blob: eaea7e932abc28022cf3ac0fc6d815b25d1565f2
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: bb975385231a8db011ec923309cbe6f95b995df3
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 1687e64dff30961bb46cfd14abc4ce330ecfb630
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 23f7c913dd013cd09ab07c4623ea7e0b0cd69068
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 22404b72d93eedeb50a5d0f5f0bba9a99eeb8419
  - path: docs/atlas/modules/plugins-rca.md
    blob: b0a9851562b9d4d4bc537065edaf59c36d62f0e8
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: 5e5126d32f89d8fe302e022e727762b5720749a9
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: df14bfd23880eb2ab5ab326f493cfcf67afe2094
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: 905bad0c2736244e9391d00760a7d442eda72660
  - path: docs/atlas/modules/plugins-semver-tests.md
    blob: e7af975f76741c2123925b7828eb142a2e958a19
  - path: docs/atlas/modules/root-misc.md
    blob: 6fa0a9f041c69d1a1151a0420f56853c2fad0e96
  - path: docs/atlas/modules/tests.md
    blob: 6969eb85a2db40c7d0b8c1cf62ed14133ece8138
scopes:
  - tree: plugins
    sha: 1aeb8d775b58d2b80eccbceda1dd0d01c4bdebda
  - tree: tests
    sha: f726161a1df6bcd639771ffdde7d527eaba66cdf
generator: cartographer/1
baseline: b9203a6997fdbc2248086c1aa9ee6f62b1e025b6
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
