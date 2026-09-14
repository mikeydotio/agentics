# AGE-66: Prototype preservation and reconciliation

## Decision and scope

Retain `.claude/worktrees/dual-host-plugin-compatibility` and branch
`codex/dual-host-plugin-compatibility`. Preserve the entire filesystem payload
locally, prove independent recovery, and accept remaining unique material as
archival reference under AGE-66. This decision authorizes neither deletion nor
runtime porting. No prototype code was imported into shipped plugins.

The defect was a preservation gap: a merged branch tip does not contain dirty
files. AGE-61 explicitly left this prototype for AGE-66. Subsequent ports did
not establish that its files, binary database, and untracked designs were safe
to discard. The recovery utility and its round-trip tests address that class.

## Dated inventory and recovery

| Evidence | Value |
|---|---|
| Inventory date | 2026-09-14T18:58:02.467497Z |
| Prototype base | `bf4d47e61eaf0dc8839f5aceab58d65b2db3c77d` |
| Reconciliation baseline | fetched `origin/main`, `a0952cea61e0ba5c66870995db9c341f2bc3c4ac` |
| Tracked modifications | 69; no staged content changes |
| Untracked paths | 243 |
| Ignored paths | one: historical tracker lock |
| Filesystem inventory | 899 entries: 636 regular files, 262 directories including root, one symlink |
| Modes | 522 entries at `0644`; 377 at `0755` |
| Other metadata | owner 501, group 20; no ACL entries or file flags; provenance xattr on all entries |
| Concurrent users | `lsof -nP +D` returned no open files before and after capture |
| Stability | Complete filesystem and Git inventories match before and after capture |
| Archive | `/Users/mikey/.local/share/agentics/preservation/AGE-66/20260914T185750Z/` |
| Independent restore | `/private/tmp/AGE-66-prototype-final-restored/` |

The archive contains a pax tar payload, a self-contained Git bundle, complete
index and staged-blob evidence, inventories, provenance, stability evidence,
recovery scripts, and checksums. `verification.json` records the independent
recovery verdict and checksum-manifest digest. The raw archive is outside Git
and Syncthing, in a private directory. It includes historical tracker data.
The committed report contains paths, hashes, and conclusions, not private payload.

The archive's own scripts perform recovery:

```bash
python3 /Users/mikey/.local/share/agentics/preservation/AGE-66/20260914T185750Z/restore/preserve-worktree.py verify /Users/mikey/.local/share/agentics/preservation/AGE-66/20260914T185750Z /tmp/AGE-66-new-recovery
```

The destination must not exist. Verify `SHA256SUMS.json` against the digest
recorded on AGE-66 before using the archive. The utility validates each
component before extraction and leaves the first successful receipt unchanged
when another independent restore succeeds.

The original `.git` entry is excluded from the tar payload and recorded only
as provenance. Recovery creates independent Git administration from bundled
objects and saved index evidence. It does not activate the original pointer,
read shared source objects, or check out over the recovered dirty files.

Exact comparisons cover paths, bytes, ownership, modes, links, directory and
file modification times, ACLs, extended attributes, flags, Git status, staged
content, index flags, and index bytes. Inode identities and access, change, and
birth times are explicitly outside the restoration contract. Hardlink
relationships remain required. Recovery restores the original Unicode spelling
after macOS libarchive decomposes some filenames. It restores directory times
after extraction and root time after Git initialization.

An initial independent restore rejected group 0 where the source recorded
group 20. A new regression reproduced that mismatch. Explicit numeric-owner
restoration fixed it without weakening comparison. The earlier capture at
`20260914T191600Z` and disposable restore attempts remain available as local
investigation evidence; that directory name is an identifier, not its capture
time. Its provenance records the actual earlier UTC capture time.

## Requirement reconciliation

Both original design documents are preserved at their original archive paths:
`docs/plans/2026-07-19-dual-host-plugin-compatibility-design.md` and
`docs/plans/2026-07-19-dual-host-plugin-compatibility.md`.

The following table covers the design requirements and all eleven implementation
tasks. Landed owners identify concrete commits in the pinned baseline; they do
not imply that every prototype byte shipped. Ancestor checks confirm those
commits belong to the baseline. The machine-readable companion
`age-66-reconciliation.json` covers all 313 modified, untracked, and ignored
paths with content hashes, classifications, and current-path evidence.

| Requirement / original task | Classification and landed evidence | Remaining difference and disposition |
|---|---|---|
| Goal, baseline, design approval; task 1 | Still unique/useful: both documents survive only in the prototype | Accept both as historical design evidence. Their old approval does not authorize executing their release, cleanup, or tracker instructions. |
| Eleven-plugin packaging, marketplace order, interface metadata; task 2 | Partial delivery: AGE-87 `c258847`, AGE-88 `7ebf1db`, AGE-89 `c7f9160`, AGE-93 `3608756`, AGE-94 `7658dd5` provide five Codex manifests | The separate `.agents/plugins/marketplace.json`, six further native manifests, and temporary cachebuster helper remain unique. Archive them without claiming all eleven native ports exist. No MCP/app assets were proposed or added. |
| Version synchronization and runtime-byte coverage; task 2 | Superseded in part: current sync supports Claude/Codex manifests; AGE-84 `3be7626` separates candidate and release validation | Preserve the prototype's extra marketplace synchronization and guards as reference. Current release identities and validation policy remain authoritative. |
| Strict root dispatchers, unchanged Claude trees, Codex tools and resource paths; task 3 | Delivered for the five ported plugins by the commits above | The six other native instruction trees remain unique. Current dispatchers select host identity explicitly; the prototype's older assumptions are not imported. Shared references can replace duplicate files. |
| Hook fields, roots, serialization, matchers and optional-state failure; task 4 | Freshen AGE-87/90/96/100: `c258847`, `d1af5d2`, `38184a2`, `604db96`; Semver AGE-91/95: `7b7f277`, `e63a250`; Greenlight AGE-103: `2b5e20c`, `66fe644`; Forge AGE-94: `7658dd5` | Newer adapters supersede those prototype implementations. Hook Guard's Codex adapter and some instruction surfaces remain unique. Optional-hook tolerance does not replace active-workflow integrity checks. |
| Agents native execution, bundled roles, prompt-only restrictions; task 5 | AGE-88 `7ebf1db`; later bounded delivery AGE-104 `8389404`, `131857a` | Current validated role resolution and durable delivery supersede the prototype. Preserve original role copies and design rationale; do not restore unbounded waits. |
| Council three blind members, retry, deliberation, IRV, chair tie and audit trail; task 5 | AGE-89 `c7f9160`; AGE-81 `e9f6c80`; AGE-105 `4a3f453` | Current state-backed liveness and cross-process clocks supersede the earlier protocol. Exact shared voting reference bytes remain delivered. |
| Freshen reset readiness, deferred submission, manual non-CLI continuation; task 6 | AGE-87 `c258847`, then AGE-96 `38184a2` and AGE-100 `604db96` | The later reset handshake and abandoned-marker expiry supersede prototype timing assumptions. This audit did not run a live host or certify IDE/desktop behavior. |
| Issue host selection, owned worktrees, Codex launch and submission; task 6 | Still unique/useful: landed AGE-83 `d6ad2de`, `76bfdb2`, `6f1ec3c` hardens Claude readiness, but current Issue lacks the prototype's native Codex host path | Archive the host-specific dispatch design, code, fake tmux changes, and tests. Current StoryHook dispatch is external to this prototype reconciliation; no Issue port is claimed. |
| Greenlight shared decision logic and ephemeral Codex explorer; task 7 | Greenlight output/config repairs landed in AGE-103/52/54: `66fe644`, `b11d800`, `2945d86` | The prototype's engine extraction and native Codex explorer remain useful design evidence. Current exploration still launches Claude. Any later port must retain current permission policy rather than copy old blanket approvals. |
| Hook Guard unordered-hook safety and loop breakers; task 7 | Still unique/useful: current Hook Guard manifest command still names `CLAUDE_PLUGIN_ROOT` | Archive the Codex hook serializer, dispatcher, skill and tests. Legacy installation compatibility is not proof of native hook parity. |
| Deployit host-aware Semver discovery and forwarding; task 8 | Still unique/useful: current `_find_semver_cli` does not include the prototype's Codex cache search; router lacks its host selector | Preserve `CODEX_HOME` lookup, `DEPLOYIT_HOST`, host-aware guidance, forwarding and the host test as reference. AGE-85 `c5e92f1`, `e1c4fd3` owns later unrelated runtime repairs, not this port. |
| Semver durable host instruction lifecycle; task 8 | Still unique/useful: current CLI lacks `--host`, `INSTRUCTION_HOST`, and the `AGENTS.md` template | Preserve selector, sentinel lifecycle, result fields, router and tests. AGE-91/95 fixed hook reachability/output only. No version operation ran in AGE-66. |
| Forge twelve steps, locks, gates, retries, integrity and handoff; task 9 | AGE-94 `7658dd5`, AGE-84 `e78bd9c`, AGE-104 `376114f` | Current native workflow supersedes prototype orchestration. Archive wording and fixtures without reinstating obsolete tracker assumptions or weaker recovery. |
| RCA eight steps, reproduction, forensics, fix approval and postmortem; task 10 | AGE-93 `3608756`, AGE-104 `cf29609` | Current port and bounded specialist delivery supersede prototype orchestration. Preserve exact shared references and remaining historical differences. |
| Reconcile PR native questions and resource resolution; task 10 | Still unique/useful: deterministic engine exists, but current skill lacks the prototype's separate Codex tree | Archive the native translation and tests. Its leased-push prose does not override this session's prohibition on force-pushing. |
| Installation docs, parity/lint fixtures, smoke flows, release; task 11 | Current five-plugin ports include their own acceptance tests; release AGE-106 `6a41a83` supersedes old version/changelog bytes | The all-eleven packaging checks, generic lint, temporary install and live tmux helpers remain archival reference. No old smoke script ran. No new live-host, IDE, desktop, version, or deployment claim is made. |
| Historical tracker database, counter and lock | Database: still unique/useful; counter and lock: generated artifacts | Preserve all bytes locally. They are historical evidence, not the active StoryHook system of record. |

### Explicit disposition

| Classification | Paths | Acceptance |
|---|---:|---|
| Already delivered | 13 | Exact matching bytes at the same path or an identified shared reference path |
| Superseded | 203 | Later owner implementations or release policy replace the role; preserve original bytes regardless |
| Still unique/useful | 95 | Accept as archival implementation/design evidence under AGE-66; no runtime delivery claim |
| Generated artifact | 2 | Preserve counter and lock bytes; do not reactivate them |
| Unresolved | 0 | Every path has an explicit archival disposition |

No material is intentionally discarded. Acceptance closes the preservation and
reconciliation obligation, not the unimplemented product capabilities described
by the historical design. The archive and this report provide concrete evidence
for any separately authorized future port. No new story is needed for retaining
that evidence, and no hidden runtime work remains assigned by this acceptance.

The 36 obviation candidates were checked against the preservation obligation.
AGE-61 explicitly created this obligation. AGE-87/88/89/93/94 and related repairs
partially overlap functionality but do not supply this archive or restoration.
The remaining candidates concern contract checks, test infrastructure, retirement,
deployment behavior, or releases. None establishes complete obviation.
The candidate IDs were AGE-39/43/45/48/50/52/54/55/56/61/62/67/69/70/81/83/84/85,
AGE-87/88/89/90/91/92/93/94/95/96/100/101/102/103/104/105/106/108.

## Utility and validation contract

`scripts/preserve-worktree.py capture SOURCE NEW_ARCHIVE` inventories and captures
a named, committed Git worktree on macOS. `verify ARCHIVE NEW_DIRECTORY` checks
the payload and reconstructs an independent repository. These are maintenance
interfaces; no plugin API or runtime behavior changes. Capture fails on observed
open source files, unsupported filesystem entries, submodule index entries,
missing objects, changing state, command diagnostics, or existing destinations.
Detached/unborn sources are not supported by this named-branch workflow.

The utility disables optional Git locks, fsmonitor, diff auto-refresh, global
configuration, and source hooks. It preserves the raw index, index flags,
shared-index dependencies, and all staged blobs. Filesystem copying never
dereferences symlinks. Failures preserve partial evidence without a successful
verification receipt. The capture is a stability-checked offline copy, not an
atomic filesystem snapshot; open-file checks cannot prove future writer absence.
The original worktree remains retained.

| Final archive evidence | SHA-256 |
|---|---|
| Checksum manifest | `88212688205e4dbf2b30e5f685aac5938ae533eca1945dc8edf20da59110c73f` |
| Verification receipt | `921ea678da7b40a09379fe42d8f5041132ba6992ffbd292f4653da6dccf71936` |
| Filesystem payload | `96aef4c269985be2a379d70158900cfd48bdce3287d668a4edfaebdab6702523` |
| Git bundle | `651c68d3f0bd44b3b9b827bee3521ef2fe2b7d841904baa792622f0220c52d74` |
| Filesystem inventory | `e42ab1b03e6c2fdd588498e09f3720f9952216b06645d4004b7ffa84ed875775` |

The dedicated Make target uses the existing isolated-store wrapper. Fixtures
exercise actual Git and tar operations, including independently running recovery
scripts from inside the archive after making the source unavailable. Coverage
includes staged-only binary objects, dirty and deleted files, untracked and
ignored files, Unicode/newline names, symlinks, hardlinks, modes, ACLs, xattrs,
flags, numeric ownership, exact timestamps, linked worktrees, split indexes,
repeated recovery, corruption, missing objects, open files, concurrent edits,
destination collisions, and mismatched restoration evidence.

Only the new target and directly impacted store-isolation, gate-integrity,
version-pin, and gate-orchestration tests run locally. Central verification owns
the full suite and submission. Shell syntax, warning-level ShellCheck, Python
syntax, coverage-map validation, and whitespace checks accompany these tests.

| Measured local validation | Result |
|---|---|
| Initial stub recovery tests | Four expected failures before implementation |
| Ownership regression before repair | Failed on source group 20 versus restored group 0 |
| `make test-worktree-preservation` | 13 tests pass |
| `make test-store-isolation` | Pass |
| `make test-gate-integrity` | 5 tests pass |
| `make test-storyhook-version-pin` | 28 tests pass |
| `make test-gate-receipt` | 8 orchestration tests pass; no external writer supplied |
| Real archive's bundled recovery scripts | Pass: 899 entries and independent Git state |
| Reconciliation data validation | 313 unique paths; exact inventory/status coverage and matching hashes; 13 exact landed matches verified |
| Syntax, docstrings, ShellCheck and whitespace | Pass |

The new target and its regressions are committed in `f755fb8`. No full-suite,
publication, version, deployment, original-worktree cleanup, or branch deletion
operation ran. Configuration review found ordinary project/version settings;
credential-signature scanning found no hits in the changed paths. These checks
do not certify the historical database for publication; its bytes remain private.
