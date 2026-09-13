# AGE-39: Marker accountability

## Problem and evidence

The marker collector searched raw lines, so quoted examples could suppress
actual violations and become stale themselves. The stale classifier exempted
all command-slot placeholders to avoid those false findings. An applied `<id>`
annotation could therefore silently do nothing.

Six regression fixtures failed against unchanged production code: expired
placeholder categories were absent; quoted examples suppressed violations;
adjacent examples contaminated the real reason; post-fence quoted examples
became stale; unmatched delimiters and empty/non-angle markers escaped accounting.
A seventh fixture proved that an active final-line marker is accounted for without
a final newline; it also failed against the original source.

## Contract

- `read_document` supplies numbered command units or marker-visible lines.
  Both modes use one fence recognizer; command extraction remains unchanged.
- Outside fences, a complete same-line backtick span quotes its marker contents.
  Runs must match in length; unmatched runs remain literal. Backslash escapes
  apply outside spans, not inside them. This uses the delimiter rules from
  [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/#code-spans), without
  claiming full Markdown parsing or multiline span support.
- Actual HTML comments are atomic during quotation filtering. Backticks in an
  annotation reason must not quote neighboring text. Removed spans leave a
  separator to prevent accidental marker construction.
- Fenced annotations remain active, including indented/list and nested fences.
- Only the exact `<token>` convention signature is exempt from staleness.
  All other tokens, including placeholders, either suppress an exact finding
  or enter an existing stale category. Missing token/reason remains malformed.
- CLI arguments, JSON schema, exit behavior, vocabulary rules, command scanning,
  marker syntax/cardinality and version 3.9.1 remain unchanged.

## Verification and limits

The regression fixtures explicitly specify applied annotation counts, tokens,
line numbers, reasons and stale kinds. They do not derive expectations from the
production collector. Existing real-corpus accounting remains independent.

Run the contract Bats file and root instruction contract suite through
`tests/with-isolated-store.sh` with `TMPDIR=/tmp`, plus syntax, ShellCheck and
whitespace checks. Disposable mutation copies must prove restoring either the
broad exemption or raw collection fails the relevant new tests; a baseline copy
must pass first.

AGE-37 still owns the separate no-command diagnostic issue. This change does
not alter when SCANNED_LINES is populated. Full Markdown parsing, multiline
annotations and changes to marker cardinality are outside this repair.

Central verification owns the full suite, submission, merge and completion.

## Recorded validation

| Check | Result |
|---|---|
| Contract Bats file | 96/96 pass; subsequently added EOF case 1/1 pass |
| Root instruction contract | 9/9 pass |
| Original source | All seven new cases fail |
| Disposable fixed baseline | 6/6 pass |
| Restore broad placeholder exemption | Three stale-accounting tests fail; quotation tests stay green |
| Restore raw marker collection | Three quotation tests fail |
| Remove span separator | EOF/boundary case fails on an invented marker |
| Old/new command extraction | Byte-identical on all 189 pre-existing tracked Markdown files |
| Bash syntax, ShellCheck warning/error level, whitespace | Pass |

Only new and directly impacted tests ran. The full repository suite remains
central verification responsibility.
