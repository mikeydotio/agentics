"""Invoke StoryHook under one Bats fixture's private identity and bounded stop."""
import os
from pathlib import Path
import stat
import subprocess
import sys

REMOVED = (
    "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
    "GH_CONFIG_DIR", "STORYHOOK_ACTIVITY_LOG_DIR", "STORYHOOK_ACTIVITY_CONTEXT",
    "STORYHOOK_PROJECT", "STORYHOOK_ACTOR", "STORYHOOK_FULL_AUTO", "STORYHOOK_AUTO",
    "STORYHOOK_DISPATCH", "STORYHOOK_CODEX_BOOTSTRAP", "STORYHOOK_ALLOW_TEMP_PROJECT",
    "STORYHOOK_ALLOW_PROJECT_BURST", "STORYHOOK_ALLOW_UNINSTALLED_MIGRATION",
    "STORYHOOK_ALLOW_UNINSTALLED_DAEMON", "STORYHOOK_ALLOW_UNINSTALLED_PLUGIN_INSTALL",
    "STORYHOOK_TEST_SUBPROCESS_PATIENCE_MS", "STORYHOOK_DAEMON_NOFILE", "STORYHOOK_INVOKER",
)


def main():
    """Preserve the fixture on uncertain identity or unsuccessful normal shutdown."""
    if len(sys.argv) < 5:
        print("fixture_story requires root, owner PID, executable and command", file=sys.stderr)
        return 1
    root_arg, owner, executable, *command = sys.argv[1:]
    try:
        raw_root = Path(root_arg)
        root = raw_root.resolve(strict=True)
        info = root.stat()
        if (raw_root.is_symlink() or root.parent != Path("/tmp").resolve() or
                not root.name.startswith("forge-storyhook-fixture.") or
                not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or
                stat.S_IMODE(info.st_mode) != 0o700 or not owner.isdecimal() or int(owner) <= 1 or
                not Path(executable).is_absolute() or not os.access(executable, os.X_OK) or
                (root / "owner").is_symlink() or
                (root / "owner").read_text() != owner + "\n" + executable + "\n"):
            raise ValueError("fixture ownership identity is missing or changed")
        home = root / "home"
        data, config, state = home / ".local/share", home / ".config", home / ".local/state"
        for directory in (data / "storyhook", config, state):
            directory.mkdir(parents=True, exist_ok=True)
        env = {key: value for key, value in os.environ.items()
               if key not in REMOVED and not key.startswith("GIT_")}
        env.update(HOME=str(home), XDG_DATA_HOME=str(data), XDG_CONFIG_HOME=str(config),
                   XDG_STATE_HOME=str(state), STORYHOOK_DATA_DIR=str(data / "storyhook"),
                   STORYHOOK_STORE_PATH=str(data / "storyhook/store.db"),
                   STORYHOOK_DAEMON_ADDR="127.0.0.1:0", STORYHOOK_PARENT_PID=owner,
                   STORYHOOK_PARENT_START_TIME="", STORYHOOK_VERIFIER_MIRROR="0",
                   STORYHOOK_VERIFIER_AGENT="0", STORYHOOK_TAILNET="0",
                   GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                   GIT_TEMPLATE_DIR=str(root / "templates"))
        if command != ["daemon", "stop"]:
            return subprocess.run([executable] + command, env=env, close_fds=True).returncode
        # A regular file cannot keep Bats' output pipe open through a daemon child.
        fd = os.open(str(root / "stop.log"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as log:
            try:
                return subprocess.run([executable] + command, env=env, close_fds=True,
                                      stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                      timeout=10).returncode
            except subprocess.TimeoutExpired:
                print("Normal StoryHook stop timed out after 10 seconds; fixture retained.", file=log)
                return 1
            except OSError as error:
                print("Normal StoryHook stop failed; fixture retained: %s" % error, file=log)
                return 1
    except (OSError, ValueError) as error:
        print("StoryHook fixture retained at %s: %s" % (root_arg, error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
