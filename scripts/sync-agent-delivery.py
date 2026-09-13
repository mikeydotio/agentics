#!/usr/bin/env python3
"""Synchronize bundled delivery modules from Agents; --check never modifies files."""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = ("bin/agent-delivery.py", "bin/delivery_model.py", "bin/delivery_store.py", "bin/delivery_validation.py", "references/delivery.md")


def main():
    """Keep independently installed consumers on exactly one implementation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    failures = []
    for owner in ("forge", "rca"):
        for name in FILES:
            source = ROOT / "plugins/agents" / name
            target = ROOT / "plugins" / owner / name
            expected = source.read_bytes()
            actual = target.read_bytes() if target.exists() else None
            if actual != expected:
                if args.check:
                    failures.append(str(target.relative_to(ROOT)))
                else:
                    target.write_bytes(expected)
    if failures:
        print("Delivery copies differ; run scripts/sync-agent-delivery.py:\n" + "\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
