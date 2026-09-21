# Build Configuration Reference

Which build configuration deployit archives with, and why it can refuse to deploy.

## The short version

**deployit does not choose your build configuration.** It passes no
`-configuration` to `xcodebuild`, so your scheme's **Archive** action decides — exactly as
Archiving from Xcode would.

What deployit *does* is check the result. Before archiving it asks xcodebuild what the archive
will resolve to, and **refuses to build an unoptimized archive you have not acknowledged**.

## Why deployit stopped choosing

Until v3.0.0 deployit passed `-configuration Debug` unconditionally. An explicit `-configuration`
on the command line **overrides the scheme's Archive action**, so a project whose scheme correctly
said `Release` was silently downgraded. Every OTA build deployit produced before v3.0.0 shipped
unoptimized, with any `#if DEBUG` code compiled in.

Measured on a real project — identical commands, one flag apart:

| Setting | no `-configuration` | `-configuration Debug` |
|---|---|---|
| `CONFIGURATION` | `Release` | `Debug` |
| `SWIFT_OPTIMIZATION_LEVEL` | `-O` | `-Onone` |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | *(absent)* | `DEBUG` |
| `GCC_OPTIMIZATION_LEVEL` | *(absent)* | `0` |
| `ENABLE_TESTABILITY` | `NO` | `YES` |

## How the check works

Before archiving, deployit runs:

```
xcodebuild <container> -scheme <s> -destination <d> -showBuildSettings -json archive
```

with the same container, scheme, destination and toolchain the archive itself will use — so its
answer is the one that actually governs the build, not a guess. Cost is a few seconds (measured
3 s on a single-app project, 22 s on a workspace with local Swift packages).

The verdict is **substance-based, never name-based**, so a configuration *named* `Release` that
compiles `-Onone` is still caught:

| Rung | Setting | Verdict |
|---|---|---|
| 1 | `SWIFT_OPTIMIZATION_LEVEL` | unoptimized when `== -Onone` |
| 2 | *(no Swift key)* `GCC_OPTIMIZATION_LEVEL` | unoptimized when `== 0` |
| 3 | *(neither key, but xcodebuild answered)* | **optimized** — inherits the xcspec defaults |
| — | *(xcodebuild gave no answer at all)* | → **unresolved**, see below |

> Rung 3 is a toolchain fact, not a guess. Xcode's `Swift.xcspec` declares
> `SWIFT_OPTIMIZATION_LEVEL` DefaultValue `-O` and `Clang.xcspec` declares
> `GCC_OPTIMIZATION_LEVEL` DefaultValue `s`, so a configuration that simply inherits those
> defaults compiles optimized while reporting neither key. An explicitly unoptimized
> configuration reports `-Onone` / `0` and is caught on rungs 1–2. The archive records the
> inherited case as `optimization_level: "xcspec-default"` so it is never confused with
> "could not tell", which is now `null` and reachable only from the last row.
>
> **`unresolved` means xcodebuild did not answer — nothing else.** Before AGE-110 it also
> covered rung 3, so deployit refused every project whose Release inherits Xcode's defaults
> (the normal case) while telling the operator that xcodebuild had failed, which it had not.

## Outcomes

| Situation | What happens |
|---|---|
| Optimized archive | Proceeds silently. |
| Unoptimized, **not** acknowledged | **Refused** before the archive, on every platform. |
| Unoptimized, acknowledged | Proceeds with a loud warning, and the record is persisted. |
| Unoptimized, acknowledged, **and publishing a GitHub release** | **Refused anyway.** |
| Settings could not be resolved | **Refused**, with its own message. |

## Acknowledging a deliberate unoptimized build

Some projects deploy Debug builds on purpose — an on-demand test build with `#if DEBUG` behavior
that is the whole point of the deploy. Say so in the project's committed
`.deployit/config.toml`:

```toml
[build]
allow_debug = true
```

That is an **acknowledgement, not a setting**. It does not choose, change, or reach the build
configuration — your scheme still decides that. It records that you know this project deploys
unoptimized builds, and it turns the refusal into a warning.

Because it lives in the repo, every project's posture is greppable rather than buried in one
person's terminal history.

### What `allow_debug` deliberately does *not* cover

**Publishing.** Every macOS deploy publishes a Developer-ID-signed GitHub release by default, and
a published release cannot be recalled. So an unoptimized archive is refused at that boundary
**even with `allow_debug = true`**:

```
deployit deploy --platform macos --no-release      # or [github] release = false
```

`allow_debug` buys you a sideload to your own devices. It does not authorise shipping an
unoptimized signed binary to everyone.

**Unresolved settings.** If xcodebuild cannot report what it would build, deployit refuses and
`allow_debug` does *not* silence it — *"I know this is unoptimized and I accept it"* is a
different claim from *"deployit could not tell"*. In practice an unresolvable query means the
archive was about to fail anyway, so the refusal converts a late failure into an early one with a
better message.

## Why there is no `[build] configuration = "..."` key

Deliberately refused, not merely unimplemented.

Your scheme's Archive action already declares which configuration to archive, and for XcodeGen
projects that declaration is committed in `project.yml`. A deployit-side value key would be a
**second authority over the same fact**, free to diverge silently: `Archive` in Xcode and
`deployit deploy` would build different things with nothing reporting the disagreement. That is
the defect this release fixed, relocated rather than removed.

If you need a different archive configuration, change it where it is already declared — the
scheme.

## What gets recorded

Every build stores what it was actually built with, in its `_meta.json` and in the published
index entry:

| Field | Meaning |
|---|---|
| `configuration` | the resolved configuration name, e.g. `Release` |
| `optimization_level` | the resolved optimization level, e.g. `-O` |
| `configuration_source` | how it was determined |

`optimization_level` is stored alongside the name on purpose: **the name is the field that can
lie.** A `Release`-named configuration built `-Onone` is exactly the case a name-only record
would whitewash.

This matters because there is no way to recover it later — a `.xcarchive`'s `Info.plist` records
the scheme and the version but **not** the configuration. Without this record, the only evidence a
build shipped unoptimized would be a warning line that scrolled out of a terminal months ago.

## Upgrading to v3.0.0

If a project deliberately archives Debug, its next deploy will **fail** until you either fix the
scheme or add `[build] allow_debug = true`. That is intentional: the setting was previously
invisible, and this is the one-time cost of making it explicit.

Every other project gets what it always meant to get — an optimized archive — with no change.

## See also

- `references/toolchain.md` — pinning the Xcode that archives (`[toolchain]`); the settings query
  honours the same pin, so the check and the build always agree on the toolchain.
- `references/macos.md` — Developer-ID signing and GitHub release publishing.
