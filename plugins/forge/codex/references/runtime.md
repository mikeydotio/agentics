# Codex Forge runtime

Read this before every step, including standalone steps. The Codex tree owns host
mechanics; production shell helpers own pipeline state and artifact transitions.

## Resources and questions

Resolve every packaged path from the loaded skill's absolute location, never from
the target project's cwd. Substitute the absolute root for <plugin-root> and quote
it in shell commands. Shell variables do not persist across tool calls. References
and skills named by this tree are under codex; bin helpers remain shared.
The shared StoryHook command contract is authoritative. Resolve its internal
skill/reference links through this selected Codex tree.
Public invocation is `$forge:forge <command>`. Read the selected step inline.

Use request_user_input when available, otherwise request_user_input_async, otherwise
a direct question. Ask exactly one question with meaningful alternatives and free
text. Honor answers and authorizations already supplied by the caller. When the
caller delegates autonomous decisions, choose within that scope and immediately
record Context / Question / Decision / Rationale on the assigned story. Silence
does not grant additional permissions. Without required authority, retain an
incomplete handoff and name the missing authority. Never erase unrelated changes.
In Plan mode remain read-only: do not create artifacts, mutate stories, run
experiments, or execute step-exit until implementation is authorized.

## Specialist dispatch

Resolve Agents with:

```bash
bash "<plugin-root>/bin/resolve-dependency.sh" agents
```

Exit 0 returns its absolute root. Exit 1 means unavailable; exit 2 means invalid
configuration or damaged installation. Neither permits inventing a canonical role.
Resolve each role with `bash "<agents-root>/bin/resolve-agent.sh" <role>` and read
the returned definition. Missing dependency, missing role, or unavailable native
spawning produces an incomplete step handoff with diagnostics.

Construct each worker prompt in this order: full canonical role, full Forge override
from codex/agent-overrides when one exists, the execution contract below, then task
evidence and expected output. Use spawn_agent with a unique step/role/attempt name;
retain the returned identity. Inherit model and effort. Canonical YAML model/tools
metadata is descriptive, not Codex configuration. Use followup_task for corrections
to that task, wait_agent to collect final results, and interrupt_agent when aborting
still-running workers. A notification without a result is not a completed task.

Respect available concurrency slots. Run independent readers concurrently when
possible; collect all required results before synthesis. Generator and evaluator
are sequential and separate agents. For combined review/validation, dispatch the
required specialists as capacity allows, then write both reports and queue exactly
one step exit. Do not require all roles to fit in one tool call.

### Execution contract included in every worker prompt

Use available native tools with inherited permissions. Do not spawn further agents.
Do not ask the user questions; return missing information or denied operations to
the orchestrator. Do not stage or commit. Canonical role and Forge override define
perspective; explicit absolute allowed paths define write ownership. Evaluators,
reviewers and triagers return findings without writing files. Validators may write
only the assigned validation report and declared tests. Researchers write only their
assigned research files; generators only the story's approved implementation paths.
Return commands, evidence, changed paths, results and limitations. Never claim a
failed command succeeded.

## Integrity and ownership

Read-only instructions are prompt restrictions, not platform-enforced tool denial.
Capture the pre-dispatch content baseline, including existing dirty and untracked
files. Compare after workers return; known legitimate concurrent writer paths must
be accounted for explicitly. Do not restore another worker's authorized changes.

Before generator dispatch, inspect `git status --porcelain=v1 --untracked-files=all`.
Require a clean tracked/untracked baseline after committing only the orchestrator's
owned pipeline artifacts. If unrelated changes exist, preserve them and pause with
a handoff; never reset or stage them. Retain the baseline and allowed paths so retry
cleanup removes only that failed generator's changes after saving diagnostic evidence.

Always run the production pre-gen and pre-eval integrity snapshots/checks with the
same session ID. The evaluator uses full-tree scope even if its canonical role
declares read-only tools. If a snapshot or check reports `ok: false`, stop before
using the verdict: unavailable integrity evidence is not proof of no tampering.
Follow the existing tamper handling when a successful check detects changes.
Do not blindly reset pre-existing user work. Retry cleanup may discard only the
current failed generator's known changes after preserving diagnostics.

## Lifecycle

Every orchestrated step persists its artifacts and handoff, calls the shared
step-exit helper with `--host codex`, and ends the turn. Standalone steps return
without resetting. Never execute the next step inline. Freshen owns reset delivery
and acceptance; a queued signal is not an accepted continuation.

For graceful stop, pause state, write the full handoff, release the Forge lock, then
resolve Freshen with `bash "<plugin-root>/bin/resolve-dependency.sh" freshen` and run
`bash "<freshen-root>/codex/bin/freshen.sh" cancel --source forge`.
Missing Freshen leaves a diagnostic and durable manual resumption instructions.
Do not cancel another workflow's signal or write a replacement reset protocol.
