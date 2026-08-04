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
| agents | `/agents` | Shared agent library — 28 research-backed specialist agent definitions (17 general-purpose, 3 platform-specific UX, 8 pipeline-specific) used by forge, rca, and future plugins. |
| forge | `/forge` | Unified idea-to-deployment pipeline: interrogation → research → design → planning → decompose → execute → review → validate → triage → document → deploy. Uses shared agents from the `agents` plugin. FIX/ESCALATE triage loop. Has SessionStart and Stop hooks. |
| rca | `/rca` | Reproduction-gated RCA for known defects: KT IS/IS-NOT intake → firm repro gate (automated failing test; user/council override only) → git forensics (bisect/blame/pickaxe/hotspots via bin/ scripts) → competing-hypothesis falsification in disposable worktrees → ODC classification + surgical-vs-redesign verdict → caller gate (fix now vs hand off) → two-hats gated fix → committed blameless postmortem (docs/rca/). Orchestrator + 7 step subskills (forge-style direct-Read dispatch); latches GitHub/storyhook issues; uses shared agents (qa-engineer, investigator, evidence-collector, experimenter, hypothesis-challenger, software-architect, software-engineer, technical-writer). |
| reconcile-pr | `/reconcile-pr` | Rebase a GitHub PR onto its base branch as a hybrid state machine (`bin/reconcile-pr.sh`): preflight → start → resolve/continue loop → test → push → comment → cleanup. Deterministic script owns every git/gh mechanic + the force-push safety gate (destination-ref guard, explicit-OID `--force-with-lease`, never bare `--force`, never a protected branch); the SKILL only drives conflict resolution (base_side/pr_side zdiff3 labeling), behavior verification, and the summary. Isolated worktree under `.claude/worktrees/`. Refuses fork PRs in v1. |
| semver | `/semver` | Version lifecycle: tracking, bumping, changelog generation, sync validation. Has SessionStart and PostToolUse hooks. |

## Runtime Dependencies

**tmux** is a hard requirement for the freshen plugin and all hook-based context-clearing flows (forge step transitions). Without tmux, these flows fall back to manual `/clear` instructions.

**storyhook** is a hard test-time requirement, and this repository's suites are written against **storyhook major 2** (>=2.0.0, <3.0.0). The pin is enforced by `tests/storyhook-version-pin.sh` (`make test-storyhook-version-pin`), which fails the gate naming the observed and expected versions — an incompatible or unverifiable CLI is never skipped into a green. Measured on the real v1.0.0 binary: 87 failing assertions across three suites, none naming a version. Raising the pin means porting the suites, then changing `STORYHOOK_MAJOR` in that file *and* this sentence together.

**Bounded commands must never be captured through `$(…)`** — `timeout` signals only the process
group it created, so a descendant that `setsid()`s out of that group survives, keeps the
substitution's pipe open, and holds the caller for its whole lifetime while the bound *looks*
intact (measured **30.08s against a 5s bound**; redirect-to-file is 0.03s; `--kill-after` does not
help). Redirect to a temp file and read it back with `$(<file)` — see
`plugins/forge/hooks/session-stop.sh:194-200`. Enforced by `tests/bounded-capture-guard.sh`
(`make test-bounded-capture-guard`) in four positively-pinned layers, so **writing a new
`timeout`/`gtimeout` call site, or a new call of a bounding wrapper, reds the gate by design** —
that is the layer asking you to decide whether the new output can ever reach a caller's pipe, not
a nuisance to silence. If it can, add the wrapper's name to `REGISTRY` in that file. Deliberately
*not* covered: hand-rolled bounds (background pid + `kill -TERM`, used twice in rca), `perl -e
alarm`, and bounds reached through a variable.

**greenlight classifies the storyhook CLI by verb, and the rule for adding one is mechanical.**
The bare command name is **not** in `is_always_safe` and must never be re-added — that table
promises *"no flags or arguments can make them destructive"*, which is false for a CLI whose purge
and project-delete verbs are documented "There is no undo", whose update verb "atomically replaces
the running executable", and whose plugin verb installs third-party code. `is_safe_story()` returns
three ways: **allow** iff the worst case is a wrong story record in the current project, repairable
by another verb of the same CLI; **destructive (2)** only if `is_known_destructive` *already* ranks
an equivalent operation at 2 by command name, with that peer named in a comment at the arm (purge
and project-delete mirror `rm|rmdir|unlink|shred`; update and plugin-install mirror
`apt|brew|yum|dnf|pacman`); **uncertain (1)** for everything else, including every unrecognised
verb. The peer requirement is load-bearing — it makes bucket 2 self-limiting, since it cannot grow
without someone first editing `is_known_destructive`, a far louder act than editing an allowlist,
and it is why no rename of `any_destructive` was needed. Enforced by
`plugins/greenlight/tests/greenlight-story.bats`, whose allowlist pin asserts **set equality**, so
it reds on a narrowing exactly as it reds on a widening — **a removed verb may be a MAJOR bump**,
because shipped docs instruct agents to type some of them.

⚠ Three traps there. **The verb surface cannot be enumerated from the CLI** — its own `help --all`
yields 45 headings of which 4 are not commands, its usage block yields 48, and two more verbs
execute while appearing in *neither*; that is why unknown verbs fail closed and why no completeness
guard exists (a sentinel test pins the fail-closed default instead). **The extractor must follow
`is_safe_git`, never `is_safe_gh`** — storyhook accepts global flags *before* the verb and two of
them take a value (`--store-path`, `--project`), so `is_safe_gh`'s `$(i+1)` form reads `--json` as
the verb and a flag-skipper that ignores values reads the path as the verb. **Do not add flag
predicates** — the doctor verb is denied whole rather than split on `--fix`, because every flag
predicate is a permanent bypass surface.

⚠ **Do not write a guard that greps shipped docs for "verbs an agent is told to type."** It was
proposed, voted for, and withdrawn by all three council seats on measurement: the only occurrences
of the purge and project-delete forms in shipped `plugins/**` were inside greenlight's *own comment
describing the defect*, so the guard would have read the sentence documenting the bug as a mandate
to keep the verb auto-approved — while reporting green. The transferable rule:
`bounded-capture-guard.sh` is sound because a `timeout` call is **shell syntax in a shell file**, a
decidable predicate over a formal grammar; the same verb inside a markdown skill is **prose**. Same
shape, different kind. Full trail: `.council/age26-greenlight-story-verb-surface/DECISION.md`.

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
- This hook runs automatically after every `/semver bump` (or a direct
  `semver-cli bump execute` — e.g. the non-interactive path for bumping on a
  feature branch) regardless of whether `--plugin-root` is passed; the CLI
  locates its own hook runner (fixed since AGE-3, v2.38.0-era regression). A
  bump's JSON exits `3` (not `0`) if hooks were pending but genuinely could
  not run — check `post_hooks.warnings` before reaching for the manual
  repair step above.

### Cache is version-keyed — shipped content changes MUST bump

Claude Code caches each plugin by its **version string**: an install that already
extracted version `X` never re-extracts `X` again, even when the marketplace's
content for `X` later changes. So **any change to shipped `plugins/**` runtime
content must ship with a `/semver bump`** — never mutate an already-released
version's content in place, or installs keep running the old code while the
manifest reports the (unchanged) version. This was issue #71: a deployit fix
stranded under an unbumped `2.25.1`, so no install ever received it.

- `tests/plugin-content-drift.sh` (in `make test`) enforces this — it fails the
  pre-push gate if shipped content under `plugins/**` differs from the release tag
  `v<VERSION>` (git blob OIDs are content hashes; the check is a `git diff <tag>
  HEAD`). "Shipped" excludes plugin `tests/`, `*.bats`, and plugin `README.md`; a
  `/semver bump` retags at the new HEAD, which clears the guard.
- **Landing a release-bump PR** (keep the tag from being stranded): let
  `/semver bump` create the local tag, push the **branch only** (never the tag);
  after the PR merges, re-point the tag onto main's release commit and push it
  cleanly — `git tag -f v<X.Y.Z> <main-release-sha>` then
  `git push origin v<X.Y.Z>` (no force needed on a first push). Then
  `/semver validate` should be all-PASS.

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

### Releasing via GitHub
Any time a PR merges to main, perform a `/semver bump` (you choose the most appropriate component to bump), PR-and-merge the VERSION change, and then publish a github release for the new version.

### Hooks
- Custom pre-bump and post-bump hooks can be added in `.semver/hooks/`.
- Never trigger `/semver bump` from within a hook — this causes infinite recursion.

### Configuration
Versioning settings are in `.semver/config.yaml`. Do not modify this file unless the user explicitly asks to change semver settings.
<!-- semver:end -->
