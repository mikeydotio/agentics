---
name: semver
description: Use when the user wants to manage semantic versioning for their project. Handles version tracking (start/stop), version bumping (major/minor/patch) with changelog generation, reading current version, auto-bump configuration, and sync integrity validation/repair. Commands are /semver current, /semver bump, /semver tracking, /semver auto-bump, /semver validate, and /semver repair.
argument-hint: <current | bump <major|minor|patch> [--force] | tracking <start [options]|stop> | auto-bump <start|stop> | validate | repair>
model: haiku
---

# Semantic Versioning Orchestrator

You manage semantic versioning by delegating deterministic work to the CLI and handling user interaction via structured questions returned by the CLI.

**Router:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/semver-router.sh <ARGUMENTS>`

## Hard Rules

1. **Route all commands through the router** — never call semver-cli directly.
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

The bump command uses a gather→questions→execute pattern:

1. Router calls `bump gather <type>` → returns state + questions
2. If `no_commits` is true (and not `--force`): show message and stop
3. Process the `questions` array (dirty_tree, wrong_branch, validation_failed, tag_conflict)
4. **Pre-bump PROMPT_HOOK**: If `has_pre_bump_prompt_hook` is true, read the file at `pre_bump_prompt_hook_path` and follow its instructions. Context: bump type, old_version, new_version. **Do NOT trigger `/semver bump`**.
5. Execute: `python3 ${CLAUDE_PLUGIN_ROOT}/bin/semver-cli bump execute <TYPE> --source <manual|force> [collected flags] --plugin-root ${CLAUDE_PLUGIN_ROOT}`
   - Use `--source force` if `--force` was used, otherwise `--source manual`.
6. **Post-bump PROMPT_HOOK**: If execute result's `post_hooks.prompt_hook` is not null, follow those instructions. **Do NOT trigger `/semver bump`**.
7. Report any `post_hooks.warnings`, then show the `display` field.

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

`current`, `validate`, `auto-bump stop`, `tracking start [options]`: just route, check ok, show display.
