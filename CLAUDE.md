# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Agentics is a Claude Code plugin marketplace (`mikeydotio/agentics`) providing plugins for idea-to-execution workflows, root cause analysis, and semantic versioning.

## Architecture

**Marketplace manifest**: `.claude-plugin/marketplace.json` registers all plugins with name, description, and source path.

**Plugin pattern**: Each plugin under `plugins/` has:
- `.claude-plugin/plugin.json` — manifest (name, description)
- `skills/<name>/SKILL.md` — main skill with YAML frontmatter (`name`, `description`, optional `argument-hint`) + markdown instructions that act as the orchestrator
- `agents/<name>.md` — specialized subagent prompts with role descriptions, tool restrictions, and mandatory initial-read protocol (most agents now live in the shared `plugins/agents/agents/` library; consuming plugins use `agent-overrides/` for pipeline-specific context)
- `references/<topic>.md` — methodology docs and detailed protocols that skills reference (keeps SKILL.md lean)

**Key design patterns**:
- **Artifact-based resumption**: Plugins use namespaced artifact directories — forge writes to `.forge/`, rca to `.rca/<slug>/` (gitignored). Presence of specific files determines resume point.
- **Multi-agent orchestration**: One orchestrator skill spawns specialized agents at appropriate steps. Each agent has distinct tool access and perspective.
- **One question at a time**: All user interactions use `AskUserQuestion` with exactly one question per call.
- **Step exit protocol**: Every orchestrated step writes artifacts, handoff, commits, and queues freshen for context clearing before the next step.

## Plugins

| Plugin | Skill | Purpose |
|--------|-------|---------|
| agents | `/agents` | Shared agent library — 29 research-backed specialist agent definitions (16 general-purpose, 3 platform-specific UX, 10 pipeline-specific) used by forge, rca, atlas, and future plugins. |
| atlas | `/atlas` | Committed codebase maps for agentic tools: docs/atlas/ with a token-budgeted INDEX (@imported via CLAUDE.md) + per-module docs. v2 is a deterministic **projection** — a script extracts structure, the LLM produces only content-addressed *judgment* cells (docs/atlas/judgments.json), and `project` renders the docs; a no-change rebuild calls no model. Hybrid extraction (tree-sitter helper or regex fallback); git-aware updates re-judge only the delta; staleness-tiered SessionStart hook. See references/design-v2.md. Uses shared agents (cartographer-as-annotator, map-verifier). |
| forge | `/forge` | Unified idea-to-deployment pipeline: interrogation → research → design → planning → decompose → execute → review → validate → triage → document → deploy. Uses shared agents from the `agents` plugin. FIX/ESCALATE triage loop. Has SessionStart and Stop hooks. |
| rca | `/rca` | Root cause analysis: symptom intake → evidence collection → hypothesis formation → verification → remediation. Uses shared agents (investigator, evidence-collector, hypothesis-challenger, software-architect). |
| semver | `/semver` | Version lifecycle: tracking, bumping, changelog generation, sync validation. Has SessionStart and PostToolUse hooks. |

## Runtime Dependencies

**tmux** is a hard requirement for the freshen plugin and all hook-based context-clearing flows (forge step transitions). Without tmux, these flows fall back to manual `/clear` instructions.

**Hook ordering**: Claude Code does **not** guarantee execution order between different plugins' hooks registered on the same event (e.g. forge's and freshen's `Stop` hooks both fire on every Stop event, in unspecified order). tmux buffering (keystrokes sent by a Stop hook aren't acted on until all of that turn's hooks finish) only governs *when* an already-sent command is processed — it does not make cross-plugin ordering safe for hooks that depend on *each other's side effects* (e.g. one hook writing a signal file another hook reads). Where that matters, the dependent hook must be self-sufficient rather than assuming a write from another plugin's hook already happened — see forge's `hooks/session-stop.sh` and `references/auto-resume.md`'s **Cross-Plugin Hook Ordering** section for a worked example (and its `.freshen/.clear-pending` idempotency guard for avoiding a double action when both hooks *do* end up doing the same thing in one batch).

## When Adding a New Plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with `name` and `description` (the `version` field is auto-managed — see below)
2. Add the skill in `plugins/<name>/skills/<name>/SKILL.md`
3. Register in `.claude-plugin/marketplace.json`
4. Keep SKILL.md as a thin router dispatching to reference docs for detailed procedures

## Plugin Version Sync

The whole marketplace shares the single repo `VERSION`. The post-bump hook
`.semver/hooks/post-bump/01-sync-plugin-versions.sh` stamps the bare version into
the top-level `.claude-plugin/marketplace.json` and each
`plugins/*/.claude-plugin/plugin.json` `version` field on every `/semver bump`,
folding the change into the release commit and moving the (unpushed) tag onto it.
This is one-way (`VERSION` → manifests) and deliberately over-eager: unchanged
plugins are restamped too, so a bump can never miss one.

- **Do not hand-edit** the `version` field in any manifest — it is derived.
- To seed a brand-new plugin or repair drift between bumps, run the hook standalone:
  `bash .semver/hooks/post-bump/01-sync-plugin-versions.sh` (files only, no git ops).
- `tests/plugin-versions.sh` (in `make test`) fails if any manifest drifts from `VERSION`.

## Hardening Roadmap

The forge × storyhook seam underwent a full hardening pass (2026-07 audit + 8-workstream plan,
106 findings — see `~/Enderchest/agentics-harness-audit/`). All landed, one PR per workstream:

- ✅ WS1 — storyhook seam rewrite (verb-first CLI, real JSON shapes, DAG cycle guard)
- ✅ WS2 — state-machine correctness (F009 JSON-path fix, review/validate deadlock, resume spine)
- ✅ WS8 (F103) — docs↔CLI contract guard, regression-proofs the seam
- ✅ Critical fix — decompose's auto-created parent story could permanently deadlock `execute`
  (found by live dry-run, not in the original 106 findings)
- ✅ WS3 — agent alignment (real `agents:*` types, tool restrictions actually bind)
- ✅ WS4 — loop bookkeeping scripted (lock, verdicts, integrity, crash-recovery, predecessor-diff)
- ✅ WS5 — step-exit consolidated (fixed a live cross-project relative-path bug in all 12 step skills)
- ✅ WS7 — hooks/greenlight/portability (breaker correctness, greenlight tests+hardening, BSD/macOS)
- ✅ WS6 — tmux determinism (capture-pane verification, transition audit log)
- ✅ agentics#33 — re-scoped from "build a supervisor" to instrumentation: `forge-state.sh` now
  emits `category`/`auto_advance`/`transition_id` (the router's own pass_through vs.
  fix_loop/blocked_review/escalate_review/deploy_gate/report_complete classification, named
  instead of left implicit in `dispatch`), `--record-transition` and `forge-step-exit.sh
  --transition-id` log correlated predicted/actual lines to `.freshen/transitions.log`, and
  `forge-transition-report.sh` correlates them by id (not position) into matched/orphaned-
  predicted/orphaned-actual buckets. Pure telemetry — nothing acts on `category`/`auto_advance`
  yet. A full supervisor (or the issue's original "Level 1.5" helper) remains explicitly **not
  built**: WS6 already delivers confirmed/audited sends, and a bash reimplementation of
  categories 2–6's judgment (fix_loop's mandatory archive call, the three human-gate states)
  would be a second source of truth for exactly the class of drift `forge-contract-check.sh`
  exists to catch. Revisit only on a concrete signal — `transitions.log` data showing category-1
  transitions are a non-trivial cost, a predicted/actual mismatch (a real misroute), or a
  persistent orphaned-predicted count — not on a schedule. Full design doc:
  [agentics#33 comment](https://github.com/mikeydotio/agentics/issues/33#issuecomment-4879731013).
  Pane-option state migration remains separately deferred (reasoning in
  `plugins/forge/references/auto-resume.md`).
- ✅ storyhook repo portability follow-up (F074) — `post-git.sh`'s python3 spawn fixed
  ([storyhook#11](https://github.com/mikeydotio/storyhook/pull/11)); `session-start.sh`'s
  sed-based cwd parse investigated and left intentionally unchanged (a tested design constraint
  bans python3 there) — [storyhook#10](https://github.com/mikeydotio/storyhook/issues/10) closed

<!-- semver:start -->
## Semantic Versioning

This project uses semantic versioning managed by the `/semver` plugin.

### Version Awareness
- Read the `VERSION` file at the start of each conversation to know the current version.
- Read `.semver/config.yaml` to understand the versioning configuration.
- When discussing releases, deployments, or changes, reference the current version.

### Commit Discipline
- Write meaningful, descriptive commit messages. Each commit message may appear in an auto-generated changelog.
- Use conventional-commit-style prefixes when they fit naturally: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- The first line of the commit message should be a concise summary (under 72 characters). Add detail in the body if needed.

### Version Bump Guidance
When recommending or performing a version bump:
- **patch** (0.0.x): Bug fixes, documentation corrections, minor refactors with no behavior change.
- **minor** (0.x.0): New features, new capabilities, non-breaking additions to the public API or user-facing behavior.
- **major** (x.0.0): Breaking changes — removed features, changed interfaces, incompatible API modifications, behavior changes that require consumers to update.

When you notice the user has completed a logical unit of work, suggest running `/semver bump` with the appropriate level.

### Hooks
- Custom pre-bump and post-bump hooks can be added in `.semver/hooks/`.
- Never trigger `/semver bump` from within a hook — this causes infinite recursion.

### Configuration
Versioning settings are in `.semver/config.yaml`. Do not modify this file unless the user explicitly asks to change semver settings.
<!-- semver:end -->

<!-- atlas:start -->
## Codebase Map (atlas)

@docs/atlas/INDEX.md

- The imported INDEX above is this project's codebase map. Use its routing
  table: read the listed module doc before working in that area.
- The map covers code structure only; build/test/workflow guidance lives in
  the rest of this file.
- After committing changes to mapped source files, suggest running
  `/atlas update`.
<!-- atlas:end -->
