#!/usr/bin/env python3
"""Preserve a dirty worktree locally and verify independent recovery."""
import argparse
import base64
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import unicodedata

from preservation_metadata import compare, digest, inventory, open_files, run


def restore_names_and_directory_times(root, manifest):
    """Reverse libarchive's Unicode decomposition and restore directory timestamps."""
    for name in sorted(manifest, key=lambda value: (len(Path(value).parts), value)):
        if name == ".":
            continue
        expected = root / name
        names = os.listdir(expected.parent)
        if expected.name not in names:
            matches = [n for n in names if unicodedata.normalize("NFC", n)
                       == unicodedata.normalize("NFC", expected.name)]
            if len(matches) != 1:
                raise RuntimeError(f"cannot restore exact archive filename: {name!r}")
            # APFS can treat these names as the same lookup while retaining spelling.
            # A temporary distinct name forces the original recorded spelling.
            temporary = expected.parent / ".age66-rename"
            if temporary.exists() or temporary.is_symlink():
                raise RuntimeError(f"rename collision: {temporary}")
            (expected.parent / matches[0]).rename(temporary)
            temporary.rename(expected)
    for name, entry in manifest.items():
        if entry["type"] == "directory":
            os.utime(root / name, ns=(entry["mtime_ns"], entry["mtime_ns"]))


def git(root, *args, data=None):
    """Use explicit Git roots without optional index writes or user hooks."""
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_OPTIONAL_LOCKS="0", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
               GIT_TERMINAL_PROMPT="0", LC_ALL="C")
    return run(["git", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
                "-c", "diff.autoRefreshIndex=false",
                "-C", root, *args], data=data, env=env)


def write_json(path, value):
    """Write private evidence exclusively, never replace existing evidence."""
    with Path(path).open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, ensure_ascii=True)
        stream.write("\n")


def git_state(root):
    """Capture tracked state and all staged blob bytes independently of history."""
    state = {}
    for name, args in {
        "head": ("rev-parse", "HEAD"), "branch": ("symbolic-ref", "HEAD"),
        "status": ("status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored"),
        "stages": ("ls-files", "--stage", "-z"),
        "flags": ("ls-files", "-v", "-z"),
        "unstaged": ("diff", "--binary", "--no-ext-diff", "--no-textconv"),
        "staged": ("diff", "--cached", "--binary", "--no-ext-diff", "--no-textconv"),
        "ignored": ("ls-files", "--others", "--ignored", "--exclude-standard", "-z"),
        "untracked": ("ls-files", "--others", "--exclude-standard", "-z"),
    }.items():
        state[name] = base64.b64encode(git(root, *args)).decode()
    index = Path(os.fsdecode(git(root, "rev-parse", "--git-path", "index")).strip())
    if not index.is_absolute():
        index = root / index
    state["index"] = base64.b64encode(index.read_bytes()).decode()
    shared = os.fsdecode(git(root, "rev-parse", "--shared-index-path")).strip()
    state["shared_index"] = None
    if shared:
        shared_path = Path(shared) if Path(shared).is_absolute() else root / shared
        state["shared_index"] = {"name": shared_path.name,
                                 "bytes": base64.b64encode(shared_path.read_bytes()).decode()}
    blobs = {}
    for entry in base64.b64decode(state["stages"]).split(b"\0"):
        if entry:
            mode, oid, _ = entry.split(b"\t", 1)[0].split()
            if mode == b"160000":
                raise RuntimeError("submodule index entries require a separate repository archive")
            key = oid.decode()
            if key not in blobs:
                blobs[key] = base64.b64encode(git(root, "cat-file", "blob", key)).decode()
    state["blobs"] = blobs
    return state


def capture(source, destination):
    """Capture stable filesystem and Git state; never claim recovery from capture alone."""
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if source == destination or source in destination.parents:
        raise RuntimeError("archive destination must be outside the source")
    if destination.exists():
        raise RuntimeError(f"archive destination already exists: {destination}")
    if Path(os.fsdecode(git(source, "rev-parse", "--show-toplevel")).strip()).resolve() != source:
        raise RuntimeError("source must be the worktree root")
    before_open = open_files(source)
    before = inventory(source)
    state = git_state(source)
    destination.mkdir(mode=0o700)
    write_json(destination / "inventory.json", before)
    write_json(destination / "git.json", state)
    pointer = source / ".git"
    write_json(destination / "provenance.json", {
        "source": str(source), "captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "git_pointer": pointer.read_text() if pointer.is_file() else "standalone .git directory excluded",
        "before_open_files": before_open,
        "metadata_exceptions": ["inode numbers", "ctime", "atime", "birthtime"],
    })
    names = b"\0".join(os.fsencode(n) for n in before) + b"\0"
    run(["/usr/bin/tar", "-cf", destination / "payload.tar", "--format=pax",
         "--acls", "--xattrs", "--fflags", "--mac-metadata", "--no-recursion",
         "--null", "-C", source, "-T", "-"], data=names)
    branch = base64.b64decode(state["branch"]).decode().strip()
    git(source, "bundle", "create", "--quiet", destination / "history.bundle", branch)
    compare(before, inventory(source), "source changed during capture")
    compare(state, git_state(source), "Git state changed during capture")
    write_json(destination / "stability.json", {"after_open_files": open_files(source), "stable": True})
    (destination / "restore").mkdir(mode=0o700)
    for name in ("preserve-worktree.py", "preservation_metadata.py"):
        (destination / "restore" / name).write_bytes((Path(__file__).parent / name).read_bytes())
    (destination / "RESTORE.txt").write_text(
        "Private AGE-66 evidence. Do not publish without reviewing local configuration and historical state.\n"
        "Run: python3 ARCHIVE/restore/preserve-worktree.py verify ARCHIVE NEW_DIRECTORY\n"
        "Use a new directory on this macOS filesystem. The source repository is not required.\n"
        "The verifier checks checksums before extraction and compares filesystem and Git evidence.\n"
        "The original .git pointer is provenance only. Never install it in a restored tree.\n"
        "Inode identities, access/change/birth times are not restoration invariants.\n")
    write_json(destination / "SHA256SUMS.json", {str(p.relative_to(destination)): digest(p)
                                               for p in sorted(destination.rglob("*")) if p.is_file()})
    return {"captured": True, "verified": False, "archive": str(destination)}


def verify(archive, destination):
    """Restore into an independent repository and compare every recorded invariant."""
    archive, destination = Path(archive).resolve(), Path(destination).resolve()
    if destination.exists():
        raise RuntimeError(f"restore destination already exists: {destination}")
    if archive == destination or archive in destination.parents:
        raise RuntimeError("restore destination must be outside the archive")
    sums = json.loads((archive / "SHA256SUMS.json").read_text())
    expected_names = {"inventory.json", "git.json", "provenance.json", "payload.tar", "history.bundle",
                      "stability.json", "RESTORE.txt", "restore/preserve-worktree.py",
                      "restore/preservation_metadata.py"}
    if set(sums) != expected_names:
        raise RuntimeError("invalid archive component census")
    for name, expected in sums.items():
        if (archive / name).is_symlink() or digest(archive / name) != expected:
            raise RuntimeError(f"archive checksum mismatch: {name}")
    manifest = json.loads((archive / "inventory.json").read_text())
    state = json.loads((archive / "git.json").read_text())
    # Metadata records emitted by macOS tar are handled by bsdtar itself.
    # Reject paths that could escape the new root or write Git administration.
    with tarfile.open(archive / "payload.tar") as stream:
        for item in stream:
            path = Path(item.name)
            if path.is_absolute() or ".." in path.parts or (path.parts and path.parts[0] == ".git"):
                raise RuntimeError(f"unsafe archive member: {item.name!r}")
            if item.islnk() and (Path(item.linkname).is_absolute() or ".." in Path(item.linkname).parts):
                raise RuntimeError(f"unsafe archive hardlink: {item.linkname!r}")
    destination.mkdir(mode=0o700)
    run(["/usr/bin/tar", "-xpf", archive / "payload.tar", "--acls", "--xattrs",
         "--fflags", "--mac-metadata", "--same-owner", "--numeric-owner", "-C", destination])
    restore_names_and_directory_times(destination, manifest)
    compare(manifest, inventory(destination), "filesystem restoration mismatch")
    git(destination, "init", "--quiet", "--template=", "-b", "age66-restore")
    git(destination, "bundle", "unbundle", archive / "history.bundle")
    branch = base64.b64decode(state["branch"]).decode().strip()
    head = base64.b64decode(state["head"]).decode().strip()
    git(destination, "update-ref", branch, head)
    git(destination, "symbolic-ref", "HEAD", branch)
    for oid, content in state["blobs"].items():
        restored_oid = git(destination, "hash-object", "-w", "--stdin", data=base64.b64decode(content)).decode().strip()
        if restored_oid != oid:
            raise RuntimeError(f"staged object identity mismatch: {oid}")
    (destination / ".git/index").write_bytes(base64.b64decode(state["index"]))
    if state["shared_index"]:
        shared = state["shared_index"]
        if Path(shared["name"]).name != shared["name"] or not shared["name"].startswith("sharedindex."):
            raise RuntimeError("invalid shared index name")
        (destination / ".git" / shared["name"]).write_bytes(base64.b64decode(shared["bytes"]))
    compare(state, git_state(destination), "Git restoration mismatch")
    # Creating Git administration changes only the root directory timestamp.
    os.utime(destination, ns=(manifest["."]["mtime_ns"], manifest["."]["mtime_ns"]))
    compare(manifest, inventory(destination), "post-Git filesystem mismatch")
    result = {"verified": True, "restored": str(destination), "entries": len(manifest),
              "checksums_sha256": digest(archive / "SHA256SUMS.json")}
    receipt = archive / "verification.json"
    if not receipt.exists():
        write_json(receipt, result)
    return result


def main():
    """Expose capture and verify without modifying the source worktree."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("capture", "verify"))
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()
    try:
        if sys.platform != "darwin":
            raise RuntimeError("this preservation workflow requires macOS bsdtar and metadata interfaces")
        result = (capture if args.command == "capture" else verify)(args.source, args.destination)
        print(json.dumps(result))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, tarfile.TarError) as error:
        print(f"preservation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
