---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/plugins-agents-agents-chunk-1.md
    blob: e298868c4fe44637ccec2c3e1a337895801aee07
  - path: docs/atlas/modules/plugins-agents-agents-chunk-2.md
    blob: efb10c7091df45ef0a619e68b9c4116eddb7e068
  - path: docs/atlas/modules/plugins-agents-agents-chunk-3.md
    blob: 48d1c592dd27666315114359452107365279bff4
  - path: docs/atlas/modules/plugins-agents-agents-ux.md
    blob: 8c97acba3a92a32992e353b1b8c0fe2f8375fab6
  - path: docs/atlas/modules/plugins-agents-misc.md
    blob: 775c32a25a595af8e61bcc60dcc393911ed1d1e7
  - path: docs/atlas/modules/plugins-agents-references.md
    blob: f9c18a39dbf7a8a02777299b693961bdf0882afb
  - path: docs/atlas/modules/plugins-atlas-agent-overrides.md
    blob: 69774fe403f30365f15457011e9b4e8c39d8fa5a
  - path: docs/atlas/modules/plugins-atlas-chunk-1.md
    blob: e09e191df500a5ae4619e23ad3c05a7a39ed9095
  - path: docs/atlas/modules/plugins-atlas-chunk-2.md
    blob: 358f8e4fe42ef3ce8d29491e0e73f813405c4ebc
  - path: docs/atlas/modules/plugins-atlas-references.md
    blob: 7156d5e4525cd3fe07c88ba95032ec1edae6f8ce
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-1.md
    blob: 44a4bad1244ad868f970d22db9cd8587f83ac890
  - path: docs/atlas/modules/plugins-atlas-tests-chunk-2.md
    blob: d6b7d53b52628ba71253dfff7ac5934e8b8c01a4
  - path: docs/atlas/modules/plugins-council.md
    blob: a6c39b294498fb6c95db4823c51b9f423385fe34
  - path: docs/atlas/modules/plugins-deployit-assets.md
    blob: 4106112addd43130f94a8baba889de6099e78d4e
  - path: docs/atlas/modules/plugins-deployit-bin.md
    blob: fff7cdaa8fde7f5b0daef915ae8b26e67bb880f0
  - path: docs/atlas/modules/plugins-deployit-misc.md
    blob: 9142f71be5593b23e3154cfd3ecaa7c2f9c4ac87
  - path: docs/atlas/modules/plugins-deployit-references.md
    blob: dda42723ade6eef2e4851a654d8a6c1ffb614ce6
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-1.md
    blob: c365e48e805d06a0ccbe9c9b636b44422cc45fd6
  - path: docs/atlas/modules/plugins-deployit-tests-chunk-2.md
    blob: 81c9be08ee99cf145bd42892dd8d7768e6f79905
  - path: docs/atlas/modules/plugins-forge-agent-overrides.md
    blob: d074233fad9cbc2b6cab6b5b4350d2c0371f0d21
  - path: docs/atlas/modules/plugins-forge-bin.md
    blob: bc58d9a50483985438c764db4ed91357fdc713a8
  - path: docs/atlas/modules/plugins-forge-hooks.md
    blob: 0d8a1cab22e9b75a8a0f357d717d62b2daaf5c4d
  - path: docs/atlas/modules/plugins-forge-misc.md
    blob: 0dc9f2e34ca3a279a94af08921d0170ad2a752c2
  - path: docs/atlas/modules/plugins-forge-references.md
    blob: f047a417dbd025fca941464e119d1ba16067cb69
  - path: docs/atlas/modules/plugins-forge-skills.md
    blob: 2de6926ff1bd8a8a13d4a0748d25e9070944a909
  - path: docs/atlas/modules/plugins-freshen.md
    blob: a13f02ee0d472c2c31bc82997563b7ca8bae747f
  - path: docs/atlas/modules/plugins-greenlight.md
    blob: 20ca7ce7234e12e6b61d044e20462bf52c50c8e2
  - path: docs/atlas/modules/plugins-hook-guard.md
    blob: 6d051cbb35b1fdd6f8ada142f105c76266793153
  - path: docs/atlas/modules/plugins-rca.md
    blob: 505138a6a7e548cd6f6c06fb3c9b101a3d316be9
  - path: docs/atlas/modules/plugins-semver-hooks.md
    blob: 9ed8e4367399814a9a5f957926fc0ad80e2208f7
  - path: docs/atlas/modules/plugins-semver-misc.md
    blob: 669fc7ec5faa3ae3085861a05429114aa580c338
  - path: docs/atlas/modules/plugins-semver-references.md
    blob: 5648996af83b0552a7b728c05c5fc888e3894d72
  - path: docs/atlas/modules/plugins-semver-tests.md
    blob: 5e9bb91038653b2f49eec68f42c1f9ee1b12cea7
  - path: docs/atlas/modules/root-misc.md
    blob: 345130bd063c1aea7cbec4ab91160e763788bcfc
  - path: docs/atlas/modules/tests.md
    blob: c5ef2a13077a687028c2624411884cec73d4a8a1
scopes:
  - tree: plugins
    sha: 000d4cac44fca9bd34e58e5e9e646e29224a751a
  - tree: tests
    sha: f726161a1df6bcd639771ffdde7d527eaba66cdf
generator: cartographer/2
baseline: 17e6eccdf80aa97f11750100d58763c65b532c42
---

# Architecture

## System shape

Agentics is a Claude Code plugin marketplace: `.claude-plugin/marketplace.json` is the sole
registry, and each entry under `plugins/<name>/` is an independently installable plugin.
Every plugin follows the same three-layer pattern — a thin skill (SKILL.md) routes user
commands to a deterministic binary layer (bash or stdlib-only Python CLIs), and a references
layer (markdown docs) defines normative contracts the skill consults at dispatch time. This
keeps skills as routers, not implementers.

The shared agent library (`plugins/agents/`) is the cross-cutting seam. Forge, rca, atlas,
and council do not define their own agents; instead they inline shared definitions from
`plugins/agents/agents/` and prepend a pipeline-specific `agent-overrides/` block at spawn
time. All orchestration follows Claude Code's subagent pattern (foreground-only `Agent` tool
calls); the spawning plugin never stores agent output except by reading the artifacts the agent
writes.

State is always artifact-based. Forge's pipeline lives entirely in `.forge/`; rca's
investigations in `.rca/<slug>/`; semver's version state in `.semver/`; atlas's map in
`docs/atlas/` with `.atlas/` for runtime caches. Presence or absence of specific files
determines resume point — no database, no conversation memory.

## Module relationships

- `root-misc.marketplace.json -> plugins-agents-misc (owns)`
- `root-misc.marketplace.json -> plugins-atlas-chunk-1 (owns)`
- `root-misc.marketplace.json -> plugins-council (owns)`
- `root-misc.marketplace.json -> plugins-deployit-misc (owns)`
- `root-misc.marketplace.json -> plugins-forge-misc (owns)`
- `root-misc.marketplace.json -> plugins-freshen (owns)`
- `root-misc.marketplace.json -> plugins-greenlight (owns)`
- `root-misc.marketplace.json -> plugins-hook-guard (owns)`
- `root-misc.marketplace.json -> plugins-rca (owns)`
- `root-misc.marketplace.json -> plugins-semver-misc (owns)`
- `plugins-forge-skills.execute -> plugins-agents-agents-chunk-1.generator (calls)`
- `plugins-forge-skills.execute -> plugins-agents-agents-chunk-1.evaluator (calls)`
- `plugins-forge-skills.research -> plugins-agents-agents-chunk-1.domain-researcher (calls)`
- `plugins-forge-skills.design -> plugins-agents-agents-chunk-2.software-architect (calls)`
- `plugins-forge-skills.plan -> plugins-agents-agents-chunk-2.project-manager (calls)`
- `plugins-forge-skills.review -> plugins-agents-agents-chunk-2.reviewer (calls)`
- `plugins-forge-skills.document -> plugins-agents-agents-chunk-2.technical-writer (calls)`
- `plugins-forge-skills.validate -> plugins-agents-agents-chunk-3.validator (calls)`
- `plugins-forge-skills.triage -> plugins-agents-agents-chunk-3.triager (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-2.investigator (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.evidence-collector (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-1.hypothesis-challenger (calls)`
- `plugins-rca.rca -> plugins-agents-agents-chunk-2.software-architect (calls)`
- `plugins-atlas-chunk-2.SKILL.md -> plugins-agents-agents-chunk-1.cartographer (reads)`
- `plugins-council.council-vote -> plugins-agents-agents-chunk-1.api-designer (calls)`
- `plugins-council.council-vote -> plugins-agents-agents-chunk-2.skeptic (calls)`
- `plugins-forge-skills.forge -> plugins-forge-bin.forge-state.sh (calls)`
- `plugins-forge-skills.forge -> plugins-freshen.cmd_queue (calls)`
- `plugins-forge-hooks.session-stop.sh -> plugins-freshen.forge.signal (writes)`
- `plugins-forge-hooks.session-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-freshen.on-stop.sh -> plugins-hook-guard.stop_guard_check (calls)`
- `plugins-deployit-bin.cmd_bump -> plugins-semver-misc.semver-cli (calls)`
- `plugins-semver-hooks.post-push-check.sh -> plugins-semver-misc.semver-cli (calls)`

## Data flow

**Forge idea-to-deploy**: User invokes `/forge <idea>`. The `forge` skill calls
`forge-state.sh` to derive the pipeline position from `.forge/` artifacts, then dispatches
the next step skill with `--orchestrated`. Each step skill spawns one or more shared agents
(with forge-specific overrides prepended), writes its output artifact to `.forge/`, commits,
calls `forge-step-exit.sh` (which queues a freshen signal), and stops. The `on-stop.sh` hook
writes `.freshen/forge.signal`; freshen's Stop hook sends `/clear` via tmux; the subsequent
SessionStart hook sends `/forge resume`, and the cycle continues until all stories pass
triage or the pipeline reaches `deploy`.

**Atlas map update**: User invokes `/atlas update`. `atlas-router.sh` calls `atlas-cli` to
compute a diff between blob-SHA ledger state and current worktree. For each stale module doc,
the SKILL.md orchestrator spawns a `cartographer` agent (shared definition + atlas
`cartographer-context.md` override) with the assignment and source files injected via
`<files_to_read>`. The agent writes exactly one module doc; `atlas-cli ledger finalize` adds
blob hashes; `atlas-cli index rebuild` regenerates `INDEX.md`.

**RCA investigation**: User invokes `/rca <symptom>`. The skill calls `rca-status.sh` to
find or start a `.rca/<slug>/` investigation. Phase 2 spawns investigator and
evidence-collector in parallel; Phase 3 spawns hypothesis-challenger; Phase 5 spawns
software-architect. Each writes artifacts to `.rca/<slug>/`; phase derives from which files
are present.

## Key invariants

- Deterministic work never runs inside an LLM agent: forge's state machine, atlas's diff/index,
  semver's version math, and deployit's build/stage logic all live in standalone CLIs.
- Skills must not push to git repos directly; only their CLI layers do (semver, deployit).
- The shared agent library is inlined at spawn time — no agent registry or network lookup.
- Every Stop hook sources `plugins/hook-guard/lib/stop-guard.sh` and calls `stop_guard_check`
  before doing work, preventing feedback-loop runaway.
- Freshen's tmux `send-keys` is the only delivery channel for `/clear`; outside tmux it no-ops.
- Atlas cartographers never write `blob`, `sha`, `baseline`, or `verified` fields; `ledger
  finalize` computes those after every agent run.
- Plugin state dirs (`.forge/`, `.rca/`, `.freshen/`) are gitignored; `.forge/config.json`,
  handoffs, and fix-cycles are committed.

<!-- atlas:index-facts -->
- `.claude-plugin/marketplace.json` is the sole plugin registry; plugins live under `plugins/<name>/`
- Plugins: agents, atlas, council, deployit, forge, freshen, greenlight, hook-guard, rca, semver
- `plugins/agents/agents/` is the shared agent library; forge, rca, atlas, and council spawn from it
- Spawning inlines the shared agent definition plus the plugin's `agent-overrides/<x>-context.md`
- State = artifact dirs: `.forge/` `.rca/<slug>/` `.semver/` `.atlas/` `.freshen/`; resume derives from files
- Skills are thin routers; bin/ scripts (bash+jq or stdlib-only python3) own deterministic work
- CLIs emit one JSON object with `ok` + `display` per run; skills halt and show `display` on `ok:false`
- Hooks stay silent when their plugin is inactive and build all JSON with jq, never printf
- Stop hooks source hook-guard's `stop_guard_check`; a SessionStart reset re-arms the breaker
- `freshen` delivers `/clear` + re-invocation only via tmux `send-keys`; outside tmux it no-ops
- Forge steps exit uniformly: write artifact + handoff, commit, queue freshen, STOP
- Forge triage: FIX re-enters at plan (max 3 cycles, 10 yolo); ESCALATE pauses for the user
- Atlas maps update incrementally via the blob-SHA ledger; unchanged docs never reach an LLM
- Tests are mock-free bash harnesses driving real CLIs in throwaway `/tmp` git repos
- `make test` aggregates the semver, deployit, atlas, and root bats suites; pre-push runs it
<!-- /atlas:index-facts -->
