#!/usr/bin/env python3
"""Behavioral checks for bounded test commands."""
import pathlib
import subprocess
import sys
import unittest

RUNNER = pathlib.Path(__file__).with_name("run-with-timeout.py")


class TimeoutTests(unittest.TestCase):
    def run_command(self, code, seconds="2"):
        return subprocess.run(
            [sys.executable, str(RUNNER), seconds, sys.executable, "-c", code],
            capture_output=True, text=True, timeout=5,
        )

    def test_preserves_output_and_success(self):
        result = self.run_command("print('hello')")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "hello\n")

    def test_preserves_failure(self):
        self.assertEqual(self.run_command("raise SystemExit(7)").returncode, 7)

    def test_deadline_kills_descendants_holding_output_open(self):
        result = self.run_command(
            "import subprocess,sys,time; "
            "subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
            "time.sleep(30)", "0.2",
        )
        self.assertEqual(result.returncode, 124)
        self.assertIn("timed out after 0.2s", result.stderr)


if __name__ == "__main__":
    unittest.main()
