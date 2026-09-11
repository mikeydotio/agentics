# Pre-tool push gate

`pre-push-tests.sh` and `pre-push-delegation.py` form a standalone bundle.
The installed copy, not the checkout, executes in agent sessions.

```sh
make install-hooks HOOK_PROVIDER=all
make check-hooks HOOK_PROVIDER=all
```

Select `claude`, `codex`, or `all`. Omitting `HOOK_PROVIDER` retains the
legacy Claude default. The script also accepts
`install|check --provider claude|codex|all`. `PREPUSH_HOOK_DEST` retains the
custom-destination contract; it cannot be combined with explicit provider
selection. The companion is installed alongside that custom destination.

Installation preserves unique backups, refuses destination symlinks, and
replaces each regular file atomically, companion first. Repeating an unchanged
installation preserves mtimes and creates no backup. Check inspects every
selected provider, both files, executable status, and its literal PreToolUse
registration. Missing registrations are reported; no command rewrites settings.
Claude reads its existing settings precedence chain; an installed Codex gate
reads `~/.codex/hooks.json`, never Claude's timeout. Custom installations retain
the legacy Claude resolver and the existing explicit settings override.

## Delegation contract — SH-681

Before discovering or running a test command, the gate asks Git which
pre-push hook the target checkout selects. Delegation requires an executable
regular file tracked with executable mode inside that checkout. It does not
execute the repository hook: Git still invokes it on the real push and honors
its refusal. The global gate retains its existing behavior when proof fails.

The probe supports a single literal Git push/commit, optional leading
`cd PATH &&`, Git `-C PATH`, and `-c` overrides for `core.hooksPath` and URL
`insteadOf`. It also accepts simple `story comment`, `echo`, and `printf`
invocations so quoted push text does not start a duplicate suite in delegated
repositories. It declines expansions, redirections, wrappers, compound commands,
unrecognized overrides, inherited Git targeting, and leading cd with CDPATH.
It never evaluates command text. Quoted paths, subdirectories, and linked
worktrees are covered by real Git fixtures.

General command-position recognition remains **AGE-63**: ordinary repositories
and commands outside this bounded grammar can still trigger the legacy matcher
on prose. This change does not authorize any bypass of their existing gate.
The SH-681 council selected this scope unanimously; the durable decision is
recorded on that story. Git's hook and targeting contracts are documented at
[githooks](https://git-scm.com/docs/githooks) and
[git](https://git-scm.com/docs/git); Python's
[shlex](https://docs.python.org/3/library/shlex.html) is tokenization, not a
complete shell parser.

## Verification

`make test-prepush-gate` includes the legacy deadline/refusal tests and both
new Python suites. They use isolated repositories, fixture homes, and a real
bare remote. The new coverage proves no test discovery starts on delegation,
both allowed and rejected remote updates obey the repository hook, ambiguous
commands retain enforcement, both installed bundles work, provider deadlines
stay separate, registration drift is reported, and backups survive repeated
repairs. Tests never install into the operator's home.
