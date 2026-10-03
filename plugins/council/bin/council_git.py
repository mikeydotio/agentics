"""Cache Git interpretation only while its underlying metadata bytes agree."""
import hashlib
import os
from pathlib import Path
import re
import stat

_CACHE = {}


def observation(identity, previous=None):
    """Read semantic HEAD/index, using content evidence rather than stat shortcuts."""
    from council_inventory import git, read_evidence, repository
    guard = metadata_digest(identity)
    cached = previous or _CACHE.get(identity["root"])
    if cached and guard.startswith("files:") and cached.get("guard") == guard:
        return cached
    if repository(identity["root"], refresh=True) != identity:
        raise ValueError("repository identity changed")
    index = {}
    for record in git(identity["root"], "ls-files", "--stage", "-z").split(b"\0"):
        if record:
            metadata, name = record.split(b"\t", 1)
            index.setdefault(os.fsdecode(name), []).append(metadata.decode("ascii").split())
    head = git(identity["root"], "rev-parse", "--revs-only", "HEAD").strip()
    if head:
        head = {"oid": head.decode("ascii")}
    else:
        head = {"unborn": os.fsdecode(git(identity["root"], "symbolic-ref", "HEAD")).rstrip("\n")}
    # Record symbolic/detached identity too, including switches to the same commit.
    head["identity"] = os.fsdecode(read_evidence(Path(identity["git_dir"]) / "HEAD")).rstrip("\n")
    if metadata_digest(identity) != guard:
        raise ValueError("Git metadata changed during capture")
    result = {"guard": guard, "head": head, "index": index}
    _CACHE[identity["root"]] = result
    return result


def metadata_digest(identity):
    """Fingerprint all supported files-backend reference and index inputs."""
    from council_inventory import canonical, directory, read_evidence, _entry
    admin = directory(identity["git_dir"])
    common_file = admin / "commondir"
    if common_file.is_symlink():
        raise ValueError("symlink Git commondir is unsupported")
    common = directory(admin / os.fsdecode(read_evidence(common_file)).rstrip("\n")) if common_file.exists() else admin
    files = {}
    includes = []

    def collect(path):
        directory(path.parent)
        fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            try:
                info = os.stat(path.name, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                files[str(path)] = None
                return
            if stat.S_ISLNK(info.st_mode):
                raise ValueError(f"symlink Git metadata is unsupported: {path}")
            entry = _entry(fd, path.name, info)
            files[str(path)] = entry
            if path.name in ("config", "config.worktree") and entry["type"] == "file":
                if re.search(rb"(?im)^\s*\[\s*include(?:if)?(?:\s|\])", read_evidence(path)):
                    includes.append(str(path))
        finally:
            os.close(fd)
        if entry["type"] == "directory":
            for child in sorted(path.iterdir()):
                collect(child)

    marker = Path(identity["root"]) / ".git"
    if marker.is_symlink():
        raise ValueError("symlink Git administrative entry is unsupported")
    if marker.is_file():
        collect(marker)
    elif not marker.is_dir():
        raise ValueError("Git administrative entry disappeared")
    for base in sorted({admin, common}):
        if (base / "reftable").exists():
            raise ValueError("reftable reference storage is not supported")
        for name in ("HEAD", "index", "commondir", "gitdir", "config", "config.worktree",
                     "packed-refs", "refs", "shallow"):
            collect(base / name)
        for path in sorted(base.glob("sharedindex.*")):
            collect(path)
    prefix = "uncached:" if includes else "files:"
    return prefix + hashlib.sha256(canonical(files).encode()).hexdigest()
