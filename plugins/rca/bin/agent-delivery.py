#!/usr/bin/env python3
"""Manage one batch of agent deliveries, or inspect all batches for pipeline recovery."""
import argparse
import json
import sys

from delivery_store import execute, inspect_runs
from delivery_validation import loads


def main():
    """Read structured input and preserve contextual diagnostics on failure."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "record", "advance", "status", "recover", "finish"))
    parser.add_argument("directory")
    parser.add_argument("--runs", action="store_true", help="status: inspect a directory of batches")
    args = parser.parse_args()
    try:
        if args.runs:
            if args.command != "status":
                raise ValueError("--runs is only supported by status")
            result = inspect_runs(args.directory)
        else:
            data = {} if args.command == "status" else loads(sys.stdin.read())
            result = execute(args.directory, args.command, data)
    except (OSError, ValueError) as exc:
        print(json.dumps(dict(ok=False, command=args.command, directory=args.directory,
                              error=str(exc), display=f"Delivery {args.command} failed: {exc}; "
                              "preserve evidence and inspect status before retrying")))
        return 1
    print(json.dumps(result, allow_nan=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
