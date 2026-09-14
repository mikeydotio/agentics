"""Exercise the production Make graph without running the repository's suites.

Only leaf suite commands are replaced in private fixture copies. The receipt
adapter and dependency graph remain production code. An explicitly supplied
portable writer adds real-Git identity checks; no receipts touch this checkout.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAKE = shutil.which("make")
WRITER = None
# This independent census prevents an orchestration change from dropping a leg.
SUITES = set("""test-store-isolation test-gate-integrity test-hook-retirement
test-storyhook-version-pin test-root-bats test-plugin-versions
test-plugin-content-drift test-storyhook-path-guard test-storyhook-contract-root
test-sigpipe-shape-guard test-bounded-capture-guard test-forge-integrity-isolation
test-prompt-hygiene test-agents test-council test-semver test-deployit
test-deployit-capture-diagnostics test-forge test-hook-guard test-greenlight
test-freshen test-issue test-reconcile-pr test-rca test-worktree-preservation test-gate-receipt""".split())

EVENTS = r'''import json, os, pathlib, sys, time
mode, name = sys.argv[1:3]
def record(value):
    fd = os.open(os.environ['FIXTURE_EVENTS'], os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, (json.dumps(value) + '\n').encode())
    finally:
        os.close(fd)
if mode == 'writer':
    record(sys.argv[2:])
    if name == 'preflight':
        time.sleep(0.03)
        if os.environ.get('FAIL_PREFLIGHT'): sys.exit(42)
        record(['preflight-done'])
    elif os.environ.get('FAIL_POSTLUDE'):
        sys.exit(43)
else:
    record(['start', name])
    time.sleep(0.01)
    if name == os.environ.get('DRIFT_SUITE'):
        pathlib.Path('tracked').write_text('changed during tests\n')
    if name == os.environ.get('FAIL_SUITE'): sys.exit(17)
    record(['end', name])
'''


class GateFixture(unittest.TestCase):
    """Own all fixture files and clear ambient certification state."""

    def setUp(self):
        """Copy orchestration, replacing only the expensive leaf commands."""
        self.assertIsNotNone(MAKE, "make is required")
        temporary = tempfile.TemporaryDirectory(prefix="age102-gate-", dir="/tmp")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / "candidate with spaces"
        self.repo.mkdir()
        self.events = self.root / "events.jsonl"
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("GIT_", "STORYHOOK_GATE_", "MAKE"))
                    and k not in ("MFLAGS", "FAIL_PREFLIGHT", "FAIL_POSTLUDE",
                                  "FAIL_SUITE", "DRIFT_SUITE")}
        self.env.update(FIXTURE_EVENTS=str(self.events), TMPDIR="/tmp",
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
        self.write("events.py", EVENTS)
        lines = []
        replacing = False
        for line in (ROOT / "Makefile").read_text().splitlines(keepends=True):
            if line.startswith("\t") and replacing:
                continue
            replacing = False
            match = re.match(r"^([\w-]+):", line)
            lines.append(line)
            if match and match[1] in SUITES:
                replacing = True
                lines.append(f'\t@python3 events.py suite {match[1]}\n')
        self.write("Makefile", "".join(lines))
        adapter = ROOT / "scripts/test-gate-receipt.sh"
        if adapter.exists():
            self.write("scripts/test-gate-receipt.sh", adapter.read_text())
        self.writer = self.root / "receipt ' $literal ; writer.sh"
        self.writer.write_text('#!/bin/bash\nexec python3 events.py writer "$@"\n')
        self.writer.chmod(0o755)

    def write(self, name, text):
        """Write a file within this test's disposable checkout."""
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def invoke(self, *goals, writer=True, flags=(), **environment):
        """Run real Make against the production graph and private suite legs."""
        self.events.unlink(missing_ok=True)
        env = dict(self.env, **environment)
        if writer is not None:
            env["STORYHOOK_GATE_RECEIPT"] = str(self.writer if writer is True else writer)
        return subprocess.run([MAKE, *flags, *goals],
                              cwd=self.repo, env=env, capture_output=True,
                              text=True, timeout=30)

    def recorded(self):
        """Read complete event records emitted with atomic append writes."""
        return [json.loads(line) for line in self.events.read_text().splitlines()] \
            if self.events.exists() else []

    def assert_success(self, result):
        """Make failures carry both captured streams in assertion diagnostics."""
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def git(self, *args, env=None):
        """Use real Git and reject invalid fixture preparation."""
        return subprocess.run(["git", *args], cwd=self.repo, env=env or self.env,
                              capture_output=True, text=True, check=True).stdout.strip()


class OrchestrationTests(GateFixture):
    """Pin gate sequencing and failure propagation independently of the writer."""

    def test_managed_orders_every_suite(self):
        """Serial, parallel, default and multiple goals retain both barriers."""
        for goals, flags in ((('test',), ()), (('test',), ('-j8',)),
                             ((), ('-j8',)), (('test-root-bats', 'test'), ('-j8',))):
            with self.subTest(goals=goals, flags=flags):
                self.assert_success(self.invoke(*goals, flags=flags))
                events = self.recorded()
                self.assertEqual([["preflight"], ["preflight-done"]], events[:2])
                self.assertEqual(["postlude", "gate"], events[-1])
                self.assertCountEqual([["start", s] for s in SUITES],
                                      [e for e in events if e[0] == "start"])
                self.assertCountEqual([["end", s] for s in SUITES],
                                      [e for e in events if e[0] == "end"])
                self.assertEqual(2 * len(SUITES) + 3, len(events))

    def test_unmanaged_and_focused_runs_do_not_call_writer(self):
        """Focused nested Make invocations cannot replace outer preflight state."""
        self.assert_success(self.invoke('test', writer=None, flags=('-j8',)))
        self.assertCountEqual([["end", s] for s in SUITES],
                              [e for e in self.recorded() if e[0] == "end"])
        self.assertTrue(all(e[0] in ('start', 'end') for e in self.recorded()))
        for suite in SUITES:
            with self.subTest(suite=suite):
                self.assert_success(self.invoke(suite))
                self.assertEqual([["start", suite], ["end", suite]], self.recorded())

    def test_failed_preflight_runs_no_suite(self):
        """Preflight failure is a barrier even with keep-going parallel Make."""
        result = self.invoke('test', flags=('-j8', '-k'), FAIL_PREFLIGHT='1')
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual([["preflight"]], self.recorded())
        self.assertIn('42', result.stderr)

    def test_any_failed_suite_prevents_postlude(self):
        """Every required leg independently vetoes certification."""
        for suite in SUITES:
            with self.subTest(suite=suite):
                result = self.invoke('test', flags=('-j8', '-k'), FAIL_SUITE=suite)
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn(["start", suite], self.recorded())
                self.assertNotIn(["postlude", "gate"], self.recorded())
                self.assertIn('17', result.stderr)

    def test_postlude_failure_fails_make(self):
        """A successful suite cannot conceal a failed certification write."""
        result = self.invoke('test', flags=('-j8',), FAIL_POSTLUDE='1')
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(["postlude", "gate"], self.recorded()[-1])
        self.assertIn('43', result.stderr)

    def test_nonexecuting_and_ignore_error_modes_cannot_certify(self):
        """Make's control modes must not convert unrun or failed tests to proof."""
        for flag in ('-n', '-q', '-t', '-i', '--ignore-errors'):
            with self.subTest(flag=flag):
                result = self.invoke('test', flags=(flag, '-j8'), FAIL_SUITE='test-root-bats')
                self.assertTrue(all(e[0] in ('start', 'end') for e in self.recorded()),
                                self.recorded())
                if flag in ('-i', '--ignore-errors'):
                    self.assertIn('ignore-errors', result.stderr)

    def test_suite_override_cannot_reduce_coverage(self):
        """The configured full gate retains its complete required census."""
        self.assert_success(self.invoke('test', 'TEST_SUITES=test-root-bats', flags=('-j8',)))
        self.assertCountEqual([["end", s] for s in SUITES],
                              [e for e in self.recorded() if e[0] == 'end'])

    def test_unusable_supplied_writer_fails_before_tests(self):
        """Unset alone is unmanaged; empty, relative and unusable paths fail."""
        inert = self.root / 'not executable'
        inert.write_text('exit 0\n')
        for writer in ('', 'relative-writer', self.root / 'missing', self.root, inert):
            with self.subTest(writer=writer):
                result = self.invoke('test', writer=writer, flags=('-j8',))
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn('STORYHOOK_GATE_RECEIPT', result.stderr)
                self.assertEqual([], self.recorded())


class PortableWriterTests(GateFixture):
    """Use the actual portable writer, never a copied receipt implementation."""

    def setUp(self):
        """Initialize a private tracked source and use the supplied executable."""
        super().setUp()
        self.writer = WRITER
        self.git('init', '-q', '--template=')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'core.hooksPath', 'unrelated hooks')
        self.write('tracked', 'baseline\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.tree = self.git('rev-parse', 'HEAD^{tree}')
        self.receipts = self.repo / '.git/storyhook/gate-receipts'

    def test_success_certifies_only_fixture_tree_without_hook_changes(self):
        """The writer earns the exact fixture tree's gate receipt after all legs."""
        config = (self.repo / '.git/config').read_bytes()
        self.assert_success(self.invoke('test', flags=('-j8',)))
        receipt = (self.receipts / self.tree).read_text().splitlines()
        self.assertIn('tree ' + self.tree, receipt)
        self.assertIn('tier gate', receipt)
        self.assertEqual([self.tree], [p.name for p in self.receipts.iterdir()])
        self.assertEqual(config, (self.repo / '.git/config').read_bytes())

    def test_failure_and_midrun_drift_certify_nothing(self):
        """Neither a failed test nor changing tracked content can earn a receipt."""
        for environment in ({'FAIL_SUITE': 'test-root-bats'},
                            {'DRIFT_SUITE': 'test-root-bats'}):
            with self.subTest(environment=environment):
                result = self.invoke('test', flags=('-j8',), **environment)
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertFalse(self.receipts.exists() and list(self.receipts.iterdir()))
                if 'DRIFT_SUITE' in environment:
                    self.assertIn('tracked content changed', result.stderr)

    def test_private_alternate_head_is_certified_without_publishing_objects(self):
        """The gate retains the verifier's immutable alternate-object lookup."""
        source_objects = self.repo / '.git/objects'
        linked = self.root / 'linked candidate'
        self.git('worktree', 'add', '-q', '--detach', str(linked), 'HEAD')
        self.repo = linked
        private = self.root / 'private objects'
        private.mkdir()
        self.git('commit', '--allow-empty', '-qm', 'speculative candidate',
                 env=dict(self.env, GIT_OBJECT_DIRECTORY=str(private),
                          GIT_ALTERNATE_OBJECT_DIRECTORIES=str(source_objects)))
        head = self.git('rev-parse', 'HEAD')
        missing = subprocess.run(['git', 'cat-file', '-e', head], cwd=self.repo,
                                 env=self.env, capture_output=True)
        self.assertNotEqual(0, missing.returncode)
        self.env['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = str(private)
        self.assert_success(self.invoke('test', flags=('-j8',)))
        self.assertIn('tier gate', (self.receipts / self.tree).read_text())
        del self.env['GIT_ALTERNATE_OBJECT_DIRECTORIES']
        missing = subprocess.run(['git', 'cat-file', '-e', head], cwd=self.repo,
                                 env=self.env, capture_output=True)
        self.assertNotEqual(0, missing.returncode, 'speculative HEAD leaked into shared objects')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--writer', default=os.environ.get('STORYHOOK_GATE_RECEIPT'),
                        help='portable writer for additional real-Git integration cases')
    arguments = parser.parse_args()
    WRITER = arguments.writer
    if WRITER is not None and (not Path(WRITER).is_absolute()
                              or not Path(WRITER).is_file() or not os.access(WRITER, os.X_OK)):
        parser.error('--writer must name an absolute executable portable receipt writer')
    loader = unittest.defaultTestLoader
    suite = loader.loadTestsFromTestCase(OrchestrationTests)
    if WRITER is not None:
        suite.addTests(loader.loadTestsFromTestCase(PortableWriterTests))
    else:
        print('Orchestration checks only; pass --writer for external receipt identity checks.', flush=True)
    raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
