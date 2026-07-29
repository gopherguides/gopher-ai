#!/usr/bin/env python3

import json
import os
import queue
import re
import subprocess
import tempfile
import threading
import time
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
TOP_LEVEL_DOCUMENTATION_FILES = (
    ROOT_DIR / "AGENTS.md",
    ROOT_DIR / "README.md",
    ROOT_DIR / "plugins/go-workflow/README.md",
)
PACKAGED_DOCUMENTATION_DIRS = (
    ROOT_DIR / "plugins/go-workflow/skills",
    ROOT_DIR / "plugins/go-workflow/lib",
)
QUALIFIED_SKILL_PATTERN = re.compile(r"\$(go-workflow:[a-z][a-z0-9-]*)")
BARE_SKILL_PATTERN = re.compile(r"\$([a-z][a-z0-9-]*)(?![a-z0-9_-])")
WORKTREE_SLASH_COMMANDS = {"create-worktree", "remove-worktree", "prune-worktree"}


def documentation_files():
    packaged_files = (
        path
        for directory in PACKAGED_DOCUMENTATION_DIRS
        for path in directory.rglob("*.md")
    )
    return (*TOP_LEVEL_DOCUMENTATION_FILES, *packaged_files)


class AppServerClient:
    def __init__(self, env):
        self.process = subprocess.Popen(
            ["codex", "app-server", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        self.messages = queue.Queue()
        self.stderr = []
        self.next_request_id = 1
        self.stdout_thread = threading.Thread(target=self.read_stdout, daemon=True)
        self.stderr_thread = threading.Thread(target=self.read_stderr, daemon=True)
        self.stdout_thread.start()
        self.stderr_thread.start()

    def read_stdout(self):
        for line in self.process.stdout:
            self.messages.put(json.loads(line))
        self.messages.put(None)

    def read_stderr(self):
        self.stderr.extend(self.process.stderr)

    def send(self, message):
        self.process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def request(self, method, params):
        request_id = self.next_request_id
        self.next_request_id += 1
        self.send({"method": method, "id": request_id, "params": params})
        deadline = time.monotonic() + 15
        deferred = []
        while time.monotonic() < deadline:
            try:
                message = self.messages.get(timeout=deadline - time.monotonic())
            except queue.Empty as error:
                raise AssertionError(f"timed out waiting for {method}") from error
            if message is None:
                raise AssertionError(
                    f"app-server exited while waiting for {method}: {''.join(self.stderr)}"
                )
            if message.get("id") == request_id:
                if "error" in message:
                    raise AssertionError(f"{method} failed: {message['error']}")
                for item in deferred:
                    self.messages.put(item)
                return message["result"]
            deferred.append(message)
        raise AssertionError(f"timed out waiting for {method}")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)


def run_codex(env, *args):
    subprocess.run(
        ["codex", *args],
        cwd=ROOT_DIR,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )


def documented_skill_names():
    names = set()
    for path in documentation_files():
        names.update(QUALIFIED_SKILL_PATTERN.findall(path.read_text(encoding="utf-8")))
    if not names:
        raise AssertionError("documentation contains no qualified go-workflow skills")
    return names


def documented_bare_names():
    names = set()
    for path in documentation_files():
        names.update(BARE_SKILL_PATTERN.findall(path.read_text(encoding="utf-8")))
    return names


def main():
    temp_base = os.environ.get("TMPDIR") or os.environ.get("TMP") or os.environ.get("TEMP")
    with tempfile.TemporaryDirectory(prefix="gopher-ai-skill-names-", dir=temp_base) as root:
        test_root = Path(root)
        codex_home = test_root / ".codex"
        codex_home.mkdir()
        env = os.environ.copy()
        env.update({"HOME": str(test_root), "CODEX_HOME": str(codex_home)})

        run_codex(env, "plugin", "marketplace", "add", str(ROOT_DIR), "--json")
        run_codex(env, "plugin", "add", "go-workflow@gopher-ai", "--json")

        client = AppServerClient(env)
        try:
            client.request(
                "initialize",
                {
                    "clientInfo": {
                        "name": "gopher_ai_skill_name_probe",
                        "title": "Gopher AI Skill Name Probe",
                        "version": "1.0.0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            )
            client.send({"method": "initialized", "params": {}})
            response = client.request(
                "skills/list",
                {"cwds": [str(ROOT_DIR)], "forceReload": True},
            )
        finally:
            client.close()

        if len(response["data"]) != 1:
            raise AssertionError(
                f"expected one workspace entry, got {len(response['data'])}"
            )

        entry = response["data"][0]
        if entry["errors"]:
            raise AssertionError(f"skills/list returned errors: {entry['errors']}")

        resolver_names = {skill["name"] for skill in entry["skills"]}
        workflow_resolver_names = {
            name for name in resolver_names if name.startswith("go-workflow:")
        }
        documented_names = documented_skill_names()
        missing_names = documented_names - resolver_names
        if missing_names:
            raise AssertionError(
                f"documented skills missing from skills/list: {sorted(missing_names)}"
            )

        bare_aliases = {
            name.removeprefix("go-workflow:") for name in documented_names
        } & resolver_names
        if bare_aliases:
            raise AssertionError(
                f"skills/list unexpectedly advertised bare aliases: {sorted(bare_aliases)}"
            )

        resolver_suffixes = {
            name.removeprefix("go-workflow:") for name in workflow_resolver_names
        }
        bare_references = documented_bare_names() & (
            resolver_suffixes | WORKTREE_SLASH_COMMANDS
        )
        if bare_references:
            raise AssertionError(
                "documentation contains bare Codex skill references: "
                f"{sorted(bare_references)}"
            )

    print(
        "Codex qualified skill-name probe passed: "
        + ", ".join(sorted(documented_names))
    )


if __name__ == "__main__":
    main()
