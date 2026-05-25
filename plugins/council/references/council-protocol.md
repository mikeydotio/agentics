# Council Protocol — Phase-by-Phase

Every prompt template and JSON shape the chair needs to run a full council. The chair
(orchestrator) follows these phases in order. Each phase is bounded — there is no
"maybe we'll add a third round" branch.

## Phase 0 — Slugify and scaffold

Derive `<slug>` from the question:

1. Lowercase, replace non-alphanumeric runs with `-`, strip leading/trailing `-`.
2. Truncate to ≤50 characters at a word boundary.
3. If `.council/<slug>/` already exists, append `-2`, `-3`, etc. until a free slot is
   found. Never overwrite a prior council's artifacts.

Create the directory: `mkdir -p .council/<slug>/`.

## Phase 1 — Convene

Pick exactly 3 archetypes using the rubric in `team-composition.md`. Write
`QUESTION.md` and `PANEL.md`.

### `.council/<slug>/QUESTION.md`

```markdown
# Council Question

**Convened:** <ISO 8601 timestamp>
**Caller:** <calling skill or agent, if known; otherwise "user direct">

## Question

<question verbatim>

## Context

<context summary verbatim, or "Assembled by chair from working tree" plus the
chair's assembled summary if the caller did not provide one>
```

### `.council/<slug>/PANEL.md`

```markdown
# Council Panel

| Seat | Archetype | Why this seat |
|------|-----------|---------------|
| 1 | <archetype-name> | <one sentence> |
| 2 | <archetype-name> | <one sentence> |
| 3 | <archetype-name> | <one sentence> |

## Dispatch notes

<any domain-nuance the chair will inject on top of the archetype's default role,
e.g., "Member 1 (ux-designer-mobile) will be asked to focus on iOS 17+ HIG
guidance for primary CTAs.">
```

## Phase 2 — Independent research (parallel)

Dispatch all 3 members in a **single message** with 3 Agent tool calls. Each member
receives the same context and question, sees no information about the other members, and
returns a structured proposal.

### Member prompt template (round-1 research)

```
You are seated as **Seat <N> — <archetype display name>** on a 3-member council
convened to answer a single question. You are working independently. Do not
speculate about who else is on the panel; assume your seat covers your domain.

## Question

<question verbatim>

## Context

<context summary verbatim>

## Your task

Investigate this question from your domain's perspective. You are read-only —
investigate the codebase, read relevant docs, consult your domain expertise, but
do not modify any files.

When you have an answer, respond with a single JSON object. All fields are
required and must be non-empty. Do not wrap in markdown code fences. Do not add
any prose before or after the JSON.

Field specifications:
- summary: one sentence — the decision you propose.
- rationale: 2-5 sentences as a single string (no internal newlines) — why this
  is the right answer from your perspective.
- risks: one sentence — the biggest risk if we follow your proposal.
- confidence: exactly one of "low", "medium", or "high".

Example of a well-formed response:

{
  "summary": "Use a sheet for the onboarding CTA.",
  "rationale": "Sheets preserve the user's mental model of returning to the prior screen, follow iOS 17 HIG for non-destructive primary actions, and keep the onboarding context visible underneath. A full-screen push implies a deeper navigation commitment than this flow warrants.",
  "risks": "Sheets can be dismissed accidentally with a downward swipe; if completing the CTA is critical-path, this is a regression vector.",
  "confidence": "high"
}
```

After all 3 return, parse each JSON object and write
`.council/<slug>/proposals-round-1.md` as a human-readable markdown rendering:

```markdown
# Round 1 Proposals

## Proposal A — Seat 1 (<archetype>)

**Summary:** <summary>

**Rationale:** <rationale>

**Risks:** <risks>

**Confidence:** <confidence>

## Proposal B — Seat 2 (<archetype>)

<same shape>

## Proposal C — Seat 3 (<archetype>)

<same shape>
```

Label proposals A/B/C (not by seat number) so subsequent voting prompts can
present them in a stable, anonymized order. The JSON itself is for the agent's
benefit; the artifact is for human review.

## Phase 3 — Single-choice vote (parallel)

Dispatch all 3 members again, in parallel. Each receives all 3 proposals
(now labeled A/B/C) and casts one vote.

### Member prompt template (round-1 vote)

```
You are Seat <N> — <archetype>. The council has produced 3 proposals in response
to this question:

<question verbatim>

## Proposal A

**Summary:** <A summary>
**Rationale:** <A rationale>
**Risks:** <A risks>
**Confidence:** <A confidence>

## Proposal B

<same shape>

## Proposal C

<same shape>

## Your task

Cast a single vote for the proposal you believe best answers the question. You
may vote for your own proposal.

Respond with a single JSON object. All fields are required and must be
non-empty. Do not wrap in markdown code fences. Do not add any prose before or
after the JSON.

Field specifications:
- choice: exactly one of "A", "B", or "C".
- reason: one sentence explaining why this proposal is your top choice.

Example of a well-formed response:

{
  "choice": "B",
  "reason": "Proposal B's expand/contract migration sequence is the only one that keeps the table writable during the transition."
}
```

Tally and write `.council/<slug>/vote-round-1.md`:

```markdown
# Round 1 Vote (single-choice)

| Seat | Archetype | Voted | Reason |
|------|-----------|-------|--------|
| 1 | <archetype> | <A/B/C> | <reason> |
| 2 | <archetype> | <A/B/C> | <reason> |
| 3 | <archetype> | <A/B/C> | <reason> |

**Tally:** A=<n>, B=<n>, C=<n>

**Result:** <unanimous for X | split N-N-N>
```

**If unanimous** (all three voted the same proposal): skip phases 4 and 5, go
directly to phase 6 and record `DECISION.md` with `vote_method: unanimous`.

**Otherwise:** proceed to phase 4.

## Phase 4 — Deliberation (one round, parallel)

Share the round-1 tally and rationales with all 3 members. Each may revise
their proposal in light of what they've learned, or stand.

### Member prompt template (deliberation)

```
You are Seat <N> — <archetype>. The first vote produced a split:

<paste the tally and reason column from vote-round-1.md>

Here are the original proposals again:

## Proposal A

**Summary:** <A summary>
**Rationale:** <A rationale>
**Risks:** <A risks>
**Confidence:** <A confidence>

## Proposal B

<same shape>

## Proposal C

<same shape>

## Your task

You may revise your own proposal based on what you've learned from the other
members' reasoning, or stand by it unchanged. You may NOT revise another
member's proposal. Be specific about what you changed and why.

Respond with a single JSON object. All fields are required. Do not wrap in
markdown code fences. Do not add any prose before or after the JSON.

Field specifications:
- seat: integer matching your seat number.
- action: exactly "revise" or "stand".
- revised_proposal: an object with the same shape as a round-1 proposal
  (summary, rationale, risks, confidence). If revising, this is the new
  proposal. If standing, repeat your round-1 proposal verbatim.
- delta: one sentence on what changed if revising, or "no change" if standing.

Example of a well-formed response (revising):

{
  "seat": 2,
  "action": "revise",
  "revised_proposal": {
    "summary": "Use a sheet, but disable swipe-to-dismiss until the primary action is tapped.",
    "rationale": "Seat 1's concern about accidental dismissal is real, but moving to a full-screen push abandons too much HIG alignment. Disabling swipe-to-dismiss on the sheet preserves the mental model while closing the regression vector.",
    "risks": "Disabling swipe-to-dismiss is a known accessibility complaint for users who rely on it as an escape hatch; pair with a visible Cancel control.",
    "confidence": "high"
  },
  "delta": "Added swipe-to-dismiss lock to address Seat 1's dismissal concern, with an accessibility mitigation."
}

Example of a well-formed response (standing):

{
  "seat": 1,
  "action": "stand",
  "revised_proposal": {
    "summary": "Use a full-screen push for the onboarding CTA.",
    "rationale": "The dismissal risk is the dominant concern; sheets can be lost. A full-screen push makes the CTA unmissable.",
    "risks": "Heavier nav commitment than the flow strictly warrants.",
    "confidence": "medium"
  },
  "delta": "no change"
}
```

Write `.council/<slug>/deliberation.md` (the raw revision payloads) and
`.council/<slug>/proposals-round-2.md` (the proposal slate going into the
runoff, re-labeled A/B/C in the same order as round-1 so members can map
their familiarity).

## Phase 5 — Ranked-choice runoff (parallel)

Dispatch all 3 members again, in parallel. Each ranks all 3 round-2 proposals 1–3.

### Member prompt template (ranked-choice)

```
You are Seat <N> — <archetype>. After deliberation, the proposal slate is:

## Proposal A

**Summary:** <round-2 A summary>
**Rationale:** <round-2 A rationale>
**Risks:** <round-2 A risks>
**Confidence:** <round-2 A confidence>

## Proposal B

<same shape>

## Proposal C

<same shape>

## Your task

Rank all three proposals from best (1) to worst (3). You may rank your own
proposal. No ties allowed in your ranking — every proposal must appear in
exactly one position.

Respond with a single JSON object. All fields are required. Do not wrap in
markdown code fences. Do not add any prose before or after the JSON.

Field specifications:
- first, second, third: each is exactly one of "A", "B", or "C". The three
  values together must cover all of {A, B, C} with no repeats.
- reason: one sentence summarizing why your top choice is best.

Example of a well-formed response:

{
  "first": "B",
  "second": "A",
  "third": "C",
  "reason": "Proposal B's revised expand/contract sequence keeps the table writable and addresses the rollback gap that Proposal A leaves open."
}
```

Tally with IRV (see `voting-mechanics.md`). Write `.council/<slug>/vote-round-2.md`:

```markdown
# Round 2 Vote (ranked-choice IRV)

| Seat | Archetype | 1st | 2nd | 3rd | Reason |
|------|-----------|-----|-----|-----|--------|
| 1 | ... | A | B | C | ... |
| 2 | ... | B | A | C | ... |
| 3 | ... | C | A | B | ... |

## IRV tabulation

Round 1: A=1, B=1, C=1 — no majority, lowest eliminated: <X>
Round 2 (after eliminating <X>): <tally>

**Winner:** <proposal letter>
**Method:** <IRV majority | chair tiebreaker>
**Tiebreak reason (if chair):** <heuristic invoked>
```

## Phase 6 — Decide and return

Write `.council/<slug>/DECISION.md`:

```markdown
# Council Decision

**Question:** <question>
**Decided:** <ISO 8601 timestamp>
**Method:** <unanimous-round-1 | ranked-choice-majority | chair-tiebreaker>

## Winning proposal

<full proposal text — summary + rationale + risks + confidence>

## Why this won

<one paragraph: who voted for it, in which round, what dissent existed, whether
deliberation moved any members>

## Dissent

<if any member ranked the winner last or opposed throughout, summarize their
concern in one sentence. If unanimous, write "None — unanimous decision.">

## Audit trail

- [QUESTION.md](QUESTION.md)
- [PANEL.md](PANEL.md)
- [proposals-round-1.md](proposals-round-1.md)
- [vote-round-1.md](vote-round-1.md)
- [deliberation.md](deliberation.md) <!-- only if non-unanimous -->
- [proposals-round-2.md](proposals-round-2.md) <!-- only if non-unanimous -->
- [vote-round-2.md](vote-round-2.md) <!-- only if non-unanimous -->
```

Return to the caller in this exact shape (plain text, not JSON — the caller is
a Claude agent, not a program):

```
## Council Decision

**Proposal:** <full winning proposal summary line>

<2-5 sentence rationale from the winning proposal>

**Why this won:** <one paragraph from DECISION.md "Why this won" section>

**Dissent:** <one sentence, or "None — unanimous">

**Audit trail:** `.council/<slug>/DECISION.md`
```

The caller is then responsible for acting on the decision. The council is done.

## Member response failures

Asking for JSON with a worked sample drives malformation rates close to zero, but
not to zero. When a member's response can't be parsed cleanly, the chair follows
this bounded protocol so the council always terminates.

### 1. Parse leniently first

- Strip leading/trailing whitespace.
- If the response is wrapped in ```` ```json ```` or ```` ``` ```` fences, strip
  them. Models sometimes add fences even when told not to.
- Try `json.loads` (or the host language equivalent).
- If it parses and all required fields for that phase are present and non-empty
  (and any enum fields contain a valid value), accept it.

### 2. Retry once on failure

If parsing fails, required fields are missing/empty, enums are invalid, or the
ranking response contains duplicates, re-dispatch that single seat with this
preamble prepended to the original phase prompt:

> Your previous response was malformed: <one sentence on the specific problem,
> e.g., "missing 'rationale' field", "not valid JSON — extra prose after the
> closing brace", or "'first', 'second', 'third' did not cover all of A/B/C">.
> Please respond again, in the exact JSON format below, with all fields
> populated. Do not include any prose outside the JSON object and do not wrap
> in code fences.

Then re-send the rest of the original phase prompt. Only that seat is
re-dispatched, not the whole panel.

### 3. Abstain on second failure

If the retry also fails, mark the seat as **abstaining** for this phase. Append
to `PANEL.md` under an "Abstentions" heading:

```markdown
## Abstentions

- Seat <N> (<archetype>) abstained from <phase name>: <one sentence on why,
  e.g., "two consecutive malformed responses; chair could not parse JSON".>
```

Then proceed with the remaining members.

### How abstentions affect tallies

- **Proposal abstention (phase 2):** the council proceeds with the 2 proposals
  that did arrive. They are still labeled in arrival order (the surviving seats'
  proposals become A and B; there is no C). All subsequent voting and ranking is
  over those 2 proposals.
- **Vote abstention (phase 3):** tally over 2 voters. If both voted the same
  proposal, treat as unanimous and proceed to phase 6. A 1-1 split triggers
  deliberation.
- **Deliberation abstention (phase 4):** treat the seat as "stand" with their
  round-1 proposal unchanged. The runoff still includes the seat as a voter.
- **Ranking abstention (phase 5):** tally IRV over the rankings actually
  returned. With only 2 ballots, IRV is degenerate: whoever has 2 first-place
  votes wins; a 1-1 first-place split goes directly to the chair tiebreaker
  (`voting-mechanics.md`). Record the degenerate path in `vote-round-2.md`.
- **Two or more abstentions in any single phase:** the council cannot produce
  a meaningful decision. Write `.council/<slug>/ABORT.md` with the phase that
  collapsed, the seats that abstained, and the last salvageable artifacts.
  Return an error to the caller — do not invent a decision. The caller should
  fall back to `AskUserQuestion` or whatever it would have done without a
  council.
