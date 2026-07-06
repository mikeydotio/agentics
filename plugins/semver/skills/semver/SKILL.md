---
name: semver
description: Use when the user wants to manage semantic versioning for their project. Handles version tracking (start/stop), version bumping (major/minor/patch) with changelog generation, assigning an explicit version (set), one-shot initialization (init), reading current version, auto-bump configuration, and sync integrity validation/repair. Commands are /semver current, /semver bump, /semver set, /semver init, /semver tracking, /semver auto-bump, /semver validate, and /semver repair.
argument-hint: <current | bump <major|minor|patch> [--force] | set <vX.Y.Z> | init [vX.Y.Z] | tracking <start [options]|stop> | auto-bump <start|stop> | validate | repair>
model: claude-sonnet-4-6
---

# Semantic Versioning Orchestrator

You manage semantic versioning by delegating deterministic work to the CLI and handling user interaction via structured questions returned by the CLI.

**Router:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/semver-router.sh <ARGUMENTS>`

## Hard Rules

1. **Route all commands through the router** — never call semver-cli directly, **except** the documented second-call execute paths: `bump execute`, `tracking stop-execute`, `set execute`, and `init execute` (each invoked after a Question Loop, as their flow sections describe).
2. **Every question to the user MUST use `AskUserQuestion`** with exactly 1 question per call.
3. **Never fabricate changelog entries** — the CLI generates them from git log.
4. **When CLI returns `ok: false`**, show the `display` field (or `message`) to the user and stop.
5. **Do NOT invoke `/semver bump` from within PROMPT_HOOK.md instructions** — this causes infinite recursion.

## Generic Flow

All commands follow the same pattern:

1. **Route**: Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/semver-router.sh <ARGUMENTS>`
2. **Check result**: If `ok` is false, show `display` or `message` and stop.
3. **Handle questions**: If the response has a `questions` array, present each to the user (see below).
4. **Handle prompt hooks**: If `has_pre_bump_prompt_hook` or `post_hooks.prompt_hook` is present, follow the hook instructions (see below).
5. **Execute**: If questions produced flags, call the execute command with those flags.
6. **Display**: Show the `display` field from the final response.

## Question Loop

When the CLI returns a `questions` array, process each question in order:

```
For each question in questions:
  1. Call AskUserQuestion with the question's header, question, and options
  2. Check the user's selection:
     - If cancel_option matches → stop
     - If special_actions has an entry for this option → handle it (e.g., "run_repair_then_retry" means run /semver repair, then re-run the original command)
     - If flag_mapping has an entry → collect the flag string
     - If command_mapping has an entry → run that CLI command directly
  3. If multi_select is true, collect all selected items using answer_mapping to translate labels to values
```

After processing all questions, if flags were collected, append them to the execute command.

## Bump Flow

The router runs `bump run <type>`, which **gathers state and — on the happy path (no
questions, no pre-bump prompt hook) — executes the bump in the same call**. A clean bump
therefore needs only one round-trip. Inspect the response:

1. If `ok` is false: show the `display`/`message` and stop.
2. If **`executed` is true** → the bump already ran. Then:
   - If `post_hooks.prompt_hook` is not null, follow those instructions. **Do NOT trigger `/semver bump`**.
   - Report any `post_hooks.warnings`, show the `display` field, and stop.
3. If **`executed` is false** → interaction is needed. Continue:
   a. If `no_commits` is true (and not `--force`): show the message and stop.
   b. Process the `questions` array (dirty_tree, wrong_branch, validation_failed, tag_conflict) via the Question Loop.
   c. **Pre-bump PROMPT_HOOK**: If `has_pre_bump_prompt_hook` is true, read the file at `pre_bump_prompt_hook_path` and follow its instructions. Context: bump type, old_version, new_version. **Do NOT trigger `/semver bump`**.
   d. Execute with the collected flags:
      `python3 ${CLAUDE_PLUGIN_ROOT}/bin/semver-cli bump execute <TYPE> --source <manual|force> [collected flags] --plugin-root ${CLAUDE_PLUGIN_ROOT}`
      (use `--source force` if `--force` was used, otherwise `--source manual`).
   e. **Post-bump PROMPT_HOOK**: If the execute result's `post_hooks.prompt_hook` is not null, follow those instructions. **Do NOT trigger `/semver bump`**.
   f. Report any `post_hooks.warnings`, then show the `display` field.

## Set Flow

`/semver set <vX.Y.Z>` assigns an explicit version (skipping the incremental
bump). The router runs `set run <version>`, which gathers state and — on the
happy path — executes in the same call. Mirrors the Bump Flow:

1. If `ok` is false: show the `display`/`message` and stop.
2. If **`executed` is true** → the assignment already ran (a normal set, or a
   coherent re-cut of the current version — check `recut`/`tag_action`). Follow
   `post_hooks.prompt_hook` if present (**do NOT trigger `/semver set`**), report
   `post_hooks.warnings`, show the `display` field, and stop.
3. If **`executed` is false** → interaction is needed. Process the `questions`
   array (`backward_version`, `dirty_tree`, `wrong_branch`, `validation_failed`,
   `tag_conflict`) via the Question Loop, then execute with the collected flags:
   `python3 ${CLAUDE_PLUGIN_ROOT}/bin/semver-cli set execute <version> [collected flags] --source set --plugin-root ${CLAUDE_PLUGIN_ROOT}`
   Then handle `post_hooks.prompt_hook` (**do NOT trigger `/semver set`**), report
   `post_hooks.warnings`, and show the `display` field.

## Init Flow

`/semver init [vX.Y.Z]` enables tracking + auto-bump and initializes the
changelog + version tag (default `v0.1.0`). The router runs `init run [version]`:

1. If `ok` is false: show the `display`/`message` and stop.
2. If **`executed` is true** → a clean init ran (no prior artifacts). Follow
   `post_hooks.prompt_hook` if present, report `post_hooks.warnings`, show the
   `display` field, and stop.
3. If **`executed` is false** → the repo already has semver artifacts; the
   response carries a read-only assessment (`artifacts`) and a single
   `init_existing` question. Present it via `AskUserQuestion`, then act on the
   selected option's `command_mapping` value:
   - `init execute --mode <fresh|enable|adopt|reinit>` → run
     `python3 ${CLAUDE_PLUGIN_ROOT}/bin/semver-cli <value> --plugin-root ${CLAUDE_PLUGIN_ROOT}`.
     For `--mode reinit`, if the value has no `--version` (i.e. `reinit_needs_version`
     is true), first ask the user for the target version and append `--version <vX.Y.Z>`.
   - `validate` or `repair` → run `bash ${CLAUDE_PLUGIN_ROOT}/bin/semver-router.sh <value>`.
   - If the user picks the `cancel_option` → stop.
   Then show the resulting `display` field.

## Tracking Stop Flow

1. Router calls `tracking stop-gather` → returns questions
2. Process questions: `archive_items` (multi-select) and `tag_deletion` (conditional on tags selected)
3. Execute: `python3 ${CLAUDE_PLUGIN_ROOT}/bin/semver-cli tracking stop-execute --archive <items> --delete-tags <local|both|none>`
4. Show `display`.

## Repair Flow

1. Router calls `repair diagnose` → returns repairs with embedded questions
2. If `all_pass`: show display and stop.
3. For each item in `repairs_needed`: present its `question` via AskUserQuestion.
   - If user picks an option with a `command_mapping` entry: run `python3 ${CLAUDE_PLUGIN_ROOT}/bin/semver-cli <command>`
   - If user picks Skip (null mapping): skip it.
4. After all repairs: run `bash ${CLAUDE_PLUGIN_ROOT}/bin/semver-router.sh validate` and show the display.

## Auto-Bump Start

If the router returns `needs_input: true` with questions, ask the question, then re-run with the collected flag (e.g., `--confirm true`).

## Simple Commands

`current`, `validate`, `recommend`, `auto-bump stop`, `tracking start [options]` are
**pure passthrough**: route once, check `ok`, show the `display` field, and stop. They
never return a `questions` array or prompt hooks — do **not** enter the Question Loop or
perform any extra analysis (e.g. reading the git log) for these.
