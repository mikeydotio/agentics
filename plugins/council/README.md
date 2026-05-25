# council

Convene a 3-member sub-agent council to make a decision when the user is unavailable
or has delegated the choice. Members propose independently, vote single-choice,
deliberate once if they're not unanimous, then run a ranked-choice runoff with a
chair tiebreaker.

## When to use

`/council-vote` is intended to be invoked by **other agents** mid-task — when an agent
hits a judgment call, the user is unavailable, and the agent doesn't want to either
guess silently or block on `AskUserQuestion`.

Use the council for **judgment calls with real expertise tradeoffs** — interaction
design choices, architectural splits, schema decisions, dependency-acceptance calls,
naming and tone questions. Don't use it for facts (read the code instead), for
reversible cheap decisions (just pick), or when the user is available and the cost of
asking is low.

## Usage

```
/council-vote <question> [-- <context summary>]
```

Examples:

```
/council-vote "Should the iOS onboarding CTA be a sheet or a full-screen push?" \
  -- "SwiftUI app, iOS 17+, primary CTA for new-user flow"

/council-vote "Should we add a retry wrapper around this third-party API call?" \
  -- "Working in services/billing/stripe-client.ts, the call already fails ~1% of the time"
```

The council writes a full audit trail to `.council/<slug>/` (gitignored by default if
your project ignores `.council/`). The caller gets back the winning proposal, a one-
paragraph rationale, any dissent, and the path to `DECISION.md`.

## How it works

1. The chair (the orchestrator skill) picks 3 archetypes from the shared agent library
   using the rubric in `references/team-composition.md`.
2. All 3 members research the question in parallel, independently.
3. Each member proposes one solution.
4. Single-choice vote. Unanimous → decision returned.
5. If not unanimous: one round of deliberation (members may revise their own proposals).
6. Ranked-choice runoff (IRV). Chair tiebreaks only if IRV cannot resolve.
7. Decision and full transcript written to `.council/<slug>/`.

See `skills/council-vote/SKILL.md` and the `references/` directory for the full
protocol and voting mechanics.

## Suggested gitignore

Add to your project's `.gitignore` if you don't want council transcripts checked in:

```
.council/
```

If you do want them in git (useful for shared post-hoc review), leave them tracked.
