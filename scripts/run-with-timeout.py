#!/usr/bin/env python3
"""Run a test command with a deadline, killing its process group on timeout."""

import os
import signal
import subprocess
import sys


def main():
    seconds = float(sys.argv[1])
    command = sys.argv[2:]
    process = subprocess.Popen(command, start_new_session=True)
    try:
        status = process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        print(f"FAIL: timed out after {seconds:g}s: {command!r}", file=sys.stderr)
        return 124
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main())
