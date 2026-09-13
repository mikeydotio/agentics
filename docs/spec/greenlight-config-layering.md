# AGE-52: Greenlight live defaults

## Problem and decision

Greenlight v3.9.1 copied its bundled defaults into the user's configuration on
first use. All copied keys then overrode later corrections. The hook also kept
a second set of default values in code, and the explorer had an independent
reader. Correcting the bundle alone could not change an existing installation.

Read the bundled defaults on every invocation and layer an optional sparse user
file above them. Preserve legacy entries as explicit pins: neither equality with
an old default nor a file timestamp proves user intent. Automatic historical-value
migration would silently change deliberate safety choices. Warning-only drift
detection would leave the underlying freeze intact. This follows the separation
of vendor defaults and local overrides described in the
[systemd configuration documentation](https://www.freedesktop.org/software/systemd/man/252/journald.conf.html).

AGE-26's command classification, AGE-103's host serialization/root resolution,
and AGE-54's explorer permission policy remain separate. No permission vocabulary
or model value changes belong to this configuration repair.

## Read contract

`plugins/greenlight/lib/config.sh` is the shared Bash 3.2 reader. Fixed key and
destination-name arrays contain the schema, not default values. The bundle is
authoritative for every value; missing bundled keys are packaging errors.
Resolution is user entry, otherwise bundled entry. Explorer `--model` overrides
the resolved model. Root precedence remains `PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`,
then the invoking script's package root.

No normal read creates a directory, user file, lock, or migration marker. The
reader uses Bash builtins with one pass per layer, avoiding per-key processes or
an extra parser dependency on every hook invocation. Data is never evaluated.

| Input | Interpretation |
|---|---|
| Missing user file/key | Current bundled value |
| Explicit nonempty entry | User pin, even when equal to the default |
| Empty list or log path | Explicit empty value |
| Empty other scalar | Bundled value; still disclose the existing pin |
| Matching outer quotes | Strip the outer pair; content is literal |
| CRLF / missing final newline | Supported |
| Unknown key or comment | Ignored by resolution, preserved during edits |
| Duplicate recognized key / malformed recognized line | Contextual error |
| Missing/unreadable bundle or unreadable existing user file | Contextual error |

This is a flat scalar format, not general YAML: no nesting, arrays, multiline
values, inline comments, escape decoding, or shell expansion. Validate booleans,
analysis mode and positive integer timeout. Do not duplicate the explorer policy
owner's uncertain-value classification in the parser.

Assign the hook's `CFG_*` variables only after both layers pass. On failure, a
normal hook reports stderr and defers; a tagged explorer emits a denial. The
launcher reports failure before creating a worktree or launching Claude.

## Management interface

`bin/greenlight-config.sh` shares the reader. Exit 0 means success, 1 operational
failure, and 2 invalid arguments. `status` returns `ok` and `settings`; each
setting carries string `value`, string `default`, `source` (`user` or `bundled`),
and boolean `pinned`. `get KEY` prints the effective value. Successful mutations
return `{ok:true,backup:null}` or a reset backup path.

| Operation | Meaning |
|---|---|
| `set KEY VALUE` | Upsert only the requested pin |
| `unset KEY...` | Remove selected pins, inheriting live defaults |
| `add/remove LIST TOKEN` | Modify effective disabled modes or custom commands |
| `reset` | Back up and empty an existing file; absent file is already reset |

Validate arguments before writes, take an exclusive `.config.lock` directory
without waiting, and re-read under the lock. Contention or an abandoned lock is
a visible failure; do not steal ownership. Only the owning writer removes its
lock and temporary file. Inherited environment variables cannot establish
ownership. Manual editors must coordinate separately; this is not a hostile-user
filesystem boundary.

Write a same-directory temporary under umask 077, validate it, atomically replace
the user file, and release the lock before reporting success. Retain unrelated
lines, including comments and unknown keys; terminate rewritten lines with a
newline. Refuse mutation through symlink configuration paths. Reset makes a
unique adjacent backup before replacement. Invalid or unreadable configurations
must be corrected before management mutations. Backup and cleanup failures must
be visible, not successful-looking partial operations.

The `/greenlight` skill routes all configuration operations to the helper, shows
effective status, and reads the effective log path. It never copies the bundle
or carries an inline defaults snapshot. `unset ai_enabled ai_model
ai_show_rationale` is the selective migration for the original stale-AI case;
`reset` is the complete migration. Existing files do not migrate automatically.

## Validation and delivery

New Bats regressions drive production hooks and management entrypoints with
isolated homes and plugin fixtures under `/tmp`. The unchanged hook failed both
first-use non-mutation and bundle-only upgrade checks; the planned management
surface was absent. The initial 15 regression methods failed before the repair
and passed afterward. Additional writer tests cover ownership and real concurrent
processes. Existing manifest tests now identify the chosen bundle through its
effective decision-log path, rather than requiring a copied file.

Run new tests red→green and the directly impacted Greenlight suite via
`TMPDIR=/tmp bash tests/with-isolated-store.sh bash plugins/greenlight/tests/run-tests.sh`.
Run shell syntax, entrypoint ShellCheck with sourced libraries, and whitespace
checks. Explorer integration is a separate fix commit with its own regression.
Final results are recorded on AGE-52. The centralized verifier owns the full
repository suite, publication, merge, completion, and cleanup. No version,
release, or installed user configuration changes occur in this worktree.
