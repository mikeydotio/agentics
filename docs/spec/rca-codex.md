# AGE-93: Add Codex support without regressing Claude RCA

## Summary

Ship one RCA plugin with separate Claude and Codex instruction trees, shared deterministic scripts, and unchanged investigation artifacts.

RCA currently has no hooks. The gaps are Claude-only resource paths, question tools, agent dispatch, frontmatter, and continuation instructions.

Reviewed every current obviation candidate: AGE-45, AGE-50, AGE-81, AGE-92, AGE-95, AGE-96, AGE-101, AGE-102, and AGE-103. None implements or obviates this port. Preserve `.claude/dispatch-sentinel.json`, the existing untracked dispatch artifact.

## Implementation sequence

1. **First implementation action:** run `story comment AGE-93 <your-exact-approved-plan>`, passing this complete approved plan verbatim as one safely quoted argument. Confirm success before changing files or running tests.
2. Repeat `story help obviation-review`, `story show AGE-93 --json`, and `story load-context --story AGE-93`; review every candidate and record the findings. Repeat upon any later resumption.
3. Record the architecture decisions below on AGE-93 using **Context / Question / Decision / Rationale**. Save the implementation specification in `docs/spec/rca-codex.md`.
4. Add failing compatibility tests, implement the port, and run only new and directly impacted checks.
5. Commit focused changes with AGE-93 references. Record validation and any remaining limitations on the story.
6. When all approved work is committed and ready, run `story move AGE-93 verifying` from this worktree as the absolute last action, then stop.

## Changes and interfaces

### Host isolation and packaging

- Preserve all eight existing skill implementations byte-for-byte under `claude/skills/`. Replace their public entrypoints with the repository’s established host dispatcher pattern.
- Add eight Codex implementations under `codex/skills/`. Preserve public skill names and all existing command arguments.
- Resolve the plugin root from the loaded skill’s absolute location. Quote executable paths; require neither `CLAUDE_PLUGIN_ROOT` nor shell environment persistence.
- Select the host from authoritative runtime identity and available native tools. Reject unresolved ambiguity; never combine instruction trees.
- Add `.codex-plugin/plugin.json` with version `3.9.1`, RCA metadata, and the public skills directory. Preserve Claude registration. Add no hooks.
- Keep shared scripts, JSON contracts, `.rca/<slug>/` artifacts, branch names, and `.claude/worktrees/rca/` storage unchanged. The historical directory name does not require migration.

### Codex workflow

- Preserve the full pipeline: intake, reproduction gate, FULL/LIGHT routing, forensics, competing hypotheses, independent challenge, remediation, caller authorization, separate fix/refactor commits, and postmortem.
- Add Codex variants of references containing host-specific instructions; retain shared methodological references and agent overrides wherever they already work unchanged. Audit every transitive resource link.
- Replace Claude question calls with the available native question tool, one question at a time. Use a direct question only when no structured tool is available. Honor authorization already supplied by the caller; absent answers do not authorize a repro override, implementation, or deletion.
- Use native Codex skill invocation and fresh-session continuation wording. Offer durable Codex lessons for `AGENTS.md`; preserve Claude’s existing `CLAUDE.md` behavior.
- Preserve plan-mode read-only degradation and all existing handoff and cleanup choices.

### Codex agents

- Introduce an RCA-local agent resolver supporting explicit `AGENTS_PLUGIN_ROOT`, checkout siblings, and enabled Codex installations. Match installed identity/version rather than choosing an arbitrary cached version. Invalid explicit paths and malformed registry responses fail with context.
- Resolve canonical roles through the Agents plugin’s existing resolver. Assemble each prompt as canonical role, RCA override, Codex execution contract, and task evidence.
- Use native spawning, follow-up, result collection, and interruption tools. Inherit the session’s model and effort; do not translate Claude model names into guesses.
- Preserve the documented override-only fallback when Agents is genuinely unavailable, and record that degradation.
- Require read-only specialists to return reports. Assign each writer an explicit allowed path set; experiments remain confined to the disposable worktree. Compare against pre-dispatch changes without reverting unrelated work.
- Describe these restrictions honestly as prompt restrictions plus verification, not platform-enforced Claude permissions. Missing spawning capability produces a durable incomplete handoff rather than fabricated independent review.

This follows the repository’s Council precedent and current official guidance on [skill packaging](https://learn.chatgpt.com/docs/build-skills) and [subagent permissions](https://learn.chatgpt.com/docs/agent-configuration/subagents).

## Tests and acceptance

- **Claude preservation:** pin original skill contents and verify every public dispatcher reaches its preserved implementation.
- **Codex contracts:** cover all eight entrypoints, supported frontmatter, transitive resource resolution, quoted paths with spaces, unset/contradictory environment aliases, and absence of Claude-only calls in active Codex instructions.
- **Dependencies:** test checkout, explicit override, enabled local/cache installation, missing dependency, disabled installation, multiple versions, malformed registry output, and missing role.
- **Behavior:** run production RCA scripts in isolated fixture repositories for both host environments. Exercise reproduction, worktree creation/bisect/cleanup, FULL/LIGHT state transitions, fix versus handoff, and resumption of the same artifacts across hosts.
- **Packaging:** install RCA and Agents through a disposable local Codex marketplace under `/private/tmp`; verify installed manifests, all skill/resource paths, role resolution, and execution of installed scripts. Missing prerequisites must fail with diagnostics.
- Extend the existing documentation-to-CLI contract test to both host trees. Wire new checks into `test-rca`; run that focused target plus affected manifest checks, shell syntax/lint, and diff checks. Do not treat static instruction checks as proof of live model compliance.

No push, PR creation, full repository suite, release operation, or completion transition belongs to this implementation. The centralized verifier owns submission and final verification. Any hard stop must be documented with diagnostics, followed by blocking AGE-93 and leaving this worktree intact.

## Implementation notes

Public dispatchers retain each original Claude frontmatter block, including argument hints,
model, and effort. Claude reads these settings at registration; preserving only a nested
implementation would lose invocation behavior. Codex implementations carry portable
name/description metadata and inherit runtime settings. Tests pin both the original
Claude implementation bytes and public frontmatter equality. Codex's real local installer
accepts the shared entrypoints.

The resolver exits 0 with a normalized root, 1 only for an unavailable dependency, and 2
for configuration/registry errors. Explicit overrides are authoritative; checkout siblings
precede registry lookup. Registry resolution requires one enabled Agents identity, its exact
marketplace and version, and matching manifest metadata. Cache resolution precedes local
source fallback; neither path scans arbitrary versions.
