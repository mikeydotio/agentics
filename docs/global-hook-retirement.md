# Global push-test hook retirement — AGE-102 / SH-682

Mikey approved complete retirement of Agentics' global test enforcement on
2026-09-11. Each repository owns its test commands and enforcement. StoryHook's
central verifier owns its full suite; publishing a feature branch must not start
another full suite through a global tool hook.

The removed hook also matched quoted command text, mislabeled cancelled tests,
and duplicated local verification. Retirement removes those execution paths
instead of adding another workflow classifier. Repository hooks and other global
hooks are independent and remain in place.

## Existing installations

From this checkout:

```sh
python3 hooks/retire-pre-push-hook.py
python3 hooks/retire-pre-push-hook.py --apply
python3 hooks/retire-pre-push-hook.py
```

The default command only inspects: exit 1 means retirement is pending, exit 0
means no active installation remains, and exit 2 names an error. `--apply`
removes direct registrations for the host's `hooks/pre-push-tests.sh` from
`~/.claude/settings.json` and `~/.codex/hooks.json`, then removes both active
script files. `--home PATH` supports fixture homes and explicit installations.

All inputs are validated before changes start. Unrecognized invocations,
duplicate JSON keys, malformed shapes, symlinks and special files are refused.
Unrelated JSON values and file permissions are preserved; changed settings are
atomically replaced. Unchanged settings are not reformatted. The utility does
not execute any hook, change Git configuration, or touch repository hooks.

Exact original settings and scripts are saved first under a unique private
`~/.local/state/agentics/retired-pre-push/` directory, printed in the result.
Earlier installer backups remain untouched. A partial failure names its backup
directory and cause; inspect those diagnostics before recovery. Repeated removal
is a no-op. Hosts that cache registrations may require a session restart before
the changed registration is observed.

The installer, global gate, and hook-only deadline were removed from the source.
The ordinary test targets, store isolation, and general timeout-capture guard
remain. Historical gate measurements in PROGRESS.md describe the retired system.

## Validation

`python3 tests/retire-pre-push-hook.py` exercises the real utility against private
homes, exact backups, settings preservation, repeat runs and refusal cases. A
real local Git remote proves that a repository-owned hook still rejects and
allows publication after retirement. No test edits live host configuration.
