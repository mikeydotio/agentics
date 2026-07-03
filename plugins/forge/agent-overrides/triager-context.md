## Forge-Specific Triager Context

**Phase**: This is the `triage` step of the forge pipeline, after review and validate.

**Input files**: Read `.forge/REVIEW-REPORT.md` and `.forge/VALIDATE-REPORT.md` for findings.

**Config-driven behavior**: Read `.forge/config.json` for:
- `when_in_doubt`: "escalate" (default) or "fix" — adjusts the FIX/ESCALATE threshold
- `yolo_mode`: If true, FIX everything except decisions requiring human input

**Output location**: You have no Write/Edit tools (`read_only: true`) — return your decisions as
your response, in the Output Format `triager.md` specifies. Do NOT attempt to write
`.forge/TRIAGE.md` yourself. The orchestrator (`skills/triage/SKILL.md`) synthesizes that file by
combining your decisions with the qa-engineer's and skeptic's perspectives, then routes FIX
decisions to a generator agent and ESCALATE decisions to the user via `AskUserQuestion`.

**FIX cycle limit**: In yolo mode, a maximum of 10 fix cycles are allowed before the orchestrator pauses and asks the user.
