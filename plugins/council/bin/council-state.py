#!/usr/bin/env python3
"""Run one Council state command using JSON stdin and structured JSON output."""
import argparse
import json
import sys

from council_store import execute
from council_validation import loads


def main():
    """Report contextual failures without disguising incomplete state updates."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "begin-phase", "record", "advance",
                                            "status", "recover", "finish"))
    parser.add_argument("directory", help="absolute council artifact directory")
    args = parser.parse_args()
    try:
        data = {} if args.command == "status" else loads(sys.stdin.read())
        result = execute(args.directory, args.command, data)
    except (OSError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc), "command": args.command,
                          "directory": args.directory,
                          "display": f"Council {args.command} failed at {args.directory}: {exc}. "
                                     "Preserve artifacts; inspect status before retrying."}))
        return 1
    print(json.dumps(result, allow_nan=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
