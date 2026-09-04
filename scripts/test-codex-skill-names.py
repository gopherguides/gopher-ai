#!/usr/bin/env python3

import json
import os
import queue
import re
import shlex
import subprocess
import tempfile
import threading
import time
from collections import Counter
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
MATRIX_PATH = ROOT_DIR / "docs/platform-capabilities.json"
README_PATH = ROOT_DIR / "README.md"
BARE_SKILL_PATTERN = re.compile(r"\$([a-z][a-z0-9-]*)(?![a-z0-9_:-])")
COUNT_PATTERN = re.compile(
    r"Shipped surface: (\d+) Claude Code commands across (\d+) plugins; "
    r"(\d+) Codex skills across (\d+) plugins; "
    r"(\d+) optional Codex MCP tools\."
)
REPOSITORY_GUIDANCE_FILES = (
    ROOT_DIR / "README.md",
    ROOT_DIR / "AGENTS.md",
    ROOT_DIR / "scripts/build-universal.sh",
)
STALE_REPOSITORY_GUIDANCE = (
    "Repo-local",
    "Plugins load automatically from .agents/plugins/marketplace.json",
    "Codex reads `.agents/plugins/marketplace.json` on startup",
)
REQUIRED_CODEX_SKILLS = {"go-web:create-go-project"}


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
    missing_required = sorted(REQUIRED_CODEX_SKILLS - set(skill_names))
    if missing_required:
        raise AssertionError(
            f"capability matrix is missing required Codex skills: {missing_required}"
        )
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


def documentation_files(plugin_names):
    paths = {ROOT_DIR / "AGENTS.md", README_PATH}
    for plugin_name in plugin_names:
        plugin_root = ROOT_DIR / "plugins" / plugin_name
        paths.add(plugin_root / "README.md")
        for directory_name in ("skills", "lib"):
            directory = plugin_root / directory_name
            if directory.is_dir():
                paths.update(directory.rglob("*.md"))
    return sorted(path for path in paths if path.is_file())


def assert_no_bare_documentation_references(plugin_names, skill_names):
    suffixes = {name.split(":", 1)[1] for name in skill_names}
    offenders = []
    for path in documentation_files(plugin_names):
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            for match in BARE_SKILL_PATTERN.finditer(line):
                if match.group(1) in suffixes:
                    offenders.append(
                        f"{path.relative_to(ROOT_DIR)}:{line_number}:{match.group(0)}"
                    )
    if offenders:
        raise AssertionError(
            "documentation contains unresolvable bare Codex skill references: "
            + ", ".join(offenders)
        )


def run_codex(env, cwd, *args):
    return subprocess.run(
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


def parsed_activation_commands(output):
    return [
        shlex.split(line.strip())
        for line in output.splitlines()
        if line.strip().startswith("codex plugin ")
    ]


def resolver_skill_names(response):
    if len(response["data"]) != 1:
        raise AssertionError(
            f"expected one workspace entry, got {len(response['data'])}"
        )
    entry = response["data"][0]
    if entry["errors"]:
        raise AssertionError(f"skills/list returned errors: {entry['errors']}")
    return [skill["name"] for skill in entry["skills"]]


def assert_resolver_surface(response, plugin_names, skill_names):
    resolver_name_list = resolver_skill_names(response)
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


def validate_repository_guidance():
    stale_matches = []
    for path in REPOSITORY_GUIDANCE_FILES:
        content = path.read_text(encoding="utf-8")
        stale_matches.extend(
            f"{path.relative_to(ROOT_DIR)}: {phrase}"
            for phrase in STALE_REPOSITORY_GUIDANCE
            if phrase in content
        )
    if stale_matches:
        raise AssertionError(
            "documentation contains stale repository discovery guidance: "
            f"{stale_matches}"
        )


def main():
    matrix = load_matrix()
    plugin_names, skill_names = declared_surface(matrix)
    assert_readme_counts(matrix, plugin_names, skill_names)
    assert_no_bare_documentation_references(plugin_names, skill_names)
    validate_repository_guidance()

    temp_base = (
        os.environ.get("TMPDIR")
        or os.environ.get("TMP")
        or os.environ.get("TEMP")
        or "/tmp"
    )
    temp_base_path = Path(temp_base).resolve()
    with tempfile.TemporaryDirectory(
        prefix="gopher-ai-skill-home-", dir=temp_base
    ) as root:
        test_root = Path(root)
        codex_home = test_root / ".codex"
        codex_home.mkdir()
        target_repo = test_root / "target repo"
        target_repo.mkdir()
        marketplace_dir = target_repo / ".agents/plugins"
        marketplace_dir.mkdir(parents=True)
        (marketplace_dir / "marketplace.json").write_text(
            json.dumps({"name": "repo-plugins", "plugins": []}),
            encoding="utf-8",
        )
        temp_bin = test_root / "bin"
        temp_bin.mkdir()
        mktemp = temp_bin / "mktemp"
        mktemp.write_text(
            "#!/bin/bash\n"
            "if [[ $# -eq 0 ]]; then\n"
            '  exec /usr/bin/mktemp "${TMPDIR:?}/gopher-ai-test.XXXXXX"\n'
            "elif [[ $# -eq 1 && $1 == -d ]]; then\n"
            '  exec /usr/bin/mktemp -d "${TMPDIR:?}/gopher-ai-test.XXXXXX"\n'
            "fi\n"
            'exec /usr/bin/mktemp "$@"\n',
            encoding="utf-8",
        )
        mktemp.chmod(0o755)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(test_root),
                "CODEX_HOME": str(codex_home),
                "PATH": f"{temp_bin}{os.pathsep}{env['PATH']}",
                "TMPDIR": str(test_root),
                "TMP": str(test_root),
                "TEMP": str(test_root),
            }
        )
        if temp_base_path.is_relative_to(ROOT_DIR.resolve()):
            existing_ceiling = env.get("GIT_CEILING_DIRECTORIES")
            env["GIT_CEILING_DIRECTORIES"] = os.pathsep.join(
                value
                for value in (str(temp_base_path), existing_ceiling)
                if value
            )

        install = subprocess.run(
            [
                "/bin/bash",
                str(ROOT_DIR / "scripts/install-codex.sh"),
                "--repo",
                str(target_repo),
            ],
            cwd=ROOT_DIR,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        marketplace_name = json.loads(
            (marketplace_dir / "marketplace.json").read_text(encoding="utf-8")
        )["name"]
        activation_commands = [
            ["codex", "plugin", "marketplace", "add", str(target_repo)],
            *(
                ["codex", "plugin", "add", f"{name}@{marketplace_name}"]
                for name in sorted(plugin_names)
            ),
        ]
        emitted_commands = parsed_activation_commands(install.stdout)
        if emitted_commands != activation_commands:
            raise AssertionError(
                "installer output activation commands differ from expected: "
                f"{emitted_commands}"
            )

        unsafe_repo = test_root / "unsafe target"
        unsafe_marketplace_dir = unsafe_repo / ".agents/plugins"
        unsafe_marketplace_dir.mkdir(parents=True)
        unsafe_marketplace_name = "repo plugins;$(touch injected)"
        (unsafe_marketplace_dir / "marketplace.json").write_text(
            json.dumps({"name": unsafe_marketplace_name, "plugins": []}),
            encoding="utf-8",
        )
        unsafe_install = subprocess.run(
            [
                "/bin/bash",
                str(ROOT_DIR / "scripts/install-codex.sh"),
                "--repo",
                str(unsafe_repo),
            ],
            cwd=ROOT_DIR,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        unsafe_commands = parsed_activation_commands(unsafe_install.stdout)
        unsafe_expected = [
            ["codex", "plugin", "marketplace", "add", str(unsafe_repo)],
            *(
                ["codex", "plugin", "add", f"{name}@{unsafe_marketplace_name}"]
                for name in sorted(plugin_names)
            ),
        ]
        if unsafe_commands != unsafe_expected:
            raise AssertionError(
                "installer output did not safely preserve activation arguments: "
                f"{unsafe_commands}"
            )

        inactive_names = set(resolver_skill_names(query_resolver(env, target_repo)))
        unexpectedly_active = set(skill_names) & inactive_names
        if unexpectedly_active:
            raise AssertionError(
                "repo-staged skills unexpectedly active before plugin activation: "
                f"{sorted(unexpectedly_active)}"
            )

        for command in emitted_commands:
            run_codex(env, target_repo, *command[1:])

        response = query_resolver(env, target_repo)

    assert_resolver_surface(response, plugin_names, skill_names)
    print(
        "Codex repo activation and all-plugin qualified skill-name probe passed: "
        f"{len(skill_names)} skills: {', '.join(sorted(skill_names))}"
    )


if __name__ == "__main__":
    main()
