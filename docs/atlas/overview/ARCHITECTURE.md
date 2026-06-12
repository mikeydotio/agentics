---
module: overview/ARCHITECTURE
summary: "System shape, module relationships, and cross-plugin invariants of the agentics marketplace"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: 7660f14d138892061941645e4718e1166549e2ae
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: bd4e06d5b1bbe2bf0f997ca6429978442f043c03
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: 04d73c6dfc4f0472770a9bc069cb58ff31770e2b
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: 20d0f5c50ec76e17358372e0796c5919d1087a10
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: dbac06fd7e2936fb1d08c6915e4ae2fa16721f74
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: 14fcd93dd6ca38023f9fd627e6a4f83da44f029e
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: 3f6feda3ee4c795c686cdc3daa6d39013224a806
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 690ca7eaf33df8ddaaa089a1d2a6bc80349191e3
  - path: docs/atlas/modules/plugins-atlas-tests.md
    blob: 9c2a2fbea959c44503bdbce64a0e1c7b7a0e07bd
  - path: docs/atlas/modules/plugins-council.md
    blob: d63d87dfe2ecc25a1368d63b32c59998123dfc27
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: 7ee2a83d4f82157399ffb796e40388f5ae352bc8
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: ea1df1776368bec4144f7717efe3047284cec400
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 3cfc11747c26171f99fbdf6c9e96b1f239bb336d
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: 1fde5292bb1ce0ba95fc58dd6caaec0c0b1de97e
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: 3fbd504b865ddcfbcaad14e21c7df4f59fa8e3e7
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 235419db6d820abfd0fc37cae5c77e546f62a1c8
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: 43b986b77cf04bac0010f5419aa3aceb0ac8e4aa
  - path: docs/atlas/modules/plugins-forge-bin.md
    blob: c6823510f72cf9dff23162c687387ea2b58125fa
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: a231b5effc8e1a04408e80545a1e5235dc10fa8f
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: fe6e8805aaaddfe46af33ebff2165f0aa8e7561d
  - path: docs/atlas/modules/plugins-forge-references.md
    blob: 55b59186bb3edbb765ae8173c2b1dd2c940eb8de
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: 4e99ebb9dcac5679025b2c3704dcd5f0767194a7
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 183412f3940cf8c34e76f0a0a4b7cab6f67db1e9
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 3d5664baba847c5ed5d037ad77722cd79ed84e64
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: e3af22ed35b7708182b55e5bafdf35e78b778b55
  - path: docs/atlas/modules/plugins-rca.md
    blob: 89c49df2a95019de19802da19e9779d9258d0992
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: eacacdd599b18ffd3d2be37f1d10263c7b64a9da
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: caf60c9dbc5c0c107c01a6dd7af46ccaa3e09c80
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: 8e7302e61947f26e352a9c110f62591d57f0b3a5
  - path: docs/atlas/modules/plugins-semver-tests.md
    blob: e870abbfa5bc1f7b84e76ceef67a9c903fd36bca
  - path: docs/atlas/modules/root-misc.md
    blob: 4654a6c93293f17dc9d52b0a87ca7d5d39996c24
  - path: docs/atlas/modules/tests.md
    blob: ff960fb0024aae037ef342b645238f358a612643
scopes:
  - tree: plugins
    sha: 37589c1691d9bf073b6cf3587bfa051850d6d24d
  - tree: tests
    sha: f726161a1df6bcd639771ffdde7d527eaba66cdf
  - tree: docs
    sha: 8bc1f9594b5410680ea544876a4d7443c3aa721d
generator: cartographer/1
baseline: cdb99b78f7feadd24f898adb2545c7589790c375
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
