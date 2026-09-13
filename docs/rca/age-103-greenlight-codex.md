# AGE-103: Greenlight Codex hook output

## Failure and origin

Greenlight 3.9.1 returns a Claude `permissionDecision: allow` envelope for
safe Bash/Read calls even when the payload identifies Codex with `turn_id`.
Codex 0.154.0 rejects bare approval without `updatedInput`. Greenlight does
not rewrite input, so a safe classification must defer to Codex permission
handling. Warnings and denials already use supported shapes.

SH-707 independently reproduced this interface mismatch and supplied a
production-entrypoint Bats candidate. Its StoryHook handoff commit is
`6da5a4185`; the personal-hook repair is separate, in `7d4de7e68`.
The authored contract assertion is not captured Codex stderr. The SH-707
investigation checked the upstream Codex output parser and challenged
StoryHook regression and stale-install explanations; neither explained
Greenlight's independent output. No original-incident telemetry establishes
when the user first encountered the symptom.

The approval shape exists in original Greenlight commit
`1d9d4ab1760ed107bd22c0e8cc430c396e261ab2`; this is host compatibility work,
not a demonstrated regression from a known-good Codex version. Existing
coverage lacked Codex payloads and successful AI responses.

## Three origin repairs

| Defect | Repair and invariant |
|---|---|
| `.answer // empty` discards boolean false; raw strings lose type identity | Validate exactly one structured object with boolean answer and nonempty string rationale before conversion. Invalid data logs AI_FAIL and follows existing deferral. |
| Manifest uses only an unquoted CLAUDE_PLUGIN_ROOT | Quote the hook path; prefer nonempty PLUGIN_ROOT, then CLAUDE_PLUGIN_ROOT. Apply the same order to bundled resources; direct invocation retains script-relative fallback. |
| Deterministic and AI approvals serialize independently | One approval helper selects output by turn_id key presence. Codex emits no approval fields; Claude retains its allow envelope. |

Codex safe output is empty unless rationale is enabled, in which case it
contains only `hookEventName` and `additionalContext`. No fabricated input
rewrite is needed. Denials, warning context, and existing ALLOW/AI_RESULT
log detail are preserved. Host identity comes from the payload, independently
of the root variables used to locate installed files.

The shared helper also prevents a future approval branch from accidentally
reintroducing Claude-only serialization. The AI tests assert AI_RESULT with
boolean false: silent output alone could otherwise hide parser failure.
The manifest tests execute the actual packaged command and identify which
bundled configuration it loaded, including roots containing spaces.

## Validation

- AI regressions: four failures before repair, then seven tests passing.
  Cases include true/false, wrong JSON types, absent fields, multiple objects,
  malformed JSON, invalid rationale, and contextual failure diagnostics.
- Manifest regressions: five failures before repair, then six tests passing.
- Host regressions: seven failures before serialization repair, then nineteen
  tests passing, including both rationale settings, denials, warnings,
  malformed/unrelated input, escaped text, and host/root independence.
- Final command: `TMPDIR=/tmp bash tests/with-isolated-store.sh bash
  plugins/greenlight/tests/run-tests.sh` — all 127 tests pass (32 new and
  95 existing). Test homes and HTTP fixtures are isolated; no live API is used.
- Bash syntax, manifest JSON, whitespace, and warning-level lint of new test
  fixtures pass. Production ShellCheck matches the original baseline by code,
  severity, message (normalizing shifted line numbers), and affected source:
  six SC2221/SC2222 warnings for wc/terraform/helm pattern overlaps and two
  SC2016 literal-string notes. No production warning was added or suppressed.
- A separate fixture-only commit makes the Bats status precondition explicit
  and orders assertion definitions before tests to eliminate false diagnostics.
  The escaping regression deliberately contains literal shell expressions;
  ShellCheck reports an informational SC2016 note for that fixture data.

## Delivery boundary

AGE-81, AGE-93, and AGE-102 were reviewed on resumption; none superseded these
requirements. Source delivery belongs to AGE-103; SH-707 owns the personal
hook repair and follow-through after Agentics verification. No installed
plugin cache, release version, deployment, or host permission control is
modified here. The centralized verifier owns publication and completion.
