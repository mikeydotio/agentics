#!/usr/bin/env python3
"""Own the deadline, output files, and cancellation of Agents identity validation."""

import json
import math
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def _group_state(pgid):
    """Observe only the child group; presence does not imply every member is live."""
    if pgid is None:
        return "not-created"
    try:
        os.killpg(pgid, 0)
        return "present"
    except ProcessLookupError:
        return "absent"
    except OSError:
        return "unknown"


def _cleanup(process, record):
    """Signal the owned group, then bound both grace and reap observations."""
    end = time.monotonic() + 0.8
    for signum, key, allowance in ((signal.SIGTERM, "term_attempted", 0.2),
                                  (signal.SIGKILL, "kill_attempted", 0.6)):
        if _group_state(process.pid) != "absent":
            record[key] = True
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass
            except OSError as error:
                record.setdefault("cleanup_errors", []).append(str(error))
        until = min(end, time.monotonic() + allowance)
        while time.monotonic() < until:
            process.poll()
            if process.returncode is not None and _group_state(process.pid) == "absent":
                break
            time.sleep(0.01)
        if process.returncode is not None and _group_state(process.pid) == "absent":
            break
    process.poll()
    record["reaped"] = process.returncode is not None
    record["group_after_cleanup"] = _group_state(process.pid)


def _snapshot(path, limit):
    """Read a finite snapshot even if an escaped writer still appends to the file."""
    try:
        with path.open("rb") as stream:
            size = os.fstat(stream.fileno()).st_size
            return stream.read(min(size, limit)), size > limit
    except FileNotFoundError:
        return b"", False


def _commit_outcome(cancellation, prepared_signal):
    """Freeze a prepared outcome at a short, I/O-free signal-mask cutoff."""
    signals = {signal.SIGINT, signal.SIGTERM}
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, signals)
    try:
        pending = signal.sigpending() & signals
        if cancellation[0] is None and pending:
            # POSIX does not preserve arrival order for coalesced pending signals.
            cancellation[0] = min(pending)
        if cancellation[0] != prepared_signal:
            return False
        cancellation[1] = True
        return True
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)


def main(argv=None):
    """Run one resolver attempt; never retry or infer permission from an exit."""
    started = time.monotonic()
    cancellation = [None, False]  # First accepted signal, outcome committed.

    def latch(signum, _frame):
        """Latch the first signal without throwing during spawn or cleanup."""
        if not cancellation[1] and cancellation[0] is None:
            cancellation[0] = signum

    signal.signal(signal.SIGINT, latch)
    signal.signal(signal.SIGTERM, latch)
    os.umask(0o077)
    try:
        evidence = Path(tempfile.mkdtemp(prefix="rca-resolver-"))
    except OSError as error:
        print(f"rca: cannot create private resolver evidence: {error}", file=sys.stderr)
        return 2
    record = dict(operation="resolve-agents-root", phase="initialization",
                  configured_deadline_seconds=None, validator_pid=None, validator_pgid=None,
                  child_status=None, reason=None, signal=None, term_attempted=False,
                  kill_attempted=False, reaped=False, group_after_cleanup="not-created",
                  detached_descendant_absence_attested=False, absence_confirmed=False,
                  success_artifact_cleanup_started=False, evidence_record_reconstructed=False,
                  stdout_publication_started=False)
    process = None
    exit_code = 2
    output = b""
    try:
        if argv is None:
            argv = sys.argv[1:]
        if argv:
            record["reason"] = "invalid-arguments"
            raise ValueError("resolve-agents-root.sh accepts no arguments")
        value = os.environ.get("RCA_RESOLVER_TIMEOUT_SECONDS", "10")
        try:
            seconds = float(value)
            if not math.isfinite(seconds) or not 0 < seconds <= 60:
                raise ValueError
        except ValueError:
            record["reason"] = "invalid-deadline"
            raise ValueError("RCA_RESOLVER_TIMEOUT_SECONDS must be finite and greater than 0, at most 60")
        record["configured_deadline_seconds"] = seconds
        deadline = started + seconds
        with (evidence / "stdout").open("wb") as stdout, (evidence / "stderr").open("wb") as stderr:
            if cancellation[0] is None and time.monotonic() < deadline:
                process = subprocess.Popen(
                    ["/bin/bash", str(Path(__file__).absolute().with_name("resolve-agents-root-validate.sh")),
                     str(evidence)], stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                    close_fds=True, start_new_session=True)
                record.update(validator_pid=process.pid, validator_pgid=process.pid)
                while cancellation[0] is None and time.monotonic() < deadline:
                    if process.poll() is not None:
                        break
                    time.sleep(0.01)
            if cancellation[0] is not None:
                record["reason"] = "cancelled"
                exit_code = 128 + cancellation[0]
            elif time.monotonic() >= deadline:
                record["reason"] = "deadline"
                exit_code = 124
            elif process.returncode not in (0, 1, 2):
                record["reason"] = "validator-failure"
            elif _group_state(process.pid) != "absent":
                record["reason"] = "remaining-group"
            elif process.returncode == 1 and _snapshot(evidence / "outcome", 32)[0] != b"unavailable\n":
                record["reason"] = "unconfirmed-absence"
            else:
                record["absence_confirmed"] = process.returncode == 1
                exit_code = process.returncode
                record["reason"] = {0: "resolved", 1: "unavailable", 2: "validator-failure"}[exit_code]
            if process is not None:
                _cleanup(process, record)
                record["child_status"] = process.returncode
                if not record["reaped"] or record["group_after_cleanup"] != "absent":
                    if exit_code in (0, 1):
                        exit_code = 2
                        record["reason"] = "uncertain-custody"
            if cancellation[0] is not None:
                record["reason"] = "cancelled"
                exit_code = 128 + cancellation[0]
        if exit_code == 0:
            output, truncated = _snapshot(evidence / "stdout", 32768)
            if truncated or not output.startswith(b"/") or not output.endswith(b"\n"):
                record["reason"] = "invalid-validator-output"
                exit_code = 2
    except (OSError, ValueError) as error:
        record.setdefault("errors", []).append(str(error))
        if isinstance(error, OSError) or record["reason"] is None:
            record["reason"] = "supervisor-failure"
        if process is not None:
            _cleanup(process, record)
            record["child_status"] = process.returncode
        exit_code = 2
    diagnostic = b""
    truncated = False
    try:
        phase, _ = _snapshot(evidence / "phase", 128)
        if phase:
            record["phase"] = phase.decode("utf-8", "replace").strip()
        if exit_code == 0 and cancellation[0] is None:
            record["success_artifact_cleanup_started"] = True
            shutil.rmtree(evidence)
            if cancellation[0] is None:
                record["stdout_publication_started"] = True
                sys.stdout.buffer.write(output)
                sys.stdout.buffer.flush()
                if _commit_outcome(cancellation, None):
                    return 0
        diagnostic, truncated = _snapshot(evidence / "stderr", 4096)
    except OSError as error:
        record.setdefault("errors", []).append(str(error))
        record["reason"] = "supervisor-failure"
        exit_code = 2
    record["evidence_record_reconstructed"] = record["success_artifact_cleanup_started"]
    # Outcomes can change once for I/O failure and once for the immutable first
    # cancellation. No validation or CLI invocation is repeated by these passes.
    for _ in range(3):
        prepared_signal = cancellation[0]
        if prepared_signal is not None:
            record["reason"] = "cancelled"
            exit_code = 128 + prepared_signal
        record["signal"] = prepared_signal
        record["exit_code"] = exit_code
        record["elapsed_seconds"] = time.monotonic() - started
        io_failed = False
        persistence_error = None
        try:
            evidence.mkdir(mode=0o700, exist_ok=True)
            (evidence / "result.json").write_text(json.dumps(record, indent=2) + "\n")
        except OSError as error:
            persistence_error = str(error)
            record.setdefault("errors", []).append(f"cannot persist resolver metadata: {error}")
            io_failed = True
        try:
            print(f"rca: Agents resolution {record['reason']} (exit {exit_code}); evidence: {evidence}", file=sys.stderr)
            if persistence_error is not None:
                print("rca: could not persist current outcome; result.json may describe an earlier outcome; "
                      f"exit {exit_code} is authoritative: {persistence_error}", file=sys.stderr)
            if record["evidence_record_reconstructed"]:
                print("rca: reconstructed failure record after success cleanup; original raw captures may be missing",
                      file=sys.stderr)
            if record["stdout_publication_started"]:
                print("rca: stdout publication began; discard stdout unless exit 0", file=sys.stderr)
            if diagnostic:
                print(diagnostic.decode("utf-8", "replace"), file=sys.stderr, end="\n")
            if truncated:
                print("rca: diagnostic excerpt truncated; raw stderr retained in evidence", file=sys.stderr)
            for error in record.get("errors", []):
                print(f"rca: {error}", file=sys.stderr)
            sys.stderr.flush()
        except OSError as error:
            record.setdefault("errors", []).append(f"cannot emit resolver diagnostics: {error}")
            io_failed = True
        if io_failed and prepared_signal is None and exit_code != 2:
            record["reason"] = "supervisor-failure"
            exit_code = 2
            continue
        if _commit_outcome(cancellation, prepared_signal):
            return exit_code
    # The two monotonic transitions above exhaust the allowed outcome changes.
    return 2


if __name__ == "__main__":
    sys.exit(main())
