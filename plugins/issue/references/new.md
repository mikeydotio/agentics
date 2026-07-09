# `/issue new` — interrogate, draft, and file a GitHub issue

This is the protocol for the `new` verb. The router loads it **only** when the
user runs `/issue new …`, so the baseline skill stays small. The filing itself is
deterministic (`bin/issue.sh create`); your job is the judgment: understand the
need, draft a clear issue, and confirm before filing.

## Inputs

`ARGUMENTS` after `new` is the user's raw description (may be empty). Treat it as a
braindump, not a spec.

## Protocol

1. **Anchor on the braindump.** Restate in one sentence what you think the user
   wants, so a misread surfaces immediately.

2. **Cheap recon only when it sharpens the issue.** If the description names a
   file/area, a quick `Grep`/`Read` to ground the wording is fine. Do **not**
   launch agents or do deep research — this is issue *filing*, not `/forge`.

3. **Interrogate the gaps — one `AskUserQuestion` per call** (repo convention:
   exactly one question at a time). Only ask what you genuinely can't infer;
   never pad to four questions. The dimensions worth resolving:
   - **Type** — bug / feature / chore / docs (shapes the title prefix + labels).
   - **Scope** — what's in, and explicitly what's *out*.
   - **Acceptance** — how we'll know it's done (for a bug: expected vs. actual +
     repro; for a feature: the observable outcome). Don't invent criteria the
     user didn't imply — ask.
   - **Priority** — only if the user signals it matters; otherwise omit.

4. **Draft the issue.**
   - **Title:** imperative, concise (aim < 72 chars), with a natural type prefix
     when it fits (`Bug:`, `Feature:`, `Chore:`, `Docs:`).
   - **Body (markdown):** a tight structure, omitting sections that don't apply:
     ```
     ## Context
     <why this matters / where it shows up>

     ## Problem  (bug)  — or —  ## Goal  (feature/chore)
     <the crux>

     ## Proposed approach
     <optional; only if the user has a direction>

     ## Acceptance criteria
     - [ ] <observable, checkable outcomes>

     ## Out of scope
     <what this issue explicitly does not cover>
     ```

5. **Confirm before filing — one `AskUserQuestion`.** Show the drafted title and
   body, then ask: **File it** / **Edit first** / **Cancel**. On *Edit*, revise
   from their feedback and re-confirm. On *Cancel*, stop (file nothing).

6. **File it deterministically.** Write the drafted body to a temp file in the
   session scratchpad (multi-line markdown must not travel through shell quoting),
   then run:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/bin/issue.sh create --title "<title>" --body-file <path>
   ```
   Add `--label "<csv>"` only if the repo uses type labels and the user wants one.

7. **Report.** On `ok:true`, show the helper's `display` (the filed number + URL).
   On `ok:false`, show its `display` and stop — do **not** retry blindly (a repeat
   `create` would file a duplicate).

## Guard rails

- **Never file without an explicit "File it".** No confirmation → no `create`.
- **Never call `gh` yourself** — `bin/issue.sh create` owns the write.
- **One filing per invocation.** If `create` fails, surface the error; don't loop.
- Keep the title honest and the body free of invented detail — when unsure, ask
  rather than fabricate.
