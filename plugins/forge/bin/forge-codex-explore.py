#!/usr/bin/env python3
"""Run bounded Codex experiments in an owned disposable Git worktree."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def git(repo, *args):
    """Run one Git operation with captured contextual diagnostics."""
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True,
                            text=True, timeout=30, check=False)
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout.strip()


def stop_group(process):
    """Kill remaining ordinary descendants in the owned process group and reap the leader."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def explore(task, out, timeout):
    """Return findings only after successful execution and cleanup; preserve failure evidence."""
    repo = Path(git(Path.cwd(), "rev-parse", "--show-toplevel"))
    result = {"ok": False, "rc": None, "findings": str(out), "kept": False}
    # Files live outside the caller and are excluded from the model's writable root.
    temp = tempfile.TemporaryDirectory(prefix="forge-codex-explore-", dir="/private/tmp")
    base = Path(temp.name)
    worktree = base / "worktree"
    result["worktree"] = str(worktree)
    added = False
    try:
        git(repo, "worktree", "add", "--detach", str(worktree), "HEAD")
        added = True
        report = worktree / ".forge-explorer-findings.md"
        command = [
            "codex", "exec", "--sandbox", "workspace-write",
            "-c", 'approval_policy="never"',
            "-c", "sandbox_workspace_write.writable_roots=[]",
            "-c", "sandbox_workspace_write.network_access=false",
            "-c", "sandbox_workspace_write.exclude_tmpdir_env_var=true",
            "-c", "sandbox_workspace_write.exclude_slash_tmp=true",
            "--output-last-message", str(report), "-",
        ]
        # Stay in the verifier's session while owning a distinct child process group.
        # The trampoline works on Python versions predating Popen(process_group=...).
        trampoline = [sys.executable, "-c",
                      "import os,sys; os.setpgid(0,0); os.execvp(sys.argv[1],sys.argv[1:])"]
        charter = ("Investigate in this disposable worktree. Experimental edits here are "
                   "throwaway. Do not edit outside it, stage, commit, spawn agents, or request "
                   "approval. Use the active sandbox. Return a concise report with concrete "
                   "file/line evidence, experiments, results and limitations.\n\n")
        input_path = base / "input.txt"
        input_path.write_text(charter + task)
        with input_path.open() as incoming, (base / "process.log").open("w+") as log:
            process = subprocess.Popen(trampoline + command, cwd=worktree, stdin=incoming,
                                       stdout=log, stderr=log)
            try:
                result["rc"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                result["error"] = f"Codex explorer timeout after {timeout:g} seconds"
            finally:
                stop_group(process)
            log.seek(0)
            diagnostic = log.read()[-4000:]
        if "error" not in result:
            if result["rc"] != 0:
                result["error"] = f"Codex explorer exited {result['rc']}: {diagnostic}"
            elif not report.is_file() or not report.read_text().strip():
                result["error"] = "Codex explorer returned no findings"
            else:
                findings = report.read_text()
                result["ok"] = True
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        result["error"] = f"Codex explorer failed: {error}"
    finally:
        if added:
            try:
                git(repo, "worktree", "remove", "--force", str(worktree))
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                result["ok"] = False
                result["kept"] = True
                result["error"] = f"{result.get('error', '')}; cleanup failed: {error}"
        if result["kept"]:
            # Keep the owned directory for diagnosis when Git could not remove its registration.
            temp._finalizer.detach()
        else:
            temp.cleanup()
    if result["ok"]:
        try:
            out.parent.mkdir(parents=True, exist_ok=True)
            pending = out.with_name(out.name + ".tmp")
            pending.write_text(findings)
            pending.replace(out)
        except OSError as error:
            result["ok"] = False
            result["error"] = f"Cannot publish explorer findings to {out}: {error}"
    return result


def main():
    """Parse the internal launcher interface and emit exactly one JSON result."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", required=True)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args()
    if not 0 < args.timeout <= 3600:
        parser.error("--timeout must be greater than 0 and at most 3600 seconds")
    try:
        result = explore(args.task, args.out, args.timeout)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
