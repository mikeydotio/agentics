---
module: "plugins/agents/agents/ux*"
summary: "Three read-only platform-specific UX reviewer agents (CLI, mobile, web) each encoding that platform's native conventions and anti-patterns."
read_when: "Choosing or editing a platform-specific UX reviewer (CLI, mobile, or web)"
sources:
  - path: plugins/agents/agents/ux-designer-cli.md
    blob: 10595e11ce270175e12322409a2b8908eae54dde
  - path: plugins/agents/agents/ux-designer-mobile.md
    blob: 5e69aab6a0ad62ccf0b8d2b06483faee6b176eb8
  - path: plugins/agents/agents/ux-designer-web.md
    blob: 47d2ee61ac977b280271bab4bb2567c765db198b
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/agents/agents/ux*

## Purpose

This module is three parallel specializations of a shared 'UX designer' review role, each hardcoding the native conventions of one surface — terminal idioms and exit codes for CLI (plugins/agents/agents/ux-designer-cli.md), HIG/Material and thumb-zone ergonomics for mobile (plugins/agents/agents/ux-designer-mobile.md), and design tokens/Core Web Vitals for web (plugins/agents/agents/ux-designer-web.md) — rather than one generic UX heuristic set that would miss platform-specific idioms. The idea holding it together is platform selection: a consumer (forge, atlas, or a user) picks the reviewer matching the surface under review instead of getting one-size-fits-all advice. If this module vanished, pipelines wanting a UX review step would lose the ability to route to platform-appropriate conventions (e.g. exit-code correctness, thumb-zone placement, or CLS/INP thresholds) entirely.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

All three agents are read-only reviewers with no Write/Edit tool access, matching their `read_only: true` frontmatter (plugins/agents/agents/ux-designer-cli.md:8, plugins/agents/agents/ux-designer-mobile.md:8, plugins/agents/agents/ux-designer-web.md:8) and each carries an explicit guardrail stating 'You have NO Write or Edit tools' (plugins/agents/agents/ux-designer-cli.md:188, plugins/agents/agents/ux-designer-mobile.md:189, plugins/agents/agents/ux-designer-web.md:207) — their lifecycle ends at producing a review, never a fix. ux-designer-cli's tool list is narrower (`Read, Grep, Glob`, plugins/agents/agents/ux-designer-cli.md:4) than mobile and web, which add `WebSearch, WebFetch` (plugins/agents/agents/ux-designer-mobile.md:4, plugins/agents/agents/ux-designer-web.md:4) — CLI conventions are treated as fixed/internal knowledge while mobile and web reviewers may look up live HIG/Material/Core Web Vitals guidance. All three share `tier: platform-variant` and `pipeline: null` (e.g. plugins/agents/agents/ux-designer-cli.md:6-7), meaning none belongs to a fixed pipeline step sequence — they are selected situationally by whichever consumer needs a platform-specific review. Each also caps its own output at 2000 lines (plugins/agents/agents/ux-designer-cli.md:189, plugins/agents/agents/ux-designer-mobile.md:190, plugins/agents/agents/ux-designer-web.md:208).

## External deps
