# HANDOFF — atlas plugin build (Phases 6–7 remain)

Branch: `feat/atlas-plugin` (do not push without running `make test`; the
pre-push hook enforces it). Plan of record:
`/Users/mikey/.claude/plans/design-a-codebase-mapping-skill-fancy-river.md`.
Contributor onboarding: `plugins/atlas/references/design.md` (decision record +
roadmap — read first).

## State

Phases 1–5 complete and committed. The deterministic core (scan, partition,
ground, blob-SHA ledger, lock, status tiers, lint L1–L11, INDEX rebuild,
guarded commit, CLAUDE.md init/remove), the shared agents (cartographer,
map-verifier), the /atlas skill + full-map protocol, and the SessionStart hook
all exist and are tested: 88 atlas tests green, `make test` green overall.

Phase 5 was dogfooded end-to-end on this repo: docs/atlas/ now holds a
32-module map + ARCHITECTURE overview + derived INDEX (5,624 chars), all 32
docs verified (map-verifier pass, `verified: true`), lint 0 errors,
`atlas-cli status` reports tier 0, CLAUDE.md carries the managed atlas block
with the @docs/atlas/INDEX.md import.

## Next: Phase 6 — incremental update + verify flows

Replace the stub `plugins/atlas/references/update-protocol.md` with the real
protocol (plan §Phase 6): lock → `ledger diff` → plan presentation →
>50%-affected escalation to full remap → mechanical rename rewrites (no LLM) →
orphan deletion (doc + INDEX row, same commit) → anchored regeneration of
stale+ripple docs (prior doc + `git diff $OLD_BLOB $NEW_BLOB` per source) →
new-file assignment via partition → overview regen iff any module doc changed
→ **init-style mutations BEFORE the final finalize** → finalize → index
rebuild → lint → verify changed docs → commit → release. Add `/atlas verify`
(lint + verifier sweep, no regeneration). SKILL.md dispatch rows already
exist. e2e fixture tests per plan (edit/rename/delete/ripple/hash-gating
proof: unchanged docs byte-identical).

Hard-won protocol lessons already encoded in mapping-protocol.md — keep them
true in the update protocol too: overview `scopes` must never contain
docs/atlas's parent; every mutation (init, doc edits) precedes the final
finalize, else the ledger correctly reports the map stale at birth.

## Phase 7 punch list (besides plan §Phase 7)

- `plugins/agents/agents/_template.md` pipeline enum: add `atlas`.
- map-format.md: exempt Relationships edge lines from the 100-char rule
  (long module ids make compliance impossible; several docs note this).
- `ground`: skip .md files when extracting definition candidates (prose noise).
- Dogfood findings to surface to the user (map Gotchas carry citations):
  deployit troubleshooting documents a `questions` array the CLI never emits;
  forge README ships a pre-refactor 15-agent roster; forge skills name
  devils-advocate/senior-engineer/ux-designer which have no library files;
  freshen SKILL.md:64 contradicts its one-source-at-a-time CLI; greenlight
  `permissive` mode behaves identically to `standard` and terraform/helm
  case-guards are dead; rca-status.sh never surfaces INCONCLUSIVE.md; the
  root bats suite tests a nonexistent "pilot" plugin; forge bin .bats files
  resolve paths that can't work in place.
- Release: /semver bump minor (expect v2.18.0), push via HTTPS override,
  PR per branch+PR flow.
