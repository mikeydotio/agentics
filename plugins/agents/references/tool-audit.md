# Tool Design Audit

Audit of all tools across the agentics plugin ecosystem against five tool design principles from the Agentailor article. Covers storyhook MCP tools, freshen, sentry, semver, and pilot.

---

## 1. Storyhook MCP Tools

Storyhook exposes 18 MCP tools (`mcp__storyhook__storyhook_*`) and a CLI (`story`) with ~40 commands. The pilot plugin uses the CLI exclusively via `references/storyhook-contract.md`.

### 1.1 Strategic Consolidation

| Finding | Priority |
|---------|----------|
| **CLI creates stories one-at-a-time but MCP has `bulk_create` and `decompose_spec`** — the storyhook-contract.md says `storyhook_bulk_create` does not exist and instructs sequential `story new` calls. This is wrong: the MCP tool exists. The decompose skill creates stories in a loop with individual `story new` + `story HP-X priority` + `story HP-X precedes HP-Y` calls. A 20-story plan generates 60+ sequential tool calls. | **HIGH** |
| **State setup + story creation + dependency wiring = 3 separate operations per story** — `create_story` does not accept relationships or comments. Adding priority, labels, parent relationship, and wave dependencies each require separate `update_story`/`add_relationship` calls. `bulk_create` accepts relationships and priority in one shot. | **HIGH** |
| **`commit_sync` is a good consolidation example** — scans commits and links them to stories in one call. No fragmentation issue here. | -- |

**Recommendations:**
1. Update `storyhook-contract.md` to document `decompose_spec` and `bulk_create` MCP tools. The decompose skill should use `storyhook_decompose_spec` to create all stories from the PLAN.md markdown in a single call with `--dry-run` preview, then confirm.
2. Use `bulk_create` for wave-based story creation where `decompose_spec` markdown format does not fit. This eliminates the sequential create-then-update-then-relate pattern.
3. At minimum, use `create_story` with the `priority`, `labels`, and `state` parameters it already accepts, rather than separate update calls.

### 1.2 Clear Namespacing

| Finding | Priority |
|---------|----------|
| **Dual interface confusion** — storyhook has both a CLI (`story`) and MCP tools (`mcp__storyhook__storyhook_*`). The pilot plugin uses only the CLI, ignoring the richer MCP tools. The CLAUDE.md in `.storyhook/` documents only the CLI. No document maps CLI commands to MCP equivalents. | **MEDIUM** |
| **MCP tool names are well-namespaced** — the `mcp__storyhook__storyhook_` prefix is verbose but unambiguous. The `storyhook_` prefix within the MCP namespace is redundant (`mcp__storyhook__storyhook_get_story` vs `mcp__storyhook__get_story`) but this is a storyhook project issue, not ours. | **LOW** |
| **CLI command naming is inconsistent with MCP** — CLI uses `story HP-N is <state>` (positional, implicit), MCP uses `storyhook_update_story(id, state)` (explicit params). CLI uses `story HP-N precedes HP-M`, MCP uses `storyhook_add_relationship(a, relation, b)`. This creates confusion for agents choosing between interfaces. | **MEDIUM** |

**Recommendations:**
1. Add a CLI-to-MCP mapping table in `storyhook-contract.md` so agents know which interface to prefer.
2. Decide on one canonical interface for pilot. MCP tools are preferable: they return structured JSON by default, accept typed parameters, and support batch operations. The CLI requires `--json` flags and output parsing.
3. If keeping the CLI, document which operations have no CLI equivalent (e.g., `decompose_spec`, `phase_list`).

### 1.3 Meaningful Context Returns

| Finding | Priority |
|---------|----------|
| **`create_story` returns the full created story object** including the assigned ID, state, timestamps. Agents can immediately reference the story without a follow-up `get_story`. Good. | -- |
| **`get_next` returns full story context** — title, state, priority, comments, relationships. The agent can make decisions without a second call. Good. | -- |
| **`list_stories` returns summary objects** — sufficient for routing decisions but missing comments and relationships. An agent deciding which story to work on may need follow-up `get_story` calls. | **LOW** |
| **`bulk_create` returns all created stories** with IDs and relationships. Single-call decomposition with full response. Good. | -- |
| **CLI `story next --json` is documented but actual output format is assumed** — the storyhook-contract.md shows expected JSON format but does not document what happens on errors or edge cases. | **LOW** |

**Recommendations:**
1. Consider adding a `verbose` parameter to `list_stories` that includes comments and relationships, avoiding N+1 `get_story` follow-ups during triage.
2. Document error response shapes in storyhook-contract.md (not just success paths).

### 1.4 Token Efficiency

| Finding | Priority |
|---------|----------|
| **`get_summary` is token-efficient** — returns counts by state/priority plus curated lists (ready, blocked, stale). Good for health checks without listing every story. | -- |
| **`generate_report` with HTML format produces large responses** — HTML reports are for stakeholder consumption, not agent reasoning. An agent accidentally calling this wastes context. | **LOW** |
| **`list_stories` has no pagination** — returns all matching stories. A project with 100+ stories dumps the entire backlog into context. No `limit` or `offset` parameter exists. | **MEDIUM** |
| **`decompose_spec` can produce very large responses** — creating 30+ stories returns all of them with full details. The `--dry-run` preview is similarly verbose. | **LOW** |
| **`get_graph` returns text-based DAG visualization** — can be large for complex dependency graphs. No option to limit depth or scope. | **LOW** |

**Recommendations:**
1. Add `limit` and `offset` parameters to `list_stories` (upstream storyhook issue).
2. Add a note in storyhook-contract.md warning agents to prefer `get_summary` over `list_stories` for status checks, and `get_next` over `list_stories` for task selection.
3. The `generate_report` description should explicitly state it is for human consumption, not agent reasoning — steering agents toward `get_summary` instead.

### 1.5 Description Quality

| Finding | Priority |
|---------|----------|
| **MCP tool descriptions are excellent** — they explain when to use each tool, mention alternatives (`get_next` vs `list_stories`, `create_story` vs `bulk_create` vs `decompose_spec`), and describe parameter semantics with examples. | -- |
| **`add_relationship` description clearly explains relationship types** with semantic meaning (blocks vs relates-to). Good for agent decision-making. | -- |
| **`update_story` has a critical limitation buried in the description** — "Processes one update field per call in priority order (state > priority > labels > assignee > awaiting)." This means setting both state and priority requires two calls. An agent unaware of this would silently lose the second update. | **MEDIUM** |
| **`delete_story` properly requires a reason** — forcing agents to justify destructive actions. Good pattern. | -- |
| **CLI documentation in `.storyhook/CLAUDE.md` is a good cheat sheet** but lacks error handling guidance and does not mention the MCP tools at all. | **LOW** |

**Recommendations:**
1. The `update_story` one-field-per-call limitation should be more prominent — put it in bold at the top of the description, not buried in the middle. Alternatively, fix this upstream to process multiple fields per call.
2. Add edge case documentation to storyhook-contract.md: what happens when a story is already in the target state? When a relationship already exists? When `get_next` returns nothing?

---

## 2. Freshen Plugin

Freshen is a CLI script (`freshen.sh`) with three subcommands and two hooks (Stop, SessionStart). It has no MCP tools.

### 2.1 Strategic Consolidation

| Finding | Priority |
|---------|----------|
| **Queue + Stop hook + Clear hook = well-consolidated 3-part pipeline** — the queue command registers intent, the stop hook triggers `/clear`, the clear hook executes re-invocation. Each part has a single responsibility. No fragmentation. | -- |
| **Cross-source conflict is a hard error with no resolution** — if another source has a pending signal, `queue` fails. The caller must explicitly cancel the other source first. This is two calls (cancel + queue) that could be one (`queue --force` or `queue --replace`). | **LOW** |

**Recommendations:**
1. Add a `--replace` flag to `freshen.sh queue` that cancels any existing signal before queueing. The current two-step cancel-then-queue pattern is fragile if the cancel fails or the source name is unknown.

### 2.2 Clear Namespacing

| Finding | Priority |
|---------|----------|
| **Well-scoped** — three subcommands (`queue`, `status`, `cancel`) with clear verbs. No confusion with other tools. | -- |
| **`--source` naming is used by consumers** (pilot, semver) to self-identify. Clear contract. | -- |

No issues.

### 2.3 Meaningful Context Returns

| Finding | Priority |
|---------|----------|
| **`queue` returns a human-readable confirmation** — "freshen: queued '/pilot continue' (source: pilot)". Sufficient for logging. | -- |
| **`status` returns human-readable text** — not machine-parseable. An agent checking whether a signal is pending would need to parse output strings. | **LOW** |

**Recommendations:**
1. Consider adding `--json` output to `freshen.sh status` for programmatic consumption (e.g., pilot's stop hook checking if freshen is pending).

### 2.4 Token Efficiency

No issues. Output is minimal (1-2 lines per operation).

### 2.5 Description Quality

| Finding | Priority |
|---------|----------|
| **SKILL.md is clear and focused** — explains the 3-step mechanism, documents the tmux requirement, and provides the cross-plugin usage pattern. | -- |
| **Missing: what happens when tmux is unavailable** — the skill says "fails with error" but does not document the fallback behavior for callers. Pilot's SKILL.md handles this (falls back to manual instructions) but the freshen SKILL.md should document it for all consumers. | **LOW** |

**Recommendations:**
1. Add a "Fallback behavior" section to the freshen SKILL.md documenting what callers should do when tmux is unavailable.

---

## 3. Sentry Plugin

Sentry is a PreToolUse hook (`sentry.sh`, ~1100 lines) with a management skill (`/sentry`). It has no MCP tools.

### 3.1 Strategic Consolidation

| Finding | Priority |
|---------|----------|
| **Three-tier decision pipeline is well-consolidated** — deterministic ALLOW, deterministic PASS, AI fallback. A single hook invocation handles everything. No fragmented multi-step operations. | -- |
| **The `/sentry` skill is a config management CLI** — `allow`, `block`, `test`, `status`, `mode`, `ai` are all single-concern commands that modify `config.yaml`. Well-scoped. | -- |
| **Config parsing is duplicated** — `sentry.sh` uses `grep/sed` to parse config; the skill's bash snippets also use `grep/sed`. Any config format change breaks both independently. | **LOW** |

No critical issues.

### 3.2 Clear Namespacing

| Finding | Priority |
|---------|----------|
| **Hook output is clearly prefixed** — `[sentry]` prefix on all messages to the user. Agents and users can identify the source. | -- |
| **Decision types are well-separated** — `ALLOW` (auto-approve), `PASS` with context (warn but defer), `PASS` silent (defer to normal permissions). The three outcomes are unambiguous. | -- |

No issues.

### 3.3 Meaningful Context Returns

| Finding | Priority |
|---------|----------|
| **ALLOW returns a reason string** — agents see why the command was approved (e.g., "Bash: safe readonly command(s)"). Useful for debugging but not needed for agent decision-making since the command proceeds. | -- |
| **PASS with context returns actionable warning** — e.g., "[sentry] Detected file deletion: `rm` — requesting user confirmation." The agent and user both understand the risk. Good. | -- |
| **AI fallback returns structured rationale** — when `ai_show_rationale: true`, the AI's reasoning is surfaced. Agents can understand why a command was flagged. Excellent. | -- |
| **Log decisions include timestamps and categories** — useful for post-hoc auditing but not surfaced to agents during operation. | -- |

No issues. Context returns are well-designed.

### 3.4 Token Efficiency

| Finding | Priority |
|---------|----------|
| **Short-circuit evaluation prevents unnecessary work** — unconditionally safe commands exit immediately without parsing further. The 150+ safe commands are checked first via a fast `case` statement. | -- |
| **AI fallback has a configurable timeout** — prevents hanging on slow API calls. Good. | -- |
| **AI prompt is concise and focused** — 7 bullet points of evaluation criteria, structured JSON response format. No wasted tokens. | -- |
| **Response sizes are minimal** — typically 1-2 lines of JSON. No context bloat. | -- |

No issues.

### 3.5 Description Quality

| Finding | Priority |
|---------|----------|
| **Inline code comments are thorough** — the header block explains the three-tier pipeline, features, and default behavior. Maintenance-friendly. | -- |
| **SKILL.md provides complete command reference** — every `/sentry` subcommand has usage, examples, and bash snippets. | -- |
| **Edge case: `update_story` one-field limitation analog** — the sentry hook processes file-writing redirections BEFORE command analysis, meaning `echo "hello" > file.txt` silently passes to user (correct) but the reason is "file-writing redirection detected" which is vague. The agent does not know if the write target is safe. | **LOW** |
| **Scope limitation is clearly documented** — "Sentry only evaluates Bash commands. Write and Edit tool calls are not intercepted." This prevents agents from expecting sentry to guard non-Bash tools. | -- |

**Recommendations:**
1. Consider enriching the redirection warning to include the target file path: "[sentry] File write detected: `> output.txt` — requesting user confirmation."

---

## 4. Semver Plugin

Semver has two hooks (SessionStart, PostToolUse), a management skill (`/semver`), user-extensible pre/post-bump hooks, and file lock protocol. No MCP tools.

### 4.1 Strategic Consolidation

| Finding | Priority |
|---------|----------|
| **`/semver bump` is a well-consolidated mega-operation** — re-entrancy guard, tracking check, first version check, commit count check, dirty tree handling, branch check, sync validation, version computation, pre-bump hooks, critical section (changelog + VERSION + commit + tag), post-bump hooks, report, verification. All in one command. This is correct: the bump is atomic and should not be split. | -- |
| **`/semver validate` and `/semver repair` are separate but complementary** — validate diagnoses, repair fixes. Running repair internally calls validate first. No unnecessary fragmentation. | -- |
| **Pre-bump dirty tree handling is 4 options via AskUserQuestion** — this is a multi-step interactive flow inside the bump command. Each option triggers different git operations. Well-integrated, not fragmented. | -- |
| **Auto-bump trigger chain: PostToolUse hook -> systemMessage -> agent reads message -> agent calls /semver bump** — this is a 3-hop chain where the hook cannot directly invoke `/semver bump`. The hook emits a `systemMessage` instruction asking the agent to analyze commits and run the bump. This indirection is inherent to the hook architecture but adds latency and relies on the agent following the instruction. | **MEDIUM** |

**Recommendations:**
1. Document the auto-bump trigger chain explicitly so maintainers understand why the hook cannot directly bump. Consider whether a `PROMPT_HOOK.md` approach (like pre/post-bump hooks) could make this more reliable.

### 4.2 Clear Namespacing

| Finding | Priority |
|---------|----------|
| **Skill name conflicts: `/semver` vs other version-related tools** — no actual conflict in this ecosystem. The `semver:semver` fully-qualified name is clear. | -- |
| **Hook output is prefixed** — `[semver]` on auto-bump messages and `[!DESYNC]`/`[!NO_TAG]` on session-start warnings. Scannable. | -- |
| **Config file path is unique** — `.semver/config.yaml` does not conflict with any other plugin's namespace. | -- |

No issues.

### 4.3 Meaningful Context Returns

| Finding | Priority |
|---------|----------|
| **SessionStart hook injects version + desync warning** — e.g., "agentics version: v2.1.1 [!DESYNC] VERSION says v2.1.1 but latest tag is v2.1.0 — run /semver validate". Actionable: tells the agent what is wrong and what to do. Excellent. | -- |
| **PostToolUse hook injects detailed bump instructions** — includes current version, commit count, analysis instructions, and the exact command to run. The agent has everything needed to act. | -- |
| **Post-bump report gives a complete summary** — old version, new version, commits included, tag status, changelog preview. No follow-up calls needed. | -- |
| **Validation results use structured PASS/FAIL/SKIP format** — each check has a clear status and detail. Agents can parse and act on failures. | -- |

No issues. Context returns are among the best in the ecosystem.

### 4.4 Token Efficiency

| Finding | Priority |
|---------|----------|
| **SessionStart hook output is a single line** — version string + optional warning. Minimal context cost per session. | -- |
| **PostToolUse hook emits nothing for non-push commands** — multiple early exits (not Bash, not git push, not target branch, tracking off, pilot running). Only fires when relevant. | -- |
| **SKILL.md is 680 lines** — one of the longest skill files. However, it covers 6 subcommands with full specifications. The "read references on demand" pattern keeps each individual invocation from loading all 7 reference files. | -- |
| **Auto-bump message includes full analysis instructions** — ~2-3 lines of guidance embedded in the systemMessage. This is intentional (the agent needs to know what to do) but adds to context on every push. | **LOW** |

**Recommendations:**
1. Consider shortening the auto-bump systemMessage for the no-confirm case. The agent does not need analysis instructions if it is just executing `/semver bump <type>` — the bump command itself does the analysis.

### 4.5 Description Quality

| Finding | Priority |
|---------|----------|
| **SKILL.md serves as both documentation and executable specification** — each command has pre-checks, error messages, exact bash commands, and user interaction flows. An agent can follow it mechanically. | -- |
| **Edge cases are well-documented** — re-entrancy guard, dirty tree, wrong branch, sync issues, tag conflicts, lock failures. Each has explicit handling. | -- |
| **Reference files separate concerns** — config schema, changelog format, file locking, and sync validation are each in their own file. The skill loads them on demand. | -- |
| **`argument-hint` in frontmatter is excellent** — `<current | bump <major|minor|patch> [--force] | tracking <start [options]|stop> | auto-bump <start|stop> | validate | repair>` gives the agent the full command grammar without reading the skill. | -- |

No issues. Semver has the most mature description quality in the ecosystem.

---

## 5. Pilot Plugin

Pilot is an 11-skill orchestrator with 15 agents, session hooks, freshen integration, and storyhook integration. It is the most complex plugin.

### 5.1 Strategic Consolidation

| Finding | Priority |
|---------|----------|
| **Decompose skill creates stories sequentially when `decompose_spec` or `bulk_create` would do it in one call** — this is the same storyhook issue noted in section 1.1, but from the consumer side. The decompose skill parses PLAN.md waves, creates stories one at a time, sets priorities individually, and adds relationships individually. A 20-task plan with 4 waves generates ~80 CLI calls. Using `decompose_spec` with the PLAN.md markdown directly would be 1 call. | **HIGH** |
| **Execution loop is well-consolidated** — pick story, generate, check, evaluate, commit, update story state. Each is a distinct concern that cannot be merged. | -- |
| **Step exit protocol is 5 operations but properly atomic** — write artifacts, write handoff, commit, queue freshen, STOP. Cannot be reduced further without losing resumability. | -- |
| **Review + Validate run in parallel** — good consolidation. These are independent evaluations that the orchestrator dispatches simultaneously rather than sequentially. | -- |
| **Storyhook health check + runaway safeguard are checked every iteration** — these could be consolidated into a single "pre-iteration guard" that checks both conditions. Currently they are two separate code blocks. | **LOW** |
| **`/pilot status` requires reading multiple files and querying storyhook** — artifact scan, config.json, state.json, handoffs, and storyhook stories. This is 5+ reads for a status display. A single `state.json` with embedded summary would reduce this, but would risk stale data. Current design is correct for accuracy. | -- |

**Recommendations:**
1. Switch decompose skill from sequential CLI calls to `storyhook_decompose_spec` MCP tool or `story decompose --stdin` CLI command. The PLAN.md markdown with `### Wave N` headings and `- [ ]` checkboxes is already the format `decompose_spec` expects. This eliminates 80+ calls and replaces them with 1.
2. If the PLAN.md format does not match `decompose_spec` expectations exactly, use `storyhook_bulk_create` with pre-constructed relationship arrays. Still 1 call instead of 80+.

### 5.2 Clear Namespacing

| Finding | Priority |
|---------|----------|
| **11 sub-skills share the `pilot` namespace** — `/pilot interrogate`, `/pilot research`, etc. Clear and scannable. | -- |
| **Agent files are in the shared `agents` plugin** — `generator.md`, `evaluator.md`, etc. No namespace collision. | -- |
| **Artifact namespace (`.pilot/`) is well-documented** — the full directory tree is listed in the SKILL.md. No collision with other plugins. | -- |
| **Storyhook-contract.md uses `story` CLI prefix** — distinct from `storyhook_*` MCP tools. But this creates the dual-interface issue noted in section 1.2. | **MEDIUM** |

**Recommendations:**
1. Pick one interface for storyhook interactions in pilot. MCP tools are preferable for batch operations (decompose) and structured returns. CLI is acceptable for simple state changes. Do not mix both.

### 5.3 Meaningful Context Returns

| Finding | Priority |
|---------|----------|
| **Handoff files are rich context documents** — patterns established, micro-decisions, code landmarks, test state. The next session can fully reconstruct working context from the handoff alone. Excellent. | -- |
| **SessionStart hook injects runtime state** — sessions completed, stories attempted, retries, plus the full last handoff. An agent resuming knows exactly where it left off. | -- |
| **Stop hook writes a degraded handoff** — explicitly marked as "Incomplete Handoff" with a warning. The agent knows to be cautious about the context quality. Good design. | -- |
| **Evaluator feedback is stored as structured JSON in storyhook comments** — `{verdict, failures: [{criterion, evidence, suggestion}]}`. The generator can parse failures and address them specifically on retry. Excellent. | -- |
| **State detection returns an enum** — the artifact scan produces a single state value (`interrogate`, `research`, `design`, etc.) that maps directly to a skill dispatch. No ambiguity. | -- |

No issues. Pilot's context returns are well-designed.

### 5.4 Token Efficiency

| Finding | Priority |
|---------|----------|
| **SKILL.md is 358 lines but delegates to 7 reference files** — "load on demand, not all at once." Each skill invocation reads only its own SKILL.md plus the references it needs. Good. | -- |
| **plan-mapping.json embeds DESIGN.md sections** — the `design_section` field contains the full text of the relevant design section for each story. This avoids the generator needing to read DESIGN.md and search for the right section, but it means plan-mapping.json can be large (duplicated design content). | **LOW** |
| **Execute skill loads 9 reference files** — "load all — this is the most complex skill." This is a lot of context, but execution is the longest-running skill with the most edge cases. Acceptable. | -- |
| **Verdicts.jsonl grows unboundedly** — every evaluator verdict is appended. A 200-story project with retries could generate 1000+ entries. This file is gitignored and not read in bulk (individual lookups), so it is not a context issue but a disk issue. | **LOW** |
| **Storyhook queries in every iteration of the execution loop** — `story next --json` is called each iteration. The response is a single story object (small). Acceptable. | -- |

**Recommendations:**
1. Consider adding a size limit or rotation to `verdicts.jsonl` (e.g., keep last 100 entries).
2. Document in plan-mapping.json that `design_section` embeddings are intentional and explain the tradeoff (larger mapping file vs. fewer reads during execution).

### 5.5 Description Quality

| Finding | Priority |
|---------|----------|
| **Pilot SKILL.md is a state machine specification** — artifact scan table, state detection pseudocode, command router, exit protocol. An agent can mechanically follow it. | -- |
| **Hard Rules section is concise and numbered** — 10 rules, each one sentence. Easy to reference ("violates rule 3"). | -- |
| **Agent roster table maps agents to skills** — an agent knows which specialists are available at each step. | -- |
| **storyhook-contract.md documents commands that DO NOT exist** — prevents agents from trying `story decompose` (which actually does exist now) or `storyhook_bulk_create` (which also exists). This section is stale. | **HIGH** |
| **Settings section documents config.json defaults** — an agent can create the file from the SKILL.md alone. | -- |

**Recommendations:**
1. Update `storyhook-contract.md` "Commands That DO NOT Exist" section — `story decompose` now exists in the CLI and `storyhook_bulk_create`/`storyhook_decompose_spec` exist as MCP tools. This section actively misleads agents.
2. Add `story decompose`, `story phase list`, `story phase show`, `story set`, and `story relate` to the command table — these are useful CLI commands that exist but are not documented in the contract.

---

## Cross-Cutting Findings

### Storyhook Interface Fragmentation (HIGH)

The most significant cross-cutting issue: storyhook has three interfaces (CLI, MCP tools, direct file access) and no single source of truth for which to use. The pilot plugin uses only the CLI and explicitly tells agents the MCP tools do not exist. Meanwhile, the MCP tools offer batch operations that would eliminate the biggest performance bottleneck (story creation in decompose).

**Recommendation:** Create a unified storyhook interface guide that:
1. Maps every operation to the best interface (CLI for simple state changes, MCP for batch operations and queries)
2. Documents `decompose_spec` as the preferred way to create stories from markdown specs
3. Removes the "Commands That DO NOT Exist" section that contradicts reality

### Hook Output Standards (LOW)

Hooks across plugins use different output patterns:
- Sentry: `[sentry]` prefix in `additionalContext`
- Semver: plain text in `additionalContext` or `systemMessage` with `[!DESYNC]` markers
- Pilot: plain text in `additionalContext`
- Freshen: no hook output (hooks manage side effects silently)

This works but is not standardized. Consider a convention: `[plugin-name]` prefix on all hook-emitted messages.

### Config Parsing Duplication (LOW)

Both sentry and semver parse YAML config files with `grep/sed` one-liners. This works for flat key-value configs but will break on multi-line values, comments after values, or quoted strings. Consider a shared `parse-config.sh` helper or switch to `yq` if available.

---

## Priority Summary

| Priority | Count | Key Items |
|----------|-------|-----------|
| **HIGH** | 3 | Decompose uses sequential story creation (60-80 calls) instead of batch/decompose_spec (1 call); storyhook-contract.md says MCP batch tools do not exist (they do); storyhook-contract.md says `story decompose` does not exist (it does) |
| **MEDIUM** | 4 | CLI vs MCP interface confusion; `list_stories` has no pagination; `update_story` one-field-per-call limitation poorly documented; auto-bump trigger chain indirection |
| **LOW** | 12 | Various minor documentation, output formatting, and edge case handling improvements |

The highest-impact change is switching the decompose skill from sequential CLI calls to `storyhook_decompose_spec` or `story decompose --stdin`, which would reduce ~80 tool calls to 1 and eliminate the biggest latency bottleneck in the pilot pipeline.
