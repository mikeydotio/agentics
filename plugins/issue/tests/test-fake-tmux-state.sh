#!/usr/bin/env bash
# AGE-83: the fake tmux's state directory is NAMED BY THE CALLER, always.
# Ported from storyhook's SH-263 fix for the identical defect in its own
# fork of this file (plugin/claude-code/tests/test-fake-tmux-state.sh).
#
# The fake holds every byte of its model -- the input buffer, the `launched`
# flag, the absorb counter -- in files under one directory, because it is
# re-exec'd per tmux call and can keep nothing in process memory. That
# directory used to fall back to a FIXED, world-writable path
# (`/tmp/issue-faketmux`) whenever $FAKE_TMUX_STATE was unset, and five of
# this suite's own test files left it unset. They therefore shared one
# directory with each other, with every concurrent run of this suite, and
# with storyhook's fork of this same fake -- a directory that could also
# persist between runs. See test-occupant-*.sh (AGE-83's next commit) for
# the collision this invites once the fake tracks a pane's occupant: a
# second user's `new-window` clears a first user's `launched`/`input`, and
# its next Enter is then read as a launch line of nothing, deriving the
# fallback shell name over the first user's occupant.
#
# This file deliberately does not set $FAKE_TMUX_STATE. It is the same shape
# as the five that forgot to, and it inherits whatever lib.sh gives every
# test -- which is the fix, and which is what the first case below measures.
source "$(dirname "$0")/lib.sh"

FAKE_TMUX="$TESTS_DIR/fakes/tmux"
LEGACY_SHARED_STATE=/tmp/issue-faketmux

# --- the fake refuses to invent a state directory --------------------------
#
# Refusal rather than a default is the whole repair: a fake that silently
# invents a shared path where a private one was meant fails the way this
# harness exists to prevent -- quietly, in another test's assertions, hours
# later, on a change that touched none of it.
out="$(env -u FAKE_TMUX_STATE "$FAKE_TMUX" display-message -p '#{window_id}' 2>&1)"
rc=$?
[ "$rc" -ne 0 ] || fail_test "the fake ran with no \$FAKE_TMUX_STATE (exit $rc)"
assert_contains "$out" "FAKE_TMUX_STATE" \
  "the refusal names the variable that was not set"

# ...and it stores state, it does not own it: a directory the caller never
# created is a mistake worth failing on, not one to paper over with `mkdir -p`.
pane_cwd="$(mktemp -d /tmp/issue-test-tmux-cwd.XXXXXX)"
_TMP_REPOS+=("$pane_cwd")
missing="$pane_cwd/never-created"
out="$(FAKE_TMUX_STATE="$missing" "$FAKE_TMUX" display-message -p '#{window_id}' 2>&1)"
rc=$?
[ "$rc" -ne 0 ] || fail_test "the fake ran against a state directory that does not exist (exit $rc)"
[ ! -d "$missing" ] || fail_test "the fake created the state directory it was refusing"

# --- every test gets its own, from lib.sh -----------------------------------
#
# In lib.sh rather than in each test file, for the reason the fake-gh block
# above it is: five files forgot, and a fixture you can forget is one that
# will be forgotten again. Two independent sourcings must never land in one
# directory -- that IS the concurrent-runs case, minus the timing.
[ -n "${FAKE_TMUX_STATE:-}" ] || fail_test "lib.sh left \$FAKE_TMUX_STATE unset"
[ -d "${FAKE_TMUX_STATE:-}" ] || fail_test "lib.sh's \$FAKE_TMUX_STATE is not a directory"
case "${FAKE_TMUX_STATE:-}" in
  "$LEGACY_SHARED_STATE" | "$LEGACY_SHARED_STATE"/*)
    fail_test "lib.sh handed out the shared path this story retired" ;;
  /tmp/* | /private/tmp/*) : ;;
  *) fail_test "lib.sh's \$FAKE_TMUX_STATE [${FAKE_TMUX_STATE:-}] is not under /tmp" ;;
esac

mint() {
  env -u FAKE_TMUX_STATE bash -c \
    'source "$1/lib.sh"; printf "%s|%s" "$FAKE_TMUX_STATE" "$([ -d "$FAKE_TMUX_STATE" ] && printf dir)"' \
    _ "$TESTS_DIR"
}
first="$(mint)"
second="$(mint)"
assert_contains "$first" "|dir" "a sourced lib.sh mints a state directory that exists"
[ "${first%|*}" != "${second%|*}" ] \
  || fail_test "two independent test files were handed the same state directory [${first%|*}]"

# --- the fixed default cannot come back -------------------------------------
#
# Structural, not behavioural: the refusal above proves today's fake has no
# default, and this proves no future edit can reintroduce one without saying
# so here first.
# Comment lines are stripped first: the fake's header records what the shared
# path WAS and why it went, which is history worth keeping and not a default
# anything can fall back into. What must never reappear is an executable line
# naming it, or any value substituted in for an unset $FAKE_TMUX_STATE.
code="$(grep -v '^[[:space:]]*#' "$FAKE_TMUX")"
case "$code" in
  *issue-faketmux*) fail_test "the fake names the shared path this story retired" ;;
esac
if printf '%s\n' "$code" | grep -Eq 'FAKE_TMUX_STATE:-[^}]'; then
  fail_test "the fake substitutes a default for \$FAKE_TMUX_STATE again"
fi

# --- nothing in this suite opts out of lib.sh -------------------------------
#
# Derived over the directory rather than listed here: a hand-maintained list
# of the files that must source lib.sh is a list that drifts, and the fake's
# state isolation reaches a test file through exactly one source line.
for t in "$TESTS_DIR"/test-*.sh; do
  grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*/lib\.sh' "$t" \
    || fail_test "$(basename "$t") does not source lib.sh, so it inherits no isolation"
done

finish
