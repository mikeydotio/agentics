# Team Composition — Picking the 3 Members

The council is always exactly 3 members. Three is enough to produce real disagreement
and a meaningful runoff vote, while staying cheap and fast. Two members deadlock with
no recourse; five turn into a committee.

This doc gives you a rubric and a library of worked examples. Use the examples as
inspiration, not as a fixed lookup — your question is probably not on this list,
so apply the rubric.

## The rubric

For any question, ask:

1. **What domain does this question primarily live in?** Mobile UX? Web UX? CLI UX?
   Backend architecture? API contract? Database schema? Infrastructure? Security?
   Legal/licensing? Performance? Documentation tone?

   Seat the **specialist** for that domain in seat 1. This member brings the lived
   knowledge of how decisions in that domain actually play out.

2. **What's the broader system impact?** Most decisions ripple beyond their immediate
   domain. Seat an **architectural generalist** in seat 2 to keep the proposal coherent
   with the rest of the system. Default picks: `software-architect` for code-level
   decisions, `api-designer` for anything that crosses a service boundary.

3. **What's the worst thing that could happen if we pick wrong?** Seat a **challenger**
   in seat 3 whose specialty is exactly that failure mode:
   - Could the code be buggy or untested? → `qa-engineer`
   - Could it create a security/privacy hole? → `security-researcher`
   - Could it be slow at scale? → `performance-engineer`
   - Could it become unmaintainable? → `software-architect` (if not already seated) or `skeptic`
   - Could it expose us legally? → `lawyer`
   - Could it confuse users? → `ux-designer-<platform>` (if not already seated)
   - Could it create operational pain? → `devops-engineer` or `observability-engineer`
   - Is the question ambiguous or could be hiding the real problem? → `skeptic`

`skeptic` is the safe third pick when nothing else screams "obvious challenger" —
it specializes in surfacing hidden assumptions and reframing the question.

The shared catalog (`plugins/agents/references/agent-catalog.md`) lists every available
archetype with their tools, tags, and one-line description.

## Worked examples

| Question | Domain | Generalist | Challenger |
|----------|--------|------------|------------|
| Should the primary CTA on the iOS onboarding screen be a sheet or a full-screen push? | `ux-designer-mobile` | `software-architect` | `accessibility-engineer` |
| Should we add a retry wrapper around this third-party API call or surface failures? | `software-architect` | `api-designer` | `observability-engineer` |
| Which test framework should we standardize on for the new TypeScript SDK? | `qa-engineer` | `api-designer` | `technical-writer` |
| Is it safe to drop this column in a single migration or do we need expand/contract? | `data-engineer` | `software-architect` | `devops-engineer` |
| Should we accept this MIT-licensed dependency given our AGPL exposure? | `lawyer` | `software-architect` | `security-researcher` |
| Pagination by cursor or offset for the new list endpoint? | `api-designer` | `performance-engineer` | `software-architect` |
| Should the CLI default `--verbose` on or off? | `ux-designer-cli` | `technical-writer` | `skeptic` |
| Should the auth middleware reject expired tokens with 401 or 403? | `api-designer` | `security-researcher` | `software-architect` |
| Should this Lambda be migrated to a long-running service? | `devops-engineer` | `software-architect` | `performance-engineer` |
| Should the dashboard color-code revenue tiers using hue or saturation? | `ux-designer-web` | `accessibility-engineer` | `copy-editor` |
| Should we ship the feature behind a flag or land it directly? | `software-engineer` | `devops-engineer` | `qa-engineer` |
| Should we cache this query in Redis or in the application layer? | `performance-engineer` | `software-architect` | `observability-engineer` |
| What error message should the form show when the email is already registered? | `copy-editor` | `ux-designer-web` | `security-researcher` |
| Should the new event schema be a single wide table or normalized? | `data-engineer` | `performance-engineer` | `software-architect` |
| Should we open-source this internal library? | `lawyer` | `technical-writer` | `software-architect` |

## Patterns to notice

- **Specialist + generalist + challenger** is the dominant shape. Pure-specialist
  panels (e.g., three engineers) produce technically excellent proposals that miss
  cross-cutting concerns.
- **Don't double-seat the same archetype.** Even on a deeply technical question,
  resist seating two `software-architect`s. The point of the council is breadth.
- **Pick the challenger from the failure mode, not the domain.** A CLI UX question
  might still seat a `security-researcher` as challenger if the question is about
  whether to default-enable telemetry.
- **`skeptic` is your reframer.** When the question feels malformed or you suspect
  it's hiding a more important question, seat `skeptic` and let them push back on
  the framing in their proposal.

## Anti-patterns

- **Three people who would agree anyway.** If the panel naturally agrees, the vote
  is decorative. Pick at least one member whose perspective would plausibly conflict.
- **A specialist for a domain that's not actually involved.** Seating a
  `ux-designer-mobile` on a backend migration question wastes the seat.
- **Stacking the council to get a specific answer.** If you find yourself picking
  archetypes you know will vote a particular way, you're not running a council —
  you're rubber-stamping. Stop and either ask the user directly or accept that you
  already know the answer.

## When the rubric doesn't fit

If the question genuinely has no dominant domain (e.g., "should we ship this on
Tuesday or Wednesday?"), the question probably shouldn't go to a council. Either
ask the user, or just pick — councils are for **judgment calls with real expertise
tradeoffs**, not coin flips.
