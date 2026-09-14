"""Read macOS filesystem evidence without following symbolic links."""
import ctypes
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess


def run(argv, *, cwd=None, data=None, env=None):
    """Run a bounded operation and fail with command and stderr context."""
    result = subprocess.run([str(x) for x in argv], cwd=cwd, input=data, env=env,
                            capture_output=True, timeout=120)
    if result.returncode or result.stderr:
        raise RuntimeError(f"{argv!r}: exit {result.returncode}: {os.fsdecode(result.stderr)}")
    return result.stdout


def digest(path):
    """Hash all bytes of a regular file."""
    checksum = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def xattrs(path):
    """Read raw extended attributes through Darwin's no-follow interface."""
    libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    libc.listxattr.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    libc.listxattr.restype = ctypes.c_ssize_t
    libc.getxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                             ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
    libc.getxattr.restype = ctypes.c_ssize_t
    raw = os.fsencode(path)
    size = libc.listxattr(raw, None, 0, 1)
    if size < 0:
        raise OSError(ctypes.get_errno(), "listxattr", str(path))
    names = ctypes.create_string_buffer(size)
    if libc.listxattr(raw, names, size, 1) != size:
        raise RuntimeError(f"extended attributes changed while reading {path}")
    result = {}
    for name in sorted(n for n in names.raw.split(b"\0") if n):
        size = libc.getxattr(raw, name, None, 0, 0, 1)
        if size < 0:
            raise OSError(ctypes.get_errno(), "getxattr", str(path))
        value = ctypes.create_string_buffer(size)
        if libc.getxattr(raw, name, value, size, 0, 1) != size:
            raise RuntimeError(f"extended attribute changed: {path}: {name!r}")
        result[os.fsdecode(name)] = value.raw.hex()
    return result


def inventory(root):
    """Record every payload entry; omit only the root Git administrative entry."""
    root = Path(root)
    paths = [root]
    for directory, dirs, files in os.walk(root, followlinks=False):
        if Path(directory) == root:
            dirs[:] = [x for x in dirs if x != ".git"]
            files = [x for x in files if x != ".git"]
        paths.extend(Path(directory) / name for name in dirs + files)
    entries = {}
    links = {}
    for path in sorted(paths):
        relative = str(path.relative_to(root))
        info = path.lstat()
        kind = ("file" if stat.S_ISREG(info.st_mode) else
                "directory" if stat.S_ISDIR(info.st_mode) else
                "symlink" if stat.S_ISLNK(info.st_mode) else None)
        if kind is None:
            raise RuntimeError(f"unsupported filesystem entry: {path}")
        acl_output = run(["/bin/ls", "-lden", path]).decode(errors="surrogateescape")
        entry = {"type": kind, "mode": stat.S_IMODE(info.st_mode),
                 "uid": info.st_uid, "gid": info.st_gid, "mtime_ns": info.st_mtime_ns,
                 "flags": info.st_flags, "xattrs": xattrs(path),
                 "acl": [line.strip() for line in acl_output.splitlines()
                         if re.match(r"^ \d+: ", line)]}
        if kind == "file":
            entry.update(size=info.st_size, sha256=digest(path))
            links.setdefault((info.st_dev, info.st_ino), []).append(relative)
        elif kind == "symlink":
            entry["target"] = os.readlink(path)
        entries[relative] = entry
    for group in links.values():
        if len(group) > 1:
            for name in group:
                entries[name]["hardlinks"] = sorted(group)
    return entries


def compare(expected, actual, label):
    """Refuse missing, extra, or changed entries with bounded path diagnostics."""
    changed = [name for name in sorted(set(expected) | set(actual))
               if expected.get(name) != actual.get(name)]
    if changed:
        details = {name: {"expected": expected.get(name), "actual": actual.get(name)}
                   for name in changed[:5]}
        raise RuntimeError(f"{label}: {len(changed)} differences: {details!r}")


def open_files(root):
    """Fail closed on observed users of the source or inspection diagnostics."""
    result = subprocess.run(["/usr/sbin/lsof", "-nP", "+D", str(root)],
                            capture_output=True, timeout=60)
    if result.returncode != 1 or result.stdout or result.stderr:
        raise RuntimeError(f"source is open or inspection failed: {root}: "
                           f"exit {result.returncode}: {result.stdout!r} {result.stderr!r}")
    return {"command": "lsof -nP +D", "exit": 1, "open_files": []}
