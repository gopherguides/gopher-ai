#!/usr/bin/env python3

import json
import os
import queue
import re
import subprocess
import tempfile
import threading
import time
from collections import Counter
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
MATRIX_PATH = ROOT_DIR / "docs/platform-capabilities.json"
README_PATH = ROOT_DIR / "README.md"
COUNT_PATTERN = re.compile(
    r"Shipped surface: (\d+) Claude Code commands across (\d+) plugins; "
    r"(\d+) Codex skills across (\d+) plugins; "
    r"(\d+) optional Codex MCP tools\."
)


class AppServerClient:
    def __init__(self, env, cwd):
        self.process = subprocess.Popen(
            ["codex", "app-server", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
            cwd=cwd,
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
        deadline = time.monotonic() + 30
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


def load_matrix():
    try:
        matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise AssertionError(f"missing capability matrix: {MATRIX_PATH}") from error
    except json.JSONDecodeError as error:
        raise AssertionError(f"invalid capability matrix: {error}") from error
    if matrix.get("schema_version") != 1:
        raise AssertionError(
            f"unsupported capability matrix schema: {matrix.get('schema_version')}"
        )
    return matrix


def declared_surface(matrix):
    plugin_names = [
        plugin["name"]
        for plugin in matrix["plugins"]
        if plugin["platforms"]["codex"]["status"] == "supported"
    ]
    skill_names = [
        capability["platforms"]["codex"]["name"]
        for capability in matrix["capabilities"]
        if capability["platforms"]["codex"]["disposition"] == "skill"
    ]
    duplicate_plugins = sorted(
        name for name, count in Counter(plugin_names).items() if count > 1
    )
    duplicate_skills = sorted(
        name for name, count in Counter(skill_names).items() if count > 1
    )
    if duplicate_plugins or duplicate_skills:
        raise AssertionError(
            "capability matrix contains duplicates: "
            f"plugins={duplicate_plugins}, skills={duplicate_skills}"
        )
    if not plugin_names or not skill_names:
        raise AssertionError("capability matrix declares no Codex plugin skill surface")
    return plugin_names, skill_names


def assert_readme_counts(matrix, plugin_names, skill_names):
    command_count = sum(
        source["kind"] == "command"
        for capability in matrix["capabilities"]
        for source in capability["sources"]
    )
    mcp_tool_count = sum(
        len(capability["platforms"]["codex"]["names"])
        for capability in matrix["capabilities"]
        if capability["platforms"]["codex"]["disposition"] == "mcp_tool"
    )
    expected = (
        command_count,
        len(matrix["plugins"]),
        len(skill_names),
        len(plugin_names),
        mcp_tool_count,
    )
    match = COUNT_PATTERN.search(README_PATH.read_text(encoding="utf-8"))
    if not match:
        raise AssertionError("README.md is missing the shipped-surface count statement")
    actual = tuple(int(value) for value in match.groups())
    if actual != expected:
        raise AssertionError(
            f"stale README shipped-surface counts: expected {expected}, got {actual}"
        )


def run_codex(env, cwd, *args):
    subprocess.run(
        ["codex", *args],
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )


def query_resolver(env, cwd):
    client = AppServerClient(env, cwd)
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
        return client.request(
            "skills/list",
            {"cwds": [str(cwd)], "forceReload": True},
        )
    finally:
        client.close()


def assert_resolver_surface(response, plugin_names, skill_names):
    if len(response["data"]) != 1:
        raise AssertionError(
            f"expected one workspace entry, got {len(response['data'])}"
        )
    entry = response["data"][0]
    if entry["errors"]:
        raise AssertionError(f"skills/list returned errors: {entry['errors']}")

    resolver_name_list = [skill["name"] for skill in entry["skills"]]
    duplicate_names = sorted(
        name for name, count in Counter(resolver_name_list).items() if count > 1
    )
    if duplicate_names:
        raise AssertionError(f"skills/list returned duplicate names: {duplicate_names}")

    resolver_names = set(resolver_name_list)
    expected_names = set(skill_names)
    prefixes = tuple(f"{plugin}:" for plugin in plugin_names)
    gopher_ai_qualified_names = {
        name for name in resolver_names if name.startswith(prefixes)
    }
    missing = sorted(expected_names - gopher_ai_qualified_names)
    unexpected = sorted(gopher_ai_qualified_names - expected_names)
    if missing or unexpected:
        raise AssertionError(
            "gopher-ai qualified skill surface differs from the matrix: "
            f"missing={missing}, unexpected={unexpected}"
        )

    suffixes = {name.split(":", 1)[1] for name in expected_names}
    bare_aliases = sorted(suffixes & resolver_names)
    if bare_aliases:
        raise AssertionError(
            f"skills/list unexpectedly advertised bare aliases: {bare_aliases}"
        )


def main():
    matrix = load_matrix()
    plugin_names, skill_names = declared_surface(matrix)
    assert_readme_counts(matrix, plugin_names, skill_names)

    temp_base = (
        os.environ.get("TMPDIR")
        or os.environ.get("TMP")
        or os.environ.get("TEMP")
        or "/tmp"
    )
    temp_base_path = Path(temp_base).resolve()
    with tempfile.TemporaryDirectory(
        prefix="gopher-ai-skill-home-", dir=temp_base
    ) as home_root, tempfile.TemporaryDirectory(
        prefix="gopher-ai-skill-cwd-", dir=temp_base
    ) as cwd_root:
        test_home = Path(home_root)
        clean_cwd = Path(cwd_root).resolve()
        codex_home = test_home / ".codex"
        codex_home.mkdir()
        env = os.environ.copy()
        env.update({"HOME": str(test_home), "CODEX_HOME": str(codex_home)})
        if temp_base_path.is_relative_to(ROOT_DIR.resolve()):
            existing_ceiling = env.get("GIT_CEILING_DIRECTORIES")
            env["GIT_CEILING_DIRECTORIES"] = os.pathsep.join(
                value
                for value in (str(temp_base_path), existing_ceiling)
                if value
            )

        run_codex(env, clean_cwd, "plugin", "marketplace", "add", str(ROOT_DIR), "--json")
        for plugin_name in plugin_names:
            run_codex(
                env,
                clean_cwd,
                "plugin",
                "add",
                f"{plugin_name}@gopher-ai",
                "--json",
            )
        response = query_resolver(env, clean_cwd)

    assert_resolver_surface(response, plugin_names, skill_names)
    print(
        "Codex all-plugin qualified skill-name probe passed: "
        f"{len(skill_names)} skills: {', '.join(sorted(skill_names))}"
    )


if __name__ == "__main__":
    main()
