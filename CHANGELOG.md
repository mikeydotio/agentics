# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v2.9.1] - 2026-04-06

### Fixed
- resolve freshen.sh path relative to script location (c781671)

_[manual]_

## [v2.9.0] - 2026-04-05

### Fixed
- prevent set -e abort on empty ls|head pipelines (988edef)

_[manual]_

## [v2.8.0] - 2026-04-05

### Added
- add hard rule prohibiting background agent spawning (bfefc53)

_[manual]_

## [v2.7.0] - 2026-04-04

### Added
- run investigation in foreground instead of background (21602a9)

_[manual]_

## [v2.6.0] - 2026-04-03

### Added
- extract deterministic plugin logic into scripts for token reduction (0723dd8)

_[manual]_

## [v2.5.0] - 2026-04-03

### Added
- add /forge resume command, pre-compute resume context in hooks (e1c9680)
- add enable/disable commands for troubleshooting (b9be83d)
- rename sentry plugin to greenlight (8c7bca6)

### Fixed
- distinguish ok/error in EXIT trap stderr output (896b6a2)
- add stderr output to prevent infinite stop-hook loop (4ade8d5)

### Changed
- Merge pull request #1 from mikeydotio/fix/freshen-stop-hook-stderr (8a9b47b)

_[manual]_

## [v2.4.0] - 2026-04-02

### Added
- add Python CLI to minimize LLM round trips (1c220f5)

_[manual]_

## [v2.3.0] - 2026-04-01

### Changed
- **Pilot plugin renamed to Forge** — the unified idea-to-deployment pipeline is now `/forge` with all artifacts in `.forge/`, commit prefixes as `forge(<step>):`, and freshen source `--source forge`; all 11 sub-skill names unchanged (c87bb57)

_[manual]_

## [v2.2.0] - 2026-04-01

### Added
- **Agents plugin** (`/agents`) — shared library of 27 research-backed agent definitions replacing per-plugin agent directories; 16 general-purpose agents (software-engineer, qa-engineer, security-researcher, software-architect, project-manager, technical-writer, copy-editor, skeptic, investigator, accessibility-engineer, performance-engineer, devops-engineer, api-designer, observability-engineer, data-engineer, lawyer), 3 platform-specific UX designers (CLI, web, mobile), and 8 pipeline-specific agents (generator, evaluator, reviewer, validator, triager, domain-researcher, evidence-collector, hypothesis-challenger)
- **11 net-new agents** — copy-editor (LLM-tell detection), skeptic (Socratic questioning), investigator (multi-hypothesis RCA), 3 UX designer variants (CLI/web/mobile), performance-engineer, devops-engineer, api-designer, observability-engineer, data-engineer, lawyer (OSS license compatibility)
- **Cross-plugin agent reference mechanism** — consuming plugins reference shared agents by path and layer pipeline-specific overrides via `agent-overrides/` directories
- **Agent design principles reference** — research synthesis from Anthropic's "Building Effective Agents", Agentailor's tool design principles, and multi-agent orchestration research
- **Agent validation script** (`validate-agents.sh`) — structural validation for frontmatter, tool/read-only consistency, naming, guardrails, and mandatory protocols
- **Tool design audit** (`tool-audit.md`) — audit of all plugin tools against 5 Agentailor principles with prioritized findings

### Changed
- **Pipeline agents rewritten with cross-pollination** — generator draws from Software Engineer (TDD) + Security Researcher (secure-by-default); evaluator draws from QA (edge cases) + Skeptic (debiasing); reviewer expanded to 8-dimensional analysis; validator enforces no-mock policy; triager uses 4-dimension decision framework
- **RCA consolidated from 5 to 2 pipeline agents** — code-archaeologist and systems-analyst absorbed into general-purpose Investigator; remediation-architect absorbed into Software Architect with RCA-specific override
- **Storyhook contract rewritten** — removed false "Commands That DO NOT Exist" section; added full MCP tool catalog with 16 tools; added Interface Selection Guide mapping operations to preferred interface (MCP vs CLI)
- **Decompose skill switched to batch operations** — uses `storyhook_decompose_spec` MCP tool (1 call) instead of sequential CLI story creation (60-80+ calls per plan)
- Pilot and RCA SKILL.md files updated to reference shared agent library paths
- CLAUDE.md updated with agents plugin in plugin table

### Removed
- `plugins/pilot/agents/` — 15 agent files replaced by shared library
- `plugins/rca/agents/` — 5 agent files replaced by shared library (3 consolidated into general-purpose agents)

_[manual]_

## [v2.1.1] - 2026-04-01

### Removed
- **Ideate plugin** — fully removed from marketplace and directory; all functionality lives in pilot (`fed674f`)

### Fixed
- Freshen plugin manifest `author` field must be an object, not a string — caused marketplace install failure (`39eba9d`)

_[manual]_

## [v2.1.0] - 2026-04-01

### Added
- **Unified pilot pipeline** — merged ideate and pilot into a single idea-to-deployment plugin with 11 pipeline skills (interrogate, research, design, plan, decompose, execute, review, validate, triage, document, deploy) orchestrated by a state-machine router (`69fa065`..`828d92b`)
- **3 new agents** — reviewer (static gap/defect analysis), validator (test hardening), triager (FIX/ESCALATE deliberation) (`d512d2d`)
- **FIX/ESCALATE triage loop** — after execution, review + validate run in parallel, then triage labels findings as FIX (auto-fix, max 3 cycles) or ESCALATE (user decides); `--yolo` mode fixes everything up to 10 cycles (`d512d2d`)
- **Step exit protocol** — every orchestrated step writes artifacts, handoff to `.pilot/handoffs/`, commits, and queues freshen for context clearing (`69fa065`)
- **Severity levels and report format** references — standardized Critical/Important/Useful finding structure with solution options and pros/cons (`d512d2d`)
- **Legacy migration detection** — pilot orchestrator detects `.planning/ideate/` artifacts and offers to migrate them to `.pilot/` (`828d92b`)
- **Post-document pause** — pipeline always pauses after documentation for user review before deployment; deploy never proceeds without explicit permission

### Changed
- Pilot artifacts now live in `.pilot/` (version-controlled handoffs, fix-cycle archives) instead of `.planning/pilot/`
- Handoffs moved from single `.pilot/handoff.md` to versioned `.pilot/handoffs/handoff-<step>.md` directory
- Session hooks updated to read/write from `.pilot/handoffs/` directory
- 12 agents migrated from ideate to pilot with namespace updates (15 total)
- 10 pilot reference docs updated with `.pilot/` path references
- 3 ideate references migrated to pilot (questioning, team-roles, step-handoff)
- CLAUDE.md updated for unified pipeline architecture

### Deprecated
- **Ideate plugin** (`/ideate`) — use `/pilot` instead; deprecation notices added to SKILL.md and README.md

_[manual]_

## [v2.0.0] - 2026-03-31

### Breaking
- **Ideate phases now clear context between each step** — the orchestrator stops after each phase and re-invokes with fresh context via the freshen plugin, changing the user-facing flow from a single continuous session to a multi-session progression
- **Pilot `max_stories_per_session` default changed from 5 to 1** — each story gets a fresh context window; `max_sessions` raised from 10 to 50 to compensate

### Added
- **Freshen plugin** (`/freshen`) — portable automatic context clearing via tmux send-keys; any plugin can register a post-clear re-invocation signal, and the Stop + SessionStart(clear) hooks handle `/clear` and command dispatch automatically
- **Phase Transition Protocol** for ideate — each phase writes a handoff document (`.planning/handoff-phase-N.md`), commits artifacts, queues a freshen signal, and stops
- **Phase handoff specification** (`references/phase-handoff.md`) — defines handoff format for each phase transition with phase-specific content requirements
- **Cold-Start Essentials** for pilot handoffs — patterns established, micro-decisions, code landmarks, and test state are now mandatory sections
- **Incremental handoff writes** in pilot execution loop — handoff.md updates after every completed story, not just at pause
- **Context Validation step** (6a) in pilot recovery — cross-checks handoff claims against disk state before resuming
- **Missing-handoff protocol** — both ideate and pilot now pause and ask the user what to do via AskUserQuestion when a handoff document is missing, rather than silently continuing with degraded context

### Changed
- Ideate **Pilot Invitation** replaces Phase 4.5 — now a resumption path (not an inline gate) that activates when PLAN.md is found after context clear
- Pilot handoff elevated from "best-effort" to **primary context source** across recovery-protocol.md, handoff-format.md, and SKILL.md
- Fixed broken reference in ideate SKILL.md (`work-handoff.md` → `pilot-handoff.md`)
- Fixed typo in ideate resumption protocol ("pilot" → "ideate")

_[manual]_

## [v1.5.0] - 2026-03-30

### Added
- **Greenlight plugin** (`/greenlight`) — intelligent PreToolUse safety hook that intercepts dangerous commands (destructive git operations, broad file deletions, production deployments) and enforces confirmation or blocking policies (1d9d4ab)

_[manual]_

## [v1.4.0] - 2026-03-30

### Removed
- **Memory plugin** (`/memory`) — collides with built-in Claude Code command; memory functionality will move to the memlayer repo as its own plugin (`a64050e`)

### Changed
- Cleaned up pilot plugin references to memory (execution loop, handoff format, completion sequence) (`a64050e`)

_[manual]_

## [v1.3.0] - 2026-03-30

### Added
- **Pilot plugin** (`/pilot`) — autonomous execution harness with generator-evaluator loop, story decomposition, session locking, auto-resume via crontab, canary mode, and architectural drift detection (`c6cab14`)
- **Memory plugin** (`/memory`) — graph memory interface with local JSONL cache, entity/relation storage, two-tier recall (local + memlayer), and scale-aware warnings (`c6cab14`)
- **Ideate Phase 4.5** — conductor handoff gate offering autonomous execution via `/pilot` after plan approval (`c6cab14`)
- Test infrastructure using bats-core with 15 tests covering state machine, locking, and plan mapping (`c6cab14`)

### Changed
- Renamed project from handy-plugins to agentic-workflows; tracked `.planning/` directory (`ce06592`)
- Updated marketplace to register 5 plugins (ideate, rca, semver, pilot, memory) (`c6cab14`)

_[manual]_

## [v1.2.0] - 2026-03-29

### Added
- Conductor autonomous workflow guide — end-to-end documentation for plan-to-completion autonomous execution (`5434010`)

### Fixed
- Session-start hook now uses `additionalContext` instead of `systemMessage` for proper context injection (`2d47db8`)

### Changed
- Track tool config files (`.storyhook`, `.semver`) and gitignore `.planning/` directory (`5ec366e`)

_[manual]_

## [v1.1.0] - 2026-03-28

### Added
- Git-root enforcement — semver tracking now requires `.semver/` to be at the git root; subprojects must use separate git repos
- Configurable git tagging — new `git_tagging` config option (default: true) to enable/disable tag creation on bump
- `--no-tags` flag for `tracking start` to initialize with tagging disabled

### Changed
- Version-commit is now the primary anchor instead of git tags — `semver current` and bump pre-checks use the last VERSION-changing commit, not the last tag
- Session-start hook output simplified to `<Project> version: <version>` instead of verbose status line
- Validation checks 3, 4, 6 (tag-related) now skip gracefully when `git_tagging: false`
- Post-push hook messages reference "last version change" instead of "last tag"

_[manual]_

## [v1.0.0] - 2026-03-28

### Added
- Initial release of the Agentic Workflows marketplace
- Ideate plugin — idea interrogation, design, planning, and execution with cross-functional agent teams
- RCA plugin — root cause analysis with evidence collection, hypothesis testing, and remediation planning
- Semver plugin — semantic versioning lifecycle management with auto-bump hooks, changelog generation, and sync validation

_[manual]_
