# Post-deploy tests (out-of-band)

deployit can run a project's test suite **after** a deploy finishes, out of band,
so a long suite runs free of any timeout. This exists because a **synchronous
PreToolUse hook can't drive a long suite** — Claude Code kills PreToolUse hooks at
~60s, but a real UI suite (e.g. a full XCUITest run that boots simulators in
batches) takes 15–20 minutes (issue #90). The gate concept is sound; only the
execution model had to change.

## Fast gate vs. long suite — pick the right path

| You want… | Use | Why |
|---|---|---|
| A **fast** pre-deploy smoke check (<60s): lint, a unit smoke test, a build-sanity gate that should *block* the deploy | A project **PreToolUse Bash hook** matching `deployit-router.sh deploy` that runs the check and exits non-zero to deny | It's synchronous and blocking — exactly what a fast gate wants, and it finishes well inside the hook timeout. |
| A **long** suite (minutes): the full UI/e2e run, which can only be **advisory** (it can't block a deploy it outlasts) | A project **`.deployit/post-deploy-test.sh`** (this doc) | It runs detached after the deploy, so the ~60s hook/tool timeout can't cut it off. |

The two are complementary — keep a fast blocking hook *and* a long advisory suite
if you want both.

## Opt in: `.deployit/post-deploy-test.sh`

Drop an executable-agnostic script at `<project>/.deployit/post-deploy-test.sh`
(the same `.deployit/` project-local convention as `ExportOptions.<platform>.plist`).
When it exists, every `/deployit deploy` — **after the build is fully published** —
spawns it **detached**, streams its output to a per-build log, and records a status
the web build page renders. When it's absent, deployit says so in the deploy output
and records a `not_configured` status (a test gate must never be a silent no-op).

deployit is **agnostic** about what the script does: it owns *both* running the
suite and reporting failures (filing GitHub issues, posting to Slack, whatever).
deployit only provides reliable out-of-band execution, a log, and a status.

### Environment passed to the script

| Var | Value |
|---|---|
| `DEPLOYIT_BUILD_ID` | The build id (unique per deploy). |
| `DEPLOYIT_PROJECT_DIR` | The app checkout the deploy ran from (also the script's cwd). |
| `DEPLOYIT_INSTALL_URL` | The build's install/landing URL. |
| `DEPLOYIT_STATE_DIR` | deployit's per-machine state dir. |
| `DEPLOYIT_TEST_LOG` | The per-build log path the suite's output streams to. |
| `DEPLOYIT_POST_TEST_STATUS_FILE` | The status JSON path (read-only for the script; deployit owns it). |

## Status lifecycle

deployit derives the outcome from the script's **exit code** and writes it to
`<state>/posttest/<build_id>.json` (log at `<state>/logs/posttest-<build_id>.log`) —
deliberately *outside* `serve/<build_id>/` so a late write can never resurrect a
build that `gc`/`rm` deleted. The build landing page and listing row show a badge:

| status | meaning |
|---|---|
| `not_configured` | No `.deployit/post-deploy-test.sh` — nothing ran (grey badge; stated loudly in the deploy output too). |
| `running` | The suite is still going out-of-band. |
| `passed` | The script exited `0`. |
| `failed` | The script exited non-zero (the suite ran and reported failure). |
| `error` | deployit couldn't launch the script at all. |

**The exit code is the whole signal** — a script that exits `0` despite partial
failures reports `passed`. Make the script exit non-zero when the suite fails.

`gc`/`rm` prune a build's status + log alongside the build.

## Execution details

- **Detached, timeout-proof:** deployit spawns `bin/deployit-posttest` with
  `start_new_session=True` and all stdio to `DEVNULL`, then returns immediately —
  the deploy's own tool call finishes in seconds while the suite keeps running in
  a new session that outlives both the CLI process and the ~60s hook/tool timeout.
- **Stays awake:** the suite runs under `caffeinate -i` so idle-sleep can't
  suspend a 20-minute run.
- **Never affects the build:** a post-test concern is best-effort — the build is
  already deployed regardless of the suite's outcome (mirrors the GitHub-release
  step's recoverable design).
- **Skipping:** set `DEPLOYIT_SKIP_POSTTEST=1` to suppress the spawn (used by tests
  and offline runs).
- **Concurrency:** status/log are keyed by build id, so parallel deploys don't
  collide — but two device/simulator suites running at once will contend. deployit
  does **not** serialize them; stagger deploys if that matters.

## Worked example — file a GitHub issue per failing test class

```bash
#!/usr/bin/env bash
# .deployit/post-deploy-test.sh — advisory post-deploy UI suite.
set -uo pipefail

make ui-test | tee -a "$DEPLOYIT_TEST_LOG"
rc=${PIPESTATUS[0]}

if [ "$rc" -ne 0 ]; then
  # Parse the log for failing XCTest classes and open one issue each.
  grep -oE "Test Suite '[^']+' failed" "$DEPLOYIT_TEST_LOG" | sort -u | while read -r line; do
    suite=$(printf '%s' "$line" | sed -E "s/Test Suite '([^']+)' failed/\1/")
    gh issue create \
      --title "UI test failure: $suite (build $DEPLOYIT_BUILD_ID)" \
      --body "Failed in the post-deploy suite for build \`$DEPLOYIT_BUILD_ID\`.

Install: $DEPLOYIT_INSTALL_URL
Full log: \`$DEPLOYIT_TEST_LOG\`" \
      --label "test-failure"
  done
fi

exit "$rc"   # non-zero -> deployit records `failed` and shows a red badge
```

`gh` must be authenticated for the example's issue-filing; that's the project's
responsibility, not deployit's.
