---
module: "plugins/forge (misc)"
summary: "Forge plugin identity manifest, README pipeline overview, and the bats test-suite entrypoint for bin/ and hooks/."
read_when: "Changing forge's marketplace identity, README pipeline overview, or bats test runner"
sources:
  - path: plugins/forge/.claude-plugin/plugin.json
    blob: 39650806aeec547873c043902a97521e45f0ebf4
  - path: plugins/forge/README.md
    blob: 1ce02e4c6294d5613a305d8487b42132d669a063
  - path: plugins/forge/tests/run-tests.sh
    blob: ec21a7688fb6712b2f89b69aaa176c1bde7999b7
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge (misc)

## Purpose

This module holds forge's non-code identity and entrypoint artifacts rather than pipeline logic: the marketplace manifest that names and versions the plugin (plugins/forge/.claude-plugin/plugin.json), the README that is the only human-facing description of the 11-step pipeline and its state-machine/step-exit architecture (plugins/forge/README.md), and the bats test runner that is the sole invocation path for forge's bin/ and hooks/ suites (plugins/forge/tests/run-tests.sh). Without it, forge would have no marketplace-visible identity, no external documentation of its pipeline shape, and no command to run its own tests.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

run-tests.sh resolves PLUGIN_DIR from its own location via cd/dirname rather than the caller's cwd, then invokes bats directly against the bin/ and hooks/ subdirectories in place of a dedicated tests/ directory (plugins/forge/tests/run-tests.sh:13-21). plugin.json's version field (plugins/forge/.claude-plugin/plugin.json:3) is a plain static string in this module with no in-file indication of how it is kept in sync with anything else.

## External deps


## Gotchas

The test-runner's own header comment flags a deliberate deviation: unlike semver/deployit/atlas's custom test_*-function discovery harness, forge's bats suites live alongside the scripts they test in bin/ and hooks/ rather than a dedicated tests/ directory, so run-tests.sh just points bats at both (plugins/forge/tests/run-tests.sh:4-8).
