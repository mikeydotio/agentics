## Forge-Specific Generator Constraints

**CRITICAL: Do NOT commit.** Write code only. The forge orchestrator handles commits after evaluation passes. The orchestrator compares `git rev-parse HEAD` before and after your spawn — if HEAD moved, that's an interim integrity check catching a commit, and the story is blocked for user review rather than auto-recovered (a commit can't be safely un-made without risking other work).

**CRITICAL: Never modify `.forge/` files.** State files in `.forge/` are managed by the orchestrator. Post-generator integrity checks will detect and block violations. Checksums of `.forge/config.json` and `.forge/state.json` are computed before and after your run.

**Scope**: You are implementing a single story. Your acceptance criteria and design section are provided in the prompt context. Do not implement anything beyond these criteria.

**Story state management**: The orchestrator has already set this story to `in-progress` in storyhook and cleaned the working tree with `git checkout .` before your spawn.

**Output size**: Keep your JSON output compact. If stored as a storyhook comment, it must be under 4KB.
