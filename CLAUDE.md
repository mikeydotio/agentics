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

**Hook ordering**: When Claude Code's turn ends, tmux buffers keystrokes until the prompt accepts input. This means `/clear` sent by the Stop hook is not processed until all Stop hooks complete, so ordering between hooks is safe by design.

## When Adding a New Plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with `name` and `description` (the `version` field is auto-managed — see below)
2. Add the skill in `plugins/<name>/skills/<name>/SKILL.md`
3. Register in `.claude-plugin/marketplace.json`
4. Keep SKILL.md as a thin router dispatching to reference docs for detailed procedures

## Plugin Version Sync

Every plugin shares the single repo `VERSION`. The post-bump hook
`.semver/hooks/post-bump/01-sync-plugin-versions.sh` stamps the bare version into
each `plugins/*/.claude-plugin/plugin.json` `version` field on every `/semver bump`,
folding the change into the release commit and moving the (unpushed) tag onto it.
This is one-way (`VERSION` → manifests) and deliberately over-eager: unchanged
plugins are restamped too, so a bump can never miss one.

- **Do not hand-edit** the `version` field in a `plugin.json` — it is derived.
- To seed a brand-new plugin or repair drift between bumps, run the hook standalone:
  `bash .semver/hooks/post-bump/01-sync-plugin-versions.sh` (files only, no git ops).
- `tests/plugin-versions.bats` fails `make test` if any manifest drifts from `VERSION`.

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
