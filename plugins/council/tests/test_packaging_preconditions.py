"""Missing tools must not make the real installation smoke report success."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "smoke-codex-install.sh"


class PackagingPreconditions(unittest.TestCase):
    """Provide only tool-presence sentinels; installation behavior stays production."""

    def check_missing(self, missing):
        """Invoke the actual smoke with exactly one unavailable prerequisite."""
        with tempfile.TemporaryDirectory(prefix="council-prereqs-", dir="/tmp") as temp:
            root = Path(temp)
            (root / "dirname").symlink_to("/usr/bin/dirname")
            for command in ("codex", "jq", "python3"):
                if command != missing:
                    tool = root / command
                    tool.write_text("#!/bin/sh\nexit 88\n")
                    tool.chmod(0o700)
            result = subprocess.run(["/bin/bash", str(SCRIPT)], env=dict(os.environ, PATH=temp),
                                    capture_output=True, text=True, timeout=10, check=False)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(f"ERROR: {missing} is required", result.stdout + result.stderr)
            self.assertNotIn("PASS:", result.stdout)
            self.assertNotIn("SKIP:", result.stdout)

    def test_missing_codex_fails(self):
        """No Codex means no verified installation."""
        self.check_missing("codex")

    def test_missing_jq_fails(self):
        """No JSON verifier means no verified installation."""
        self.check_missing("jq")

    def test_missing_python_fails(self):
        """No state-helper interpreter means no verified runtime."""
        self.check_missing("python3")


if __name__ == "__main__":
    unittest.main()
