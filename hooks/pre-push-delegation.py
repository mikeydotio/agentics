"""Prove a bounded command has a repository-owned Git push gate (SH-681).

This is a conservative delegation probe, not AGE-63's general shell parser.
Unknown syntax declines delegation; the caller retains its existing test gate.
The input is tokenized, never evaluated. Install beside pre-push-tests.sh.
"""

import os
from pathlib import Path
import shlex
import subprocess
import sys


def target(command):
    """Return a known cwd and Git config prefix, or decline unsupported syntax."""
    if any(char in command for char in "$`~*?[]\\"):
        raise ValueError("shell expansion or escape is outside the delegation grammar")
    lexer = shlex.shlex(command.strip(), posix=True, punctuation_chars=";&|()<>\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    words = list(lexer)
    cwd = Path.cwd()
    if words[:1] == ["cd"]:
        if os.environ.get("CDPATH"):
            raise ValueError("CDPATH makes the leading cd target ambiguous")
        end = 3 if words[1:2] == ["--"] else 2
        if len(words) <= end or words[end] != "&&":
            raise ValueError("only a single leading cd followed by && is supported")
        cwd = (cwd / words[end - 1]).resolve(strict=True)
        words = words[end + 1:]
    if not words or any(word and all(c in ";&|()<>\n" for c in word) for word in words):
        raise ValueError("compound commands and redirects cannot delegate")
    config = []
    if words[0] == "git":
        i = 1
        while i < len(words) and words[i].startswith("-"):
            option = words[i]
            if option not in ("-C", "-c") or i + 1 >= len(words):
                raise ValueError("unsupported Git global option")
            value = words[i + 1]
            if option == "-C":
                cwd = (cwd / value).resolve(strict=True)
            else:
                key = value.partition("=")[0].lower()
                if key != "core.hookspath" and not (key.startswith("url.") and key.endswith(".insteadof")):
                    raise ValueError("Git configuration override cannot be safely delegated")
                config.extend(("-c", value))
            i += 2
        if i >= len(words) or words[i] not in ("push", "commit"):
            raise ValueError("unsupported Git command")
    elif words[0] not in ("echo", "printf") and words[:2] != ["story", "comment"]:
        raise ValueError("command target is not known")
    return cwd, config


def git(cwd, config, *args):
    """Read Git's own interpretation with fixed argv and a bounded subprocess."""
    result = subprocess.run(["git", "-C", str(cwd), *config, *args],
                            check=True, capture_output=True, text=True, timeout=3)
    return result.stdout.rstrip("\n")


def delegated_root(command):
    """Return the checkout only when Git selects its tracked executable hook."""
    cwd, config = target(command)
    root = Path(git(cwd, config, "rev-parse", "--show-toplevel")).resolve(strict=True)
    # Git invokes pre-push from the worktree root, including when the caller
    # starts in a subdirectory. Resolve relative core.hooksPath there.
    selected = Path(git(root, config, "rev-parse", "--path-format=absolute", "--git-path", "hooks/pre-push"))
    hook = selected.resolve(strict=True)
    relative = hook.relative_to(root)
    if not hook.is_file() or not os.access(hook, os.X_OK):
        raise ValueError("the selected repository hook is not executable")
    # Reject external symlinks and index symlink entries. A tracked directory
    # name or an untracked file does not establish repository ownership.
    entry = git(root, config, "ls-files", "--stage", "--error-unmatch", "--", str(relative))
    if not entry.startswith("100755 ") or "\n" in entry:
        raise ValueError("the selected hook is not tracked as an executable file")
    return root


def main():
    """Print the proven checkout; all failures keep the existing global gate."""
    try:
        root = delegated_root(sys.stdin.read())
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"pre-push delegation: retaining global gate: {error}", file=sys.stderr)
        return 1
    print(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
