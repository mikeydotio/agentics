#!/usr/bin/env bash
# tests/prompt-hygiene.sh — Claude 5 prompt-realignment regression guard (#118).
#
# Self-contained plain-bash harness (NO bats dependency) so it runs under
# `make test` on every machine — bats is not installed here and this project
# does not run tests in CI, so a .bats file would never actually execute.
# Mirrors the per-plugin harness convention: define test_* functions, run
# each in an isolated subshell, print "=== name ===" / "  PASS|FAIL  fn",
# exit with the failure count. Structurally mirrors tests/plugin-versions.sh.
#
# WHY: issue #118 realigned agentics' prompt content from the Claude 4.x
# prompting contract to the Claude 5 one — model/effort tiering, dropped
# self-verification instructions, resolved bug-archaeology citations, a
# skill-listing description budget. Nothing enforced any of it stayed that
# way. This is the enforcement.
#
# SCOPE: model-read prompt surfaces only —
#   plugins/*/skills/*/SKILL.md, plugins/*/agents/*.md,
#   plugins/*/agent-overrides/*.md, plugins/*/references/*.{md,yaml,yml}
# excluding plugins/*/tests/**, *.bats, and plugins/*/README.md. An F0NN
# citation or a self-verification phrase in a .sh comment is ordinary code
# commentary; the same text inside a SKILL.md is an instruction the model
# reads and acts on. Scoping the lint to what a model actually reads is
# deliberate — see docs/decisions/forge-hardening.md-style reasoning: a
# lint that also walked bin/**/*.sh would fail on ~170 legitimate comments
# and train everyone to ignore its output.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "$1" >&2; return 1; }

# ── File discovery ──────────────────────────────────────────────────────
#
# By directory shape, not a hand-maintained list — a new plugin's SKILL.md
# or references/ file is covered automatically (forge-contract-check.sh's
# same rationale: a drift guard that requires updating for new files isn't
# one).

skill_files() {
    find plugins -type f -path '*/skills/*/SKILL.md' | sort
}

scanned_files() {
    find plugins -type f \( \
            -path '*/skills/*/SKILL.md' -o \
            -path '*/agents/*.md' -o \
            -path '*/agent-overrides/*.md' -o \
            -path '*/references/*.md' -o \
            -path '*/references/*.yaml' -o \
            -path '*/references/*.yml' \
        \) \
        -not -path '*/tests/*' \
        -not -name '*.bats' \
        -not -name 'README.md' \
        | sort -u
}

# ── Frontmatter helpers ─────────────────────────────────────────────────
#
# Mirrors plugins/agents/bin/validate-agents.sh's own extraction: pure
# sed/grep, no yq/python3. `sed '$d'` drops the closing marker rather than
# `head -n -1`, which is GNU-only.

has_frontmatter() {
    head -1 "$1" 2>/dev/null | grep -q '^---$'
}

frontmatter_of() {
    sed -n '2,/^---$/p' "$1" | sed '$d'
}

# Single-line frontmatter fields only (name/model/effort/description are
# always one physical line in this repo's style — same assumption
# validate-agents.sh makes).
frontmatter_field() {
    local file="$1" field="$2"
    has_frontmatter "$file" || return 0
    # `grep` legitimately returns 1 when the field is absent (most files have
    # no `model:` line) — under `pipefail` that would propagate as this
    # function's own exit status and, under the caller's `set -e`, silently
    # abort the whole test. The explicit `return 0` makes absence a normal
    # empty-string result, not a failure.
    frontmatter_of "$file" | grep "^${field}:" | sed "s/^${field}: *//" | head -1
    return 0
}

# ── test_* functions ────────────────────────────────────────────────────

# Anti-vacuity: a broken glob must not pass silently (rca/tests/test-skill-
# contract.sh's own pattern). 129 scanned files at authoring time; 100 is
# a floor with real margin, not a brittle exact count.
test_scan_covers_a_realistic_file_count() {
    local n
    n=$(scanned_files | wc -l | tr -d ' ')
    [ "$n" -ge 100 ] || fail "prompt-hygiene scan found only $n files — the glob may be broken (expected >=100)"
}

# Frontmatter `model:` must be a bare tier alias, never a dated ID. This is
# the regression class semver/skills/semver/SKILL.md's `claude-sonnet-4-6`
# pin was: a full model string that stops tracking Anthropic's latest
# release of that tier and eventually points at a retired model. Scoped to
# the frontmatter KEY only — greenlight's prose and sample config legitimately
# cite dated IDs like `claude-haiku-4-5` as literal config values a human
# sets, not a `model:` pin this lint governs.
test_frontmatter_model_is_a_bare_alias() {
    local f val bad=""
    while IFS= read -r f; do
        val="$(frontmatter_field "$f" model)"
        [ -z "$val" ] && continue
        case "$val" in
            haiku|sonnet|opus|fable|inherit) : ;;
            *) bad="${bad}${bad:+$'\n'}  $f: model: $val" ;;
        esac
    done < <(scanned_files)
    [ -z "$bad" ] || fail "non-alias model pin(s) — use haiku/sonnet/opus/fable/inherit only:
$bad"
}

# Skills share the session's own context window (a subagent's window is
# sized by its own model instead) — 8b73a59 is the regression this guards:
# /semver pinned to a 200k model hard-failed once a session outgrew that
# window. Agents are exempt by design (validate-agents.sh's own check #12
# already allows haiku there).
test_no_haiku_pin_on_a_skill() {
    local f val bad=""
    while IFS= read -r f; do
        val="$(frontmatter_field "$f" model)"
        [ "$val" = "haiku" ] && bad="${bad}${bad:+$'\n'}  $f"
    done < <(skill_files)
    [ -z "$bad" ] || fail "skill(s) pinned to haiku — shares the session context window (8b73a59):
$bad"
}

# opus/fable track the latest release of their line, so pinning either is a
# no-op when the session is already on that line and a downgrade when the
# session is on something more capable (Fable 5, an Opus 5 session pinned
# to an older name). Judgment tier omits model: and raises effort: instead.
test_never_pinned_up() {
    local f val bad=""
    while IFS= read -r f; do
        val="$(frontmatter_field "$f" model)"
        case "$val" in
            opus|fable) bad="${bad}${bad:+$'\n'}  $f: model: $val" ;;
        esac
    done < <(scanned_files)
    [ -z "$bad" ] || fail "pinned-up model(s) — never pin opus/fable, omit model: to inherit and raise effort: instead:
$bad"
}

# Claude 5 models verify their own work, cap their own retries, and manage
# their own budgets; instructing them to again causes over-verification.
# Same regex as validate-agents.sh check #14 (kept identical on purpose —
# one definition of the banned pattern, not two that can drift apart).
# Deliberately does NOT match bare "re-verify" without "before": rca's
# hypothesis-falsification.md and diagnose/SKILL.md use "re-verify the new
# link" in the scientific-method sense (extend a causal chain and check the
# next link), not a self-verification instruction.
SELF_VERIFY_RE='double.?check|verify your (own )?work|re-?verify before|final verification step'
test_no_self_verification_phrasing() {
    local f m hits=""
    while IFS= read -r f; do
        m="$(grep -niE "$SELF_VERIFY_RE" "$f" 2>/dev/null || true)"
        [ -n "$m" ] && hits="${hits}${hits:+$'\n'}  $f:
$(printf '%s\n' "$m" | sed 's/^/    /')"
    done < <(scanned_files)
    [ -z "$hits" ] || fail "redundant self-verification phrasing found:
$hits"
}

# SKILL.md body budget — 500 lines, official skill-authoring guidance's
# ceiling for what stays resident vs. what moves to references/ for
# progressive disclosure. Body = everything after the frontmatter block.
test_skill_body_under_500_lines() {
    local f total close body bad=""
    while IFS= read -r f; do
        total=$(wc -l < "$f" | tr -d ' ')
        if has_frontmatter "$f"; then
            close=$(awk 'NR>1 && /^---$/{print NR; exit}' "$f")
            body=$(( total - close ))
        else
            body=$total
        fi
        [ "$body" -gt 500 ] && bad="${bad}${bad:+$'\n'}  $f: $body body lines"
    done < <(skill_files)
    [ -z "$bad" ] || fail "SKILL.md over the 500-line body budget:
$bad"
}

# Description budget — Claude Code's skill listing is capped at ~1% of the
# model's context window; overflow drops least-invoked descriptions first,
# stripping the keywords a request needs to match a skill. 500 chars is the
# per-entry ceiling; AGE-10 measured every skill against it (worst was
# council-vote at 1,081).
test_description_under_500_chars() {
    local f desc len bad=""
    while IFS= read -r f; do
        desc="$(frontmatter_field "$f" description)"
        len=${#desc}
        [ "$len" -gt 500 ] && bad="${bad}${bad:+$'\n'}  $f: $len chars"
    done < <(skill_files)
    [ -z "$bad" ] || fail "description over the 500-char skill-listing budget:
$bad"
}

# Internal audit finding-IDs (F003…F098) are unresolvable to anyone reading
# a shipped skill — no public tracker entry exists for them. WS-A/WS-B/WS-D
# already swept every instance out of runtime prose; this keeps a new one
# from creeping back in. Scope (scanned_files) already excludes tests/,
# *.bats, and README.md — the ~170 remaining marketplace-wide F-citations
# are ordinary `#` comments in bin/**/*.sh and are correctly out of reach.
test_no_finding_id_citations() {
    local f m hits=""
    while IFS= read -r f; do
        m="$(grep -noE 'F[0-9]{3}' "$f" 2>/dev/null || true)"
        [ -n "$m" ] && hits="${hits}${hits:+$'\n'}  $f: $(printf '%s' "$m" | tr '\n' ' ')"
    done < <(scanned_files)
    [ -z "$hits" ] || fail "finding-ID citation(s) in shipped prompt prose:
$hits"
}

# ── Runner ───────────────────────────────────────────────────────────────

command -v awk >/dev/null 2>&1 || { echo "ERROR: awk is required" >&2; exit 1; }

PASS=0
FAIL=0
FAILURES=()

echo "=== prompt-hygiene ==="
for fn in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    set +e
    out="$( set -e; "$fn" 2>&1 )"
    ec=$?
    set -e
    if [ $ec -eq 0 ]; then
        echo "  PASS  $fn"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $fn"
        [ -n "$out" ] && echo "$out" | sed 's/^/        /'
        FAIL=$((FAIL + 1))
        FAILURES+=("$fn")
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    printf 'Failures:\n'
    printf '  - %s\n' "${FAILURES[@]}"
fi
exit "$FAIL"
