# Codex RCA runtime contract

Read this before every step, including standalone steps. The selected Codex instruction
tree owns host mechanics; shared methodology and shell scripts own RCA semantics.

## Paths and calls

Each skill resolves `<plugin-root>` from its own loaded absolute file location. Substitute
that absolute path into every command and quote it. Never depend on the target project's
cwd to locate packaged resources or on a variable surviving between tool calls. Shell
scripts run from the investigation's target project unless a command explicitly names
the disposable experiment worktree. Read the selected step inline; do not delegate an
entire step to a worker. Load Codex reference variants when they exist; otherwise load
the named shared reference. Shared agent overrides are host-independent context.

Invoke the public RCA skill with `$rca`, followed by the existing arguments (for example,
`$rca continue <slug>`). Read public step dispatchers by absolute path when routing.
For a fresh session, persist state, then tell the caller to start a new session and invoke
`$rca continue <slug>`. Do not send TUI reset commands or infer a reset from screen text.

## Questions and authorization

Use `request_user_input` when available in the active mode; otherwise use
`request_user_input_async` when available, otherwise ask directly in the response.
Exactly one question per call, with meaningful alternatives and a free-text option.
Honor explicit answers and authorizations already provided by the caller. Do not repeat
an answered gate merely because it appears in a template. An autonomous caller can
choose within its delegated scope and record the decision and rationale.

Never interpret silence, elapsed time, missing tools, or an autonomous-session label as
a repro-gate override, fix authorization, or permission to delete artifacts. Record the
actual authorizing instruction or caller decision in APPROVAL.md/OVERRIDE.md. Without
needed authority, persist the current findings and an incomplete HANDOFF.md; do not claim
the gate passed. Destructive disposition defaults to keeping artifacts when unanswered.
In plan mode, run only the orchestrator's read-only static-forensics path. No scaffold,
test writes, experiments, issue comments, or artifact writes until execution is authorized.

## Specialist dispatch

Read `<plugin-root>/references/delivery.md` completely. The local delivery helper owns
pending state, finite deadlines, bounded waves, envelopes and cleanup on every dispatch.
Handle delivery_recovery before any artifact-based routing, fresh work or cleanup.
The helper is bundled locally and remains available in the override-only fallback.


Run `bash "<plugin-root>/bin/resolve-agents-root.sh"` and inspect its exit code:

- 0: read the absolute root from stdout. For each role run
  `bash "<agents-root>/bin/resolve-agent.sh" <role>` and read the returned canonical role.
- 1: Agents is genuinely unavailable. Use the RCA override-only fallback and record the
  missing canonical role and reduced enforcement in the step artifact.
- 2 or any unexpected failure: preserve diagnostics and stop dispatch. A malformed
  registry, invalid explicit override, or damaged enabled installation is not absence.

A missing role after successfully resolving Agents is a configuration error, not a reason
to silently use a different specialist. Explicit AGENTS_PLUGIN_ROOT is a user selection;
without it the resolver accepts a checkout sibling or one enabled registry identity and
its exact version. Multiple enabled installations require explicit selection.

For each task, construct the prompt in this order:

1. Full canonical role definition (when available).
2. Full RCA override from `<plugin-root>/agent-overrides/<role>-context.md`.
3. Codex execution contract below.
4. Dynamic task evidence, expected output, allowed absolute paths and the state-derived delivery envelope.

Use `spawn_agent` with a unique task name containing the investigation, step, role, and
attempt. Inherit the active model and effort; omit overrides. Role YAML tool/model fields
are descriptive registration metadata, not Codex runtime settings. Do not spawn further
agents from a specialist. Keep the returned agent identifier; use `followup_task` for
only helper-tracked correction attempts and bounded `wait_agent` slices to collect its final result. Independent
challenge must run in a separate specialist, never as the diagnosing agent's self-review.
If native spawning is unavailable, return an incomplete HANDOFF.md with the missing
capability; do not substitute a fictional specialist report.

### Execution contract included in every worker prompt

Use only available native tools and inherit the parent's sandbox and approval policy.
Do not spawn further agents. Do not ask the user questions; return missing information
or permission failures to the orchestrator. Do not stage or commit changes. Your canonical
role and RCA override define perspective; this task's explicit path allowance bounds writes.
Read-only roles return reports and write no files. Writers may change only the listed
absolute paths. Experimenters may mutate only the designated disposable worktree, never
the investigation's working tree. Return evidence, commands, results, changed paths, and
limitations. Do not report success when an operation failed or approval was unavailable.

## Verify results and writes

Before dispatch, record a pre-dispatch baseline: staged and unstaged diffs, porcelain
status, and contents/hashes of existing dirty and relevant untracked files. Include ignored
RCA artifacts in the allowed set. After each worker, compare content as well as path status
against that baseline; a previously dirty file must not hide a worker's new change. The
orchestrator writes reports returned by read-only roles. Writer allowances are:

| Role | Allowed writes |
|---|---|
| qa-engineer | Declared NEW reproduction tests and investigation artifacts |
| experimenter | Only the supplied disposable worktree |
| software-engineer | Only the approved remediation paths, after the fix gate |
| technical-writer | Only the named postmortem document |
| investigator, evidence-collector, hypothesis-challenger, software-architect | None |

These are prompt restrictions plus post-return verification, not structural tool denial.
On an unexpected write, halt the step, record the diff and diagnostics, and preserve
pre-existing work. Do not blindly revert/reset files or automatically respawn over the
violation. Use `interrupt_agent` only on still-running workers when abandoning a dispatch.
Worker failure, missing output, or a permission error is not a completed pipeline step;
persist an incomplete handoff and keep its gate unsatisfied.
