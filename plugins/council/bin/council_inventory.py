"""Read repository inputs without following links or changing Git state."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess

_REPOSITORIES = {}


def canonical(value):
    """Encode filesystem surrogate escapes losslessly in deterministic JSON."""
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def git(root, *args):
    """Read the selected worktree, preserving only alternate object lookup."""
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("GIT_") or k == "GIT_ALTERNATE_OBJECT_DIRECTORIES"}
    env.update(GIT_OPTIONAL_LOCKS="0", GIT_CONFIG_NOSYSTEM="1",
               GIT_CONFIG_GLOBAL=os.devnull, LC_ALL="C")
    try:
        result = subprocess.run(["git", "-C", str(root), *args], env=env,
                                capture_output=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError(f"Git read failed at {root}: {args!r}: {exc}") from exc
    if result.returncode:
        raise ValueError(f"Git read failed at {root}: {args!r}: "
                         f"exit {result.returncode}: {os.fsdecode(result.stderr)}")
    return result.stdout


def directory(path):
    """Resolve a directory while refusing symlinks in its existing path."""
    path = Path(os.path.abspath(path))
    # /tmp is a platform alias on macOS, not a user-controlled redirect.
    if str(path).startswith("/tmp/"):
        path = Path("/tmp").resolve() / path.relative_to("/tmp")
    for parent in reversed((path, *path.parents)):
        if parent.is_symlink():
            raise ValueError(f"refusing symlink directory component: {parent}")
        if parent.exists() and not parent.is_dir():
            raise ValueError(f"expected directory: {parent}")
    return path


def repository(path, refresh=False):
    """Bind an invocation directory to its real Git worktree and administration."""
    root = directory(path)
    if not refresh and str(root) in _REPOSITORIES:
        return _REPOSITORIES[str(root)]
    top = directory(os.fsdecode(git(root, "rev-parse", "--show-toplevel"))[:-1])
    admin = os.fsdecode(git(top, "rev-parse", "--absolute-git-dir"))[:-1]
    result = {"root": str(top), "git_dir": admin}
    _REPOSITORIES[str(root)] = result
    return result


def _signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_evidence(path):
    """Read a regular evidence file without following links or waiting on a FIFO."""
    directory(path.parent)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f"evidence must be a regular file: {path}")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read()
        if (_signature(before) != _signature(os.fstat(fd))
                or _signature(before) != _signature(path.lstat())):
            raise ValueError(f"evidence changed during read: {path}")
        return raw
    finally:
        os.close(fd)


def _entry(fd, name, info):
    entry = {"mode": info.st_mode & 0o111}
    if stat.S_ISLNK(info.st_mode):
        entry.update(type="symlink", target=os.readlink(name, dir_fd=fd))
    elif stat.S_ISREG(info.st_mode):
        opened = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        try:
            if _signature(os.fstat(opened)) != _signature(info):
                raise ValueError(f"file changed before read: {name!r}")
            digest = hashlib.sha256()
            with os.fdopen(opened, "rb", closefd=False) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            if _signature(os.fstat(opened)) != _signature(info):
                raise ValueError(f"file changed during read: {name!r}")
            entry.update(type="file", size=info.st_size, sha256=digest.hexdigest())
        finally:
            os.close(opened)
    elif stat.S_ISDIR(info.st_mode):
        entry["type"] = "directory"
    else:
        raise ValueError(f"unsupported filesystem entry: {name!r}")
    if _signature(os.stat(name, dir_fd=fd, follow_symlinks=False)) != _signature(info):
        raise ValueError(f"entry changed during read: {name!r}")
    return entry


def inventory(identity, sitting, artifacts, scratch, previous=None):
    """Fingerprint all files, with explicit administrative and owned exclusions."""
    root = directory(identity["root"])
    from council_git import observation, metadata_digest
    observed = observation(identity, previous)
    index = observed["index"]
    gitlinks = {name for name, rows in index.items() if any(x[0] == "160000" for x in rows)}
    sitting = directory(sitting)
    try:
        relative = sitting.relative_to(root).as_posix()
    except ValueError:
        relative = None
    ignored_files = {f"{relative}/{name}" for name in artifacts} if relative else set()
    ignored_dirs = {f"{relative}/scratch/{name}" for name in scratch} if relative else set()
    for path in index:
        if path in ignored_files or any(path == d or path.startswith(d + "/") for d in ignored_dirs):
            raise ValueError(f"tracked path overlaps owned Council output: {path!r}")
    entries, excluded = {}, []
    root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)

    def walk(fd, prefix):
        for name in sorted(os.listdir(fd)):
            path = f"{prefix}/{name}" if prefix else name
            if not prefix and name == ".git":
                continue
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if path in ignored_files:
                if not stat.S_ISREG(info.st_mode):
                    raise ValueError(f"owned artifact is not a regular file: {path!r}")
                continue
            if path in ignored_dirs:
                if not stat.S_ISDIR(info.st_mode):
                    raise ValueError(f"owned scratch is not a directory: {path!r}")
                continue
            entry = _entry(fd, name, info)
            entries[path] = entry
            if entry["type"] == "directory":
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    if (os.fstat(child).st_dev, os.fstat(child).st_ino) != (info.st_dev, info.st_ino):
                        raise ValueError(f"directory changed during read: {path!r}")
                    if path in gitlinks or ".git" in os.listdir(child):
                        excluded.append({"path": path, "reason": "nested repository interior"})
                    else:
                        walk(child, path)
                finally:
                    os.close(child)
    try:
        walk(root_fd, "")
    finally:
        os.close(root_fd)
    for path in index:
        if path not in entries:
            entries[path] = {"type": "missing"}
    if metadata_digest(identity) != observed["guard"]:
        raise ValueError("Git metadata changed during inventory")
    return {"head": observed["head"], "index": index, "entries": entries,
            "excluded": excluded, "git_observation": observed}


def stable_inventory(identity, sitting, artifacts, scratch, previous=None):
    """Reject evidence observed to change during either complete traversal."""
    first = inventory(identity, sitting, artifacts, scratch, previous)
    second = inventory(identity, sitting, artifacts, scratch, first["git_observation"])
    if first != second:
        raise ValueError("repository inputs changed during integrity capture")
    return second
