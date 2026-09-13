# AGE-94: Port Forge to Codex without regressing Claude

## Summary

Ship one Forge plugin with separate Claude and Codex instruction trees, shared pipeline mechanics, and host-specific lifecycle adapters. Preserve all twelve entrypoints, eleven pipeline steps, existing artifacts, configuration defaults, and Claude behavior.

The review surfaced no evidence that another story implements this port. Candidates covered AGE-45/50/81/84/92/93/95/96/100/101/102/103. Existing Forge completion, setup, and recovery repairs are already inherited. AGE-97’s SessionStart envelope and AGE-99’s reset delivery belong within AGE-94; preserve their tracking records and document the overlap.

## Implementation sequence

1. **First implementation action:** run `story comment AGE-94 <your-exact-approved-plan>`, passing this entire approved plan verbatim as one safely quoted argument. Confirm success before editing files or running tests.
2. Repeat `story show AGE-94 --json`, `story help obviation-review`, and `story load-context --story AGE-94`. Follow the procedure for every candidate; repeat whenever implementation resumes. Record findings on AGE-94.
3. Record the architecture decisions below using **Context / Question / Decision / Rationale**, then save the specification in `docs/spec/forge-codex.md`. Record subsequent decisions immediately, before dependent work.
4. Write failing regressions first. Implement packaging/instructions, SessionStart compatibility, Stop/Freshen integration, and governed exploration in focused commits, each with its directly impacted tests passing.
5. Record commits, validation results, and limitations on AGE-94. Preserve published history on any verifier return.
6. When all approved work is committed, run `story move AGE-94 verifying` from this worktree as the **absolute last action**, then stop. An unresolved hard stop instead requires a diagnostic comment followed by `story block AGE-94 <reason>`.

## Changes and interfaces

### Packaging and instructions

- Follow the established RCA/Council dispatcher pattern. Preserve original Claude skills byte-for-byte under `claude/skills/`; retain their original frontmatter at public entrypoints. Add twelve implementations under `codex/skills/`.
- Add `.codex-plugin/plugin.json` with identity `forge`, version `3.9.1`, repository metadata, and public skills path. Keep Claude registration and existing marketplace ordering.
- Select exactly one instruction tree using authoritative runtime identity, then native tool availability. Environment compatibility aliases must not select skill instructions.
- Resolve packaged resources from the loaded skill’s absolute location; quote executable paths. Add Codex variants of host-specific references and overrides, and audit every transitive resource reference.
- Preserve router branch order, standalone/orchestrated behavior, fix cycles, transition IDs, retry limits, handoffs, deployment gates, and shared `.forge/` schemas.
- Use Codex skill invocation syntax in generated continuations. Normalize recognized legacy Forge resume commands at the host boundary without rewriting arbitrary commands or migrating artifacts.

### Native Codex orchestration

- Replace Claude question and agent calls with available Codex tools. Preserve one-question-at-a-time behavior and honor previously supplied authorization and autonomous decision instructions.
- Resolve canonical Agents roles using its existing resolver. Add a Forge dependency resolver following RCA’s tested precedence: explicit override, checkout sibling, then exact enabled Codex installation identity/version. Invalid configuration fails with context; never select an arbitrary cache.
- Resolve Freshen and Hook Guard through the same dependency mechanism, validating each dependency’s required files.
- Assemble agent prompts from canonical role, Forge override, host contract, and task evidence. Inherit runtime model and effort rather than translating Claude model names.
- Preserve sequential generator/evaluator execution, generator commit prohibition, structured verdicts, integrity checks, conditional specialists, and reviewer/triager/validator write ownership.
- Collect results through native agent identities. Respect available concurrency slots and wait for every required result before synthesizing reports or queuing one transition.
- Describe read-only restrictions honestly: Codex children inherit runtime permissions; role text alone does not remove write tools. Retain production integrity checks and reject missing or failed integrity evidence before accepting a verdict. This follows [OpenAI’s subagent permission contract](https://learn.chatgpt.com/docs/agent-configuration/subagents).
- Missing required delegation capability produces an explicit incomplete handoff, never fabricated independent review.

### Hooks and Freshen

- Make manifest commands resolve a quoted `${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` path into a host dispatcher. Preserve hook events and time budgets.
- Codex adapters consume the event payload’s project directory and isolate any Claude compatibility variables to the child process. Claude retains its existing project resolution.
- SessionStart preserves inactive no-op behavior and recovery content, including malformed-state diagnostics. Codex emits `hookSpecificOutput` containing `hookEventName: "SessionStart"` and `additionalContext`; Claude retains its existing envelope. Validate against the [official schema](https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/session-start.command.output.schema.json).
- Add optional `--host claude|codex` to step-exit and research-explore helpers; default to Claude for backward compatibility. Codex instructions pass the host explicitly. Preserve existing JSON result fields.
- Preserve Stop checkpoint ordering: durable handoff, paused state, counters, and lock release precede optional narrative collection and restart suppression.
- Keep Claude reset delivery unchanged. Codex queues through Freshen’s Codex CLI and invokes Freshen’s existing Codex Stop lifecycle entrypoint with Freshen’s own plugin root.
- Handle either Forge/Freshen hook order without duplicate reset workers or premature signal consumption. Respect disabled Freshen, active journals, cross-source conflicts, cancellation, and same-source requeue.
- Codex never sends `/clear` or creates Claude reset markers. Missing Freshen or tmux leaves durable recovery information and an accurate manual continuation message.
- Keep lifecycle machinery owned by Freshen; do not duplicate its nonce/bootstrap/acknowledgement state machine.

### Governed codebase exploration

- Preserve the existing Claude/Greenlight launcher unchanged.
- Add a Forge-owned Codex launcher for the same optional research capability: disposable worktree, experimental edits confined by Codex’s workspace sandbox, captured findings, and cleanup of only its own resources.
- Use the installed Codex CLI’s configured model, explicit workspace-write sandbox, no interactive approval escalation, and no sandbox or hook-trust bypass. Do not inherit additional writable project roots.
- Preserve the existing research result envelope and off-by-default setting. Report launch, timeout, output, or cleanup failures explicitly; failed exploration must not become successful findings.
- Bound the subprocess and reap its descendants before cleanup. Keep production launcher logic testable independently of model-generated findings.

## Tests and acceptance

| Area | Required coverage |
|---|---|
| Claude preservation | Original skill bytes and public frontmatter; dispatcher routing; existing hook outputs and reset behavior |
| Codex instructions | All twelve entrypoints; valid metadata; transitive resources; no active Claude-only calls; preserved pipeline rules |
| Dependencies | Checkout, explicit override, enabled installation, multiple versions, disabled/missing dependency, malformed registry, damaged package, paths containing spaces |
| SessionStart | Running, paused, inactive, absent/corrupt state, legacy resume data, payload cwd, both host envelopes |
| Stop and Freshen | Both hook orders, duplicate calls, checkpoint-before-breaker, no tmux, disabled/missing dependency, conflict, active journal, cancellation, same-source requeue |
| Pipeline mechanics | Fresh start/resume, retry/pass/fail, integrity rejection, review/validation dispatch variants, terminal cancellation, retained completion history and verifier-owned recovery |
| Explorer | Disabled baseline, successful findings, launch failure, timeout, descendant cleanup, preserved caller changes, argument/path quoting |
| Installed package | Disposable Codex marketplace/home; exact installed entrypoints, dependencies, manifest hook commands, helper execution, and no duplicate skill registration |

- Extend Forge’s contract and agent-alignment scans to inspect both instruction trees, with negative controls proving invalid Codex references fail.
- Exercise production scripts with real Git repositories and isolated StoryHook stores. Mock external responses or transport only; do not replace Forge/Freshen behavior.
- Add an isolated lifecycle smoke that verifies accepted continuation and journal retirement, not merely terminal text or a queued signal. Never target the active user pane.
- Wire checks into Forge’s test runner. Run only new and directly impacted tests, packaging validation, shell syntax, warning/error lint, and relevant contract guards. Missing prerequisites fail with diagnostics.
- Report static instruction coverage separately from native runtime evidence; neither proves universal model compliance.

## Boundaries and defaults

- Keep version `3.9.1`; no release or installed-cache changes.
- Preserve AGE-86 reconciliation, AGE-100’s separate stale-marker repair, and AGE-104’s broader agent-liveness work.
- Document AGE-97/99 overlap on AGE-94; leave their disposition to centralized reconciliation.
- No push, PR creation/linking, full repository suite, release operation, or `done` transition. The centralized verifier owns submission, final verification, merge, completion, and cleanup.


## Implementation evidence and limits

- Resource-root instructions count three parent directories from each native skill directory; tests derive the actual installed ancestry. RCA's existing file-path wording is also correct and needs no separate repair.
- Dependency identity validation accepts Codex's demonstrated legacy Claude manifest compatibility when no native manifest exists, while retaining exact enabled name/version and required-file validation.
- Every Codex emergency queue, including an existing Forge signal, passes through Freshen's disabled/conflict checks before lifecycle dispatch.
- The installed-package smoke uses the actual Codex CLI in an isolated home and local marketplace. The lifecycle fixture runs production Forge/Freshen behavior with deterministic external terminal events; it does not establish live TUI or model compliance.
- The separate missing-option parser fix prevents a pre-existing infinite loop. A failed research rerun preserves previous evidence but cannot certify it as current successful findings.
