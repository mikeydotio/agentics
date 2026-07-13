#!/usr/bin/env bash
# rca-status.sh: every ladder rung, the INCONCLUSIVE override, the corrupt/
# unexpected-status defensive default (v1's set -u crash), worktree_live, and
# the missing-.rca and --slug behaviors.
source "$(dirname "$0")/lib.sh"

REPO="$(make_fixture_repo)"
cd "$REPO"

# seed <slug> <files...> — create .rca/<slug> with a valid meta (tier from $TIER)
# plus the given artifact files.
seed() {
  local slug="$1"; shift
  mkdir -p ".rca/$slug/repro"
  jq -n --arg s "$slug" --arg t "${TIER:-}" \
    '{slug:$s, created_at:"2026-07-01T00:00:00Z", description:"desc of \($s)", tier:$t, tier_directive:"", issue:null, stack:null}' \
    > ".rca/$slug/meta.json"
  local f
  for f in "$@"; do echo "content" > ".rca/$slug/$f"; done
}

# state_of <slug> — echo "<state> <dispatch>" from a --slug query.
state_of() {
  local out; out=$(bash "$STATUS" --slug "$1")
  printf '%s %s' "$(jqf "$out" '.investigations[0].state')" "$(jqf "$out" '.investigations[0].dispatch')"
}

# ---- missing .rca dir → empty, not an error ----------------------------------
REPO_EMPTY="$(make_fixture_repo)"
out=$(cd "$REPO_EMPTY" && bash "$STATUS")
assert_json "$out" '.ok == true and .count == 0' "missing .rca → ok, count 0"

# ---- ladder rungs ------------------------------------------------------------
TIER="" seed r_intake                                   # no GRID.md
assert_eq "$(state_of r_intake)" "intake_incomplete intake" "no GRID → intake_incomplete"

TIER="" seed r_repro GRID.md                            # GRID, no REPRO/OVERRIDE
assert_eq "$(state_of r_repro)" "needs_repro reproduce" "no REPRO → needs_repro"

TIER="" seed r_override GRID.md OVERRIDE.md             # OVERRIDE substitutes for REPRO
assert_eq "$(state_of r_override)" "needs_tier reproduce" "OVERRIDE satisfies repro rung"

TIER="" seed r_tier GRID.md REPRO.md                    # REPRO present, tier empty
assert_eq "$(state_of r_tier)" "needs_tier reproduce" "empty tier → needs_tier"

TIER="full" seed r_locate GRID.md REPRO.md              # tier full, no ORIGIN
assert_eq "$(state_of r_locate)" "needs_locate locate" "tier full, no ORIGIN → needs_locate"

TIER="light" seed r_lightdiag GRID.md REPRO.md          # light tier skips locate rung
assert_eq "$(state_of r_lightdiag)" "needs_diagnosis diagnose" "light tier → straight to diagnosis"

TIER="full" seed r_diag GRID.md REPRO.md ORIGIN.md      # located, no DIAGNOSIS
assert_eq "$(state_of r_diag)" "needs_diagnosis diagnose" "located, no DIAGNOSIS → needs_diagnosis"

TIER="full" seed r_inc GRID.md REPRO.md ORIGIN.md DIAGNOSIS.md INCONCLUSIVE.md
assert_eq "$(state_of r_inc)" "inconclusive diagnose" "INCONCLUSIVE overrides later rungs"

TIER="light" seed r_report GRID.md REPRO.md DIAGNOSIS.md   # no REPORT/REMEDIATION
assert_eq "$(state_of r_report)" "needs_report report" "no REPORT → needs_report"

TIER="light" seed r_report2 GRID.md REPRO.md DIAGNOSIS.md REPORT.md  # REPORT but no REMEDIATION
assert_eq "$(state_of r_report2)" "needs_report report" "no REMEDIATION → needs_report"

TIER="light" seed r_await GRID.md REPRO.md DIAGNOSIS.md REPORT.md REMEDIATION.md
assert_eq "$(state_of r_await)" "awaiting_caller report" "no APPROVAL → awaiting_caller"

# APPROVAL that asks for a fix, no FIX.md
TIER="light" seed r_fix GRID.md REPRO.md DIAGNOSIS.md REPORT.md REMEDIATION.md
printf 'please fix it\n' > .rca/r_fix/APPROVAL.md
assert_eq "$(state_of r_fix)" "needs_fix fix" "APPROVAL says fix, no FIX → needs_fix"

# APPROVAL without "fix" → jumps to postmortem rung
TIER="light" seed r_pm GRID.md REPRO.md DIAGNOSIS.md REPORT.md REMEDIATION.md
printf 'acknowledged, no code change\n' > .rca/r_pm/APPROVAL.md
assert_eq "$(state_of r_pm)" "needs_postmortem postmortem" "APPROVAL w/o fix → needs_postmortem"

# fix approved + FIX done, no POSTMORTEM
TIER="light" seed r_pm2 GRID.md REPRO.md DIAGNOSIS.md REPORT.md REMEDIATION.md FIX.md
printf 'fix please\n' > .rca/r_pm2/APPROVAL.md
assert_eq "$(state_of r_pm2)" "needs_postmortem postmortem" "fixed, no POSTMORTEM → needs_postmortem"

# everything present → complete
TIER="light" seed r_done GRID.md REPRO.md DIAGNOSIS.md REPORT.md REMEDIATION.md POSTMORTEM.md
printf 'ack\n' > .rca/r_done/APPROVAL.md
assert_eq "$(state_of r_done)" "complete none" "all artifacts → complete"

# ---- corrupt meta.json → corrupt, NOT a crash (v1 defect #1) -----------------
mkdir -p .rca/r_corrupt
printf '{ this is not valid json' > .rca/r_corrupt/meta.json
out=$(bash "$STATUS" --slug r_corrupt)
assert_eq "$(jqf "$out" '.investigations[0].state')" "corrupt" "malformed meta → corrupt"
assert_json "$out" '.investigations[0].option.label != null and .investigations[0].option.description != null' \
  "corrupt still yields option label+description (no unset var)"

# ---- missing meta.json entirely → corrupt ------------------------------------
mkdir -p .rca/r_nometa/repro
out=$(bash "$STATUS" --slug r_nometa)
assert_eq "$(jqf "$out" '.investigations[0].state')" "corrupt" "no meta → corrupt"

# ---- unexpected-status defensive default: every rung yields an option --------
# (v1 defect #2: the label/description case had no default branch.) Assert that
# EVERY investigation the ladder produced has a non-empty option pair.
out=$(bash "$STATUS")
assert_json "$out" '[.investigations[] | select(.option.label == null or .option.label == "")] | length == 0' \
  "every investigation has an option.label"
assert_json "$out" '[.investigations[] | select(.option.description == null)] | length == 0' \
  "every investigation has an option.description"

# ---- worktree_live reflects worktree.json presence ---------------------------
assert_eq "$(jqf "$(bash "$STATUS" --slug r_done)" '.investigations[0].worktree_live')" "false" "no worktree.json → false"
printf '{"slug":"r_done"}' > .rca/r_done/worktree.json
assert_eq "$(jqf "$(bash "$STATUS" --slug r_done)" '.investigations[0].worktree_live')" "true" "worktree.json → live"

# ---- summary: GRID first line wins over meta.description ----------------------
printf '# Heading\n\nThe login button double-fires on slow networks.\n' > .rca/r_done/GRID.md
assert_eq "$(jqf "$(bash "$STATUS" --slug r_done)" '.investigations[0].summary')" \
          "The login button double-fires on slow networks." "summary = first non-heading GRID line"

# ---- --slug filters to exactly one -------------------------------------------
out=$(bash "$STATUS" --slug r_intake)
assert_json "$out" '.count == 1 and .investigations[0].slug == "r_intake"' "--slug filters to one"

finish
