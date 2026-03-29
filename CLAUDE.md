# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Agentic Workflows is a Claude Code plugin marketplace (`mikeydotio/agentic-workflows`) providing plugins for idea-to-execution workflows, root cause analysis, and semantic versioning.

## Architecture

**Marketplace manifest**: `.claude-plugin/marketplace.json` registers all plugins with name, description, and source path.

**Plugin pattern**: Each plugin under `plugins/` has:
- `.claude-plugin/plugin.json` — manifest (name, description)
- `skills/<name>/SKILL.md` — main skill with YAML frontmatter (`name`, `description`, optional `argument-hint`) + markdown instructions that act as the orchestrator
- `agents/<name>.md` — specialized subagent prompts with role descriptions, tool restrictions, and mandatory initial-read protocol
- `references/<topic>.md` — methodology docs and detailed protocols that skills reference (keeps SKILL.md lean)

**Key design patterns**:
- **Artifact-based resumption**: Both ideate and rca use `.planning/` artifacts to track phase state. Presence of specific files (IDEA.md, DESIGN.md, PLAN.md) determines resume point.
- **Multi-agent orchestration**: One orchestrator skill spawns specialized agents at appropriate phases. Each agent has distinct tool access and perspective.
- **One question at a time**: All user interactions use `AskUserQuestion` with exactly one question per call.

## Plugins

| Plugin | Skill | Purpose |
|--------|-------|---------|
| ideate | `/ideate` | 5-phase pipeline: interrogation → research → design → planning → execution. 10 specialized agents. |
| rca | `/rca` | Root cause analysis: symptom intake → evidence collection → hypothesis formation → verification → remediation. 5 agents. |
| semver | `/semver` | Version lifecycle: tracking, bumping, changelog generation, sync validation. Has SessionStart and PostToolUse hooks. |

## When Adding a New Plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` with `name` and `description`
2. Add the skill in `plugins/<name>/skills/<name>/SKILL.md`
3. Register in `.claude-plugin/marketplace.json`
4. Keep SKILL.md as a thin router dispatching to reference docs for detailed procedures

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
