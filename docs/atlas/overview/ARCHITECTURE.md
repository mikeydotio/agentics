---
module: overview/ARCHITECTURE
summary: "System shape, module relationships, and cross-plugin invariants of the agentics marketplace"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: ff1636aeac1a65d31ec77b16c1f5b60e78083e40
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: 5b4e29e8474ef0fb3a9540dac318cfaf7a7d32e1
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: 93bead5ffb02b1feb95ded578f04afb895f2dc97
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: b89cd071d6e2220adbc36f5cce2247fe63914a06
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: b8a31be15884358ea01477412b0efea31cbf24ea
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: 5c3fa913f4390e9cba2523b704e47c78d936d53f
  - path: docs/atlas/modules/plugins-atlas-misc.md
    blob: 94c6efce9edff2df84bb1501a356ce2f07662776
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: a29a40ced4db7df2c4eab61223e5222456d39216
  - path: docs/atlas/modules/plugins-atlas-tests.md
    blob: fe39de0803127b4f290602548559c234c81ba5c4
  - path: docs/atlas/modules/plugins-council.md
    blob: 6793ff08dbb7e9e761c21af507d337b91afc90ef
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: 6b63071d60db5bbf1ae7d039419d9804a24f28ac
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: 289446b530bfc93d7a494726d76f92cef1cf0852
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 7342e5ae5dc6596e7fb352fd0e45d5b64a75e9d6
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: 0f1dd53b966f858368803ebc3d8d87ecfa54fd12
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: c3c9a5fd479c8b5f5ab2e5b91d2b3b8348eb6a23
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 2dfde1572c249e37b9c3b4b16bd12595f2644b19
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: ec96b49c0e1f1dcfd61a43ed020a5f109e6c5529
  - path: docs/atlas/modules/plugins-forge-bin.md
    blob: ddfd98e1f7b190c3510eee328514398dfb3f9f2a
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: 9a127e208e1838b863d8df6651bc5c520e68a8c2
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: 40e607e81dedc14bb5548d34598ee4b8318d50f9
  - path: docs/atlas/modules/plugins-forge-references.md
    blob: 0446ad46e1b382076654118c65c9365c8d8aab5e
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: 086176fee223d3dbfae264f8319008cf6deff583
  - path: docs/atlas/modules/plugins-freshen.md
    blob: 278ec432b0a4739dc7474d2ac92f0486d07782cf
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 0fa444f69698c645f5229d6b387d2ae308440097
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 943e74c200614ff71ce0b2843e8d0659bdf28834
  - path: docs/atlas/modules/plugins-rca.md
    blob: e9b1674223a1517e6898f6f56703dbe92cee03cb
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: 698539ea14918a32ae6e54969932b33055833723
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: c348be508a5490cec16a160af8029990c6d1da2b
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: efcaf48896c923fb43043c2622b207b0827c75de
  - path: docs/atlas/modules/plugins-semver-tests.md
    blob: 282687a438e32701babf077aef13b498446cf142
  - path: docs/atlas/modules/root-misc.md
    blob: 775305d548ef7054925d8367eb8e0a59bbf55aaa
  - path: docs/atlas/modules/tests.md
    blob: 9f299fc251cb39f9853ed9ced6a9c70ed109238b
scopes:
  - tree: plugins
    sha: 8b6510659ad9af77aa4b7197286686e31c9c958a
  - tree: tests
    sha: f726161a1df6bcd639771ffdde7d527eaba66cdf
generator: cartographer/1
baseline: 0ce4ca44c3cc0b4a95d86862de8dc79914ffacbf
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
