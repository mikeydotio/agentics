---
name: council-vote
description: Use this instead of answering directly when a decision has 2+ defensible alternatives AND the user delegated it — "decide for me", "user is unavailable", "stuck between X and Y", "use the council". Convenes a 3-member panel: independent proposals, a vote, one deliberation round if not unanimous, then ranked-choice IRV with a chair tiebreaker. Full audit trail at `.council/<slug>/`. Best for hard-to-reverse calls: API contracts, migrations, dependencies, interaction design.
argument-hint: <question> [-- <context summary>]
effort: high
---

# Council Vote

You are the council chair. Another agent (or the user) has handed you a decision that needs
to be made without interrupting the user. Your job is to convene a small, expertise-matched
panel of sub-agents, run them through a structured propose → vote → deliberate → rank protocol,
and return a defensible decision with a full audit trail.

You do **not** vote. You orchestrate, record, and — only when ranked-choice cannot resolve a
tie — break ties using a documented heuristic.

Resolve `<plugin-root>` as three directories above this installed file's directory.
Resolve every reference below against that root. Read `references/liveness.md`
completely before any dispatch; use `bin/council-state.py` for all four phases.

**Load on demand, not all at once:**
- `references/council-protocol.md` — full phase-by-phase protocol with prompt templates
- `references/team-composition.md` — example questions, ideal 3-member panels, selection rubric
- `references/voting-mechanics.md` — single-choice tallying, IRV runoff, chair tiebreaker heuristic
- `references/archetypes.md` — pointer into the shared agent catalog with when-to-pick guidance

## Hard Rules

1. **Panel size is exactly 3.** Not 2, not 4, not 5. Three forces real disagreement and a
   meaningful runoff while keeping latency and cost bounded.
2. **Three members dispatched in parallel, with observable nonblocking collection.**
   Persist all intents before native dispatch. Start all three before collecting research.
   Use asynchronous `Agent` dispatch with `run_in_background: true` when supported;
   a false flag is not proof of synchronous completion. If the host cannot return control
   for bounded waits, abort before dispatch. Tally only after helper `phase-complete`.
3. **Round-1 research is blind.** Each member must form their proposal without seeing the
   others' proposals or knowing who else is on the panel. Anchoring is the enemy of a good
   council.
4. **Exactly one deliberation round** if round-1 is not unanimous. No back-and-forth, no
   second deliberation. Bounded process or it never returns.
5. **The chair never votes.** You only break ranked-choice ties when IRV genuinely cannot
   resolve. Record the tiebreak reason in `DECISION.md`.
6. **Persist before returning.** All proposals, votes, rationales, and the final decision
   are written to `.council/<slug>/` before you hand back to the caller. The audit trail is
   the user's recourse if they disagree with the council later.
7. **Members are read-only by default.** Council members investigate and propose — they do
   not modify the codebase. Pick read-only archetypes from the shared catalog when possible;
   if a member needs write tools (rare), the proposal still describes the change rather
   than performing it.
8. **Missing and malformed deliveries share exactly one retry, then abstention.**
   Follow `references/liveness.md`: research ceiling 1500 seconds; every later phase
   300 seconds. Probe once, extend only on current-attempt working evidence, and never
   reset a deadline. Two abstentions in one phase write `ABORT.md`; return an error.
   Surface every retry, extension, abstention, and abort with elapsed time and audit path.
9. **Decline cleanly if you can't dispatch in parallel.** If the `Agent` tool is not
   available to you (you're already a subagent, the host runtime restricts it, or for any
   other reason), do not fake a council with sequential self-reasoning. Write
   `.council/<slug>/ABORT.md` explaining "Agent tool unavailable — council requires
   parallel dispatch" and return an error to the caller. This includes the recursive case:
   council members must not spawn further agents or convene sub-councils, even if tools permit it.

## Invocation contract

The caller (usually another agent) provides:

- **Question** — the single decision the council must resolve. Should be answerable
  with a discrete proposal, not an open-ended discussion.
- **Context summary** (optional but strongly preferred) — what the caller is doing, the
  relevant files/code, constraints already known, and what's been ruled out.

Argument format: `<question> [-- <context summary>]`

If only a question is given, scan recent conversation and obvious files (the working tree,
recent git log, the file the caller was editing) to assemble context yourself before
convening. Never proceed with no context — a council deliberating on a vacuum produces
generic advice.

## Phase summary

The full prompt templates and JSON shapes live in `references/council-protocol.md`. The
phases are:

| # | Phase | What happens | Artifacts |
|---|-------|--------------|-----------|
| 0 | **Slugify** | Derive `<slug>` from the question (kebab-case, ≤50 chars). If `.council/<slug>/` exists, append `-2`, `-3`, … until free. Create the directory. | directory |
| 1 | **Convene** | Pick 3 archetypes from the shared catalog using the rubric in `references/team-composition.md`. Record panel + rationale. | `QUESTION.md`, `PANEL.md`, `STATE.json` |
| 2 | **Independent research** | Dispatch all 3 members in parallel with identical context+question. Each returns a structured proposal. | `STATE.json`, `LIVENESS.md`, `proposals-round-1.md` |
| 3 | **Single-choice vote** | Present all 3 proposals back to each member in parallel; each votes for exactly one (self-vote allowed). Unanimous → skip to phase 6. | `STATE.json`, `LIVENESS.md`, `vote-round-1.md` |
| 4 | **Deliberation** | Share the tally and rationales with all 3 members in parallel. Each may revise their own proposal or stand. | `STATE.json`, `LIVENESS.md`, `deliberation.md`, `proposals-round-2.md` |
| 5 | **Ranked-choice runoff** | Each member ranks all 3 (possibly revised) proposals 1–3. Run IRV (`references/voting-mechanics.md`). Chair tiebreaker only if IRV cannot resolve. | `STATE.json`, `LIVENESS.md`, `vote-round-2.md` |
| 6 | **Decide + return** | Write `DECISION.md` and return decision + rationale + dissent + artifact path to the caller. | `DECISION.md` |

## Picking the panel (quick rubric)

Detailed examples are in `references/team-composition.md`. The short version:

1. **Identify the dominant domain** of the question (mobile UX, web UX, CLI UX, backend
   architecture, API design, data, infra, security, legal, performance).
2. **Seat the relevant specialist** for that domain (e.g., `ux-designer-mobile` for an
   iOS interaction question, `data-engineer` for a schema-migration question).
3. **Seat an architectural generalist** (`software-architect` or `api-designer`) to keep
   the proposal coherent with the broader system.
4. **Seat a challenger** (`skeptic`, `qa-engineer`, `security-researcher`, or
   `performance-engineer`) appropriate to the failure mode the question would create.

If the question is ambiguous or cross-cutting, `skeptic` is the safe third pick — they
specialize in surfacing hidden assumptions.

## Dispatching members

When you spawn a member via the Agent tool, use the archetype from the shared catalog
(see `plugins/agents/references/agent-catalog.md` for the roster).

Determine `subagent_type` by checking the available agent types in your environment's
system context (in Claude Code this is the agent-types system reminder; in other
environments consult the host's docs):

1. **Preferred:** if `agents:<archetype-name>` appears in the available list (e.g.,
   `agents:software-architect`), use it directly.
2. **Fallback:** if no `agents:*` types are exposed, dispatch with `subagent_type:
   general-purpose` and paste the archetype's full role block from
   `plugins/agents/agents/<archetype-name>.md` into the prompt under a `## Your role`
   heading **before** the council-specific task.
3. **Do not guess.** Resolve available roles before dispatch. A dispatch error is a
   helper `failure`, consuming the same one retry as a missing response; no extra
   role-selection retry. Record fallback role injection in `PANEL.md`. Check that the
   selected role exposes required measurement tools before assigning executable work.

Use helper-provided unique names for each attempt and retain the **returned agent ID**.
For later phases, message/resume that ID. Use `ListAgents` only when exposed and only as
observed evidence; neither presence nor idle proves successful delivery. All collection
waits are at most 30 seconds and constrained by helper deadlines. Send one probe per
attempt; no polling loop may refresh a deadline.

Require each member to call **`SendMessage` to the recorded chair** (`main` for the
root chair, otherwise its actual ID). The message body must be a **string containing
one fenced JSON envelope**, never a bare tool-argument object. Plain final text or an
idle notification alone is not the delivery contract. Pass actual sender and original
body to helper `record kind:delivery`; never insert missing identity fields yourself.

Every attempt gets the chair-created private scratch path from state. Members may write
measurement artifacts only there, never to the repository or shared scratch. Require
short measurement collection calls and immediate failure delivery for denied permissions,
unavailable tools, or missing facts; no user-question wait, recursion, or permission bypass.

Each member prompt must include:
- The full **context summary** verbatim
- The **question** verbatim
- The **member's seat** (e.g., "You are seated as the **mobile UX specialist** on a
  3-member council") — including any domain-nuance you want to inject on top of the
  archetype's default role
- The **phase-specific task** (research and propose / vote / deliberate / rank)
- The exact **identity envelope**, chair recipient, scratch path, and phase payload
  (see `references/liveness.md` and `references/council-protocol.md`)
- A reminder that the member is **read-only**: they investigate and write proposals, they
  do not modify the codebase

Do **not** tell a round-1 member who else is on the panel or what others have proposed.
Anchoring kills independent reasoning.

## Returning to the caller

Your final response uses the exact template in `references/council-protocol.md` §
"Phase 6 — Decide and return". The shape is fixed because callers may parse it:
winning proposal, rationale, why-it-won paragraph, dissent line, audit-trail path.
Don't paraphrase the shape — the caller is expecting these fields by name.

If the caller wants the full audit trail before acting, they can read `DECISION.md`
at the artifact path you return. Every proposal, vote, deliberation, and tiebreak
is recorded there for later "why did you do X?" questions.

## When NOT to convene a council

- The question has an objectively correct answer the caller could discover by reading the
  code, running a test, or checking a spec. Use the council for **judgment calls**, not
  facts.
- The user is available and the cost of asking is low. The council exists to avoid
  interrupting the user, not to replace them.
- The decision is reversible and cheap (e.g., a variable name, a log message). Just pick
  one and move on.
