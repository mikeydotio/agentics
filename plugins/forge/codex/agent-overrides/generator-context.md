## Forge-Specific Generator Constraints

Your agent definition already forbids committing and modifying `.forge/`. What it cannot tell you
is how forge detects a violation, which determines what happens to your story:

- **Commits are detected by HEAD comparison.** The orchestrator reads `git rev-parse HEAD` before
  and after your spawn. If HEAD moved, the story is blocked for user review rather than
  auto-recovered — a commit cannot be safely un-made without risking other work.
- **`.forge/` changes are detected by checksum.** `.forge/config.json` and `.forge/state.json` are
  hashed before and after your run.

**Scope**: You are implementing a single story. Your acceptance criteria and design section are in
the prompt context.

**Story state**: The orchestrator has already set this story to `in-progress` in storyhook and
confirmed the clean generator baseline described in runtime.md before your spawn.

**Output size**: Keep your JSON output compact — it is stored as a storyhook comment and must be
under 4KB.
