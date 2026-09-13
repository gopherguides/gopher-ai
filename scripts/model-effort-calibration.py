#!/usr/bin/env python3
"""Run reproducible Claude model/effort calibration sweeps.

The runner loads real plugin command, skill, or agent frontmatter into an
isolated fixture, executes each configured surface in fresh and warm sessions,
and records quality, mutation, tool, latency, token, and cache telemetry.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import fnmatch
import hashlib
import json
import os
import re
import selectors
import signal
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUITE = ROOT / "evals" / "model-effort-calibration.json"
METRIC_FIELDS = {
    "task_success",
    "incorrect_mutations",
    "tool_calls",
    "latency_ms",
    "input_tokens",
    "output_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
}


def frontmatter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return {}
    values: dict[str, str] = {}
    for line in lines[1:]:
        if line == "---":
            break
        match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*?)\s*$", line)
        if match:
            values[match.group(1)] = match.group(2).strip('"\'')
    return values


def discover_pinned_surfaces(root: Path) -> dict[str, dict[str, str]]:
    discovered: dict[str, dict[str, str]] = {}
    plugins = root / "plugins"
    if not plugins.exists():
        return discovered
    for path in sorted(plugins.rglob("*.md")):
        metadata = frontmatter(path.read_text(encoding="utf-8"))
        pin = {key: metadata[key] for key in ("model", "effort") if key in metadata}
        if pin:
            discovered[path.relative_to(root).as_posix()] = pin
    return discovered


def render_frontmatter(text: str, overrides: dict[str, str]) -> str:
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise ValueError("surface does not begin with YAML frontmatter")
    closing = next(
        (index for index, line in enumerate(lines[1:], start=1) if line.rstrip("\r\n") == "---"),
        None,
    )
    if closing is None:
        raise ValueError("surface frontmatter is not closed")
    kept = [
        line
        for line in lines[1:closing]
        if not re.match(r"^(model|effort):", line)
    ]
    for key in ("model", "effort"):
        if overrides.get(key):
            kept.append(f"{key}: {overrides[key]}\n")
    return "".join([lines[0], *kept, lines[closing], *lines[closing + 1 :]])


def build_matrix(
    surfaces: list[dict[str, Any]],
    suite_fingerprint: str = "",
    runner_fingerprint: str = "",
) -> list[dict[str, Any]]:
    matrix: list[dict[str, Any]] = []
    for surface in surfaces:
        final_name = "pinned" if surface.get("pin") else "candidate"
        configs = [
            ("inherited", {}),
            ("session-low", {"effort": "low"}),
            (final_name, surface.get("pin") or surface.get("candidate", {})),
        ]
        for name, config in configs:
            for session in ("fresh", "warm"):
                matrix.append(
                    {
                        **surface,
                        "configuration": name,
                        "configuration_frontmatter": config,
                        "session": session,
                        "suite_fingerprint": suite_fingerprint,
                        "runner_fingerprint": runner_fingerprint,
                    }
                )
    return matrix


def validate_suite(
    suite: dict[str, Any], discovered: dict[str, dict[str, str]]
) -> list[str]:
    errors: list[str] = []
    cases = suite.get("cases", {})
    required_cases = suite.get("required_cases", [])
    surfaces = suite.get("surfaces", [])
    by_path = {surface.get("path"): surface for surface in surfaces}

    for case_id in required_cases:
        if case_id not in cases:
            errors.append(f"required stress case is missing: {case_id}")
    for path, pin in discovered.items():
        surface = by_path.get(path)
        if not surface:
            errors.append(f"pinned surface is not covered: {path}")
        elif surface.get("pin") != pin:
            errors.append(
                f"suite pin differs from frontmatter for {path}: "
                f"expected {pin}, found {surface.get('pin')}"
            )
    for surface in surfaces:
        path = surface.get("path")
        if not path or not (ROOT / path).is_file():
            errors.append(f"surface path does not exist: {path}")
        if surface.get("case") not in cases:
            errors.append(f"surface {path} references an unknown case: {surface.get('case')}")
        if path not in discovered and not surface.get("candidate"):
            errors.append(f"unpinned control surface lacks candidate settings: {path}")
    declared_metrics = set(suite.get("metrics", []))
    missing_metrics = sorted(METRIC_FIELDS - declared_metrics)
    if missing_metrics:
        errors.append(f"suite omits required metrics: {', '.join(missing_metrics)}")
    return errors


def extract_target_telemetry(
    events: list[dict[str, Any]], expected_result_index: int | None = None
) -> dict[str, Any]:
    result_positions = [index for index, event in enumerate(events) if event.get("type") == "result"]
    if not result_positions:
        raise ValueError("Claude stream did not contain a result event")
    result_index = result_positions[-1]
    previous_result = result_positions[-2] if len(result_positions) > 1 else -1
    result = events[result_index]
    result_matches_target = (
        expected_result_index is None
        or result.get("result_index") == expected_result_index
    )
    previous_cost = (
        float(events[previous_result].get("total_cost_usd", 0))
        if previous_result >= 0
        else 0.0
    )
    tool_calls = 0
    target_models: set[str] = set()
    evidence_parts: list[str] = []
    for event in events[previous_result + 1 : result_index]:
        message = event.get("message", {})
        content = message.get("content", [])
        if event.get("type") == "assistant":
            if message.get("model"):
                target_models.add(message["model"])
            tool_calls += sum(item.get("type") == "tool_use" for item in content)
        if isinstance(content, str):
            evidence_parts.append(content)
        elif isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and isinstance(item.get("text"), str):
                    evidence_parts.append(item["text"])
                if isinstance(item, dict) and isinstance(item.get("content"), str):
                    evidence_parts.append(item["content"])
        for key in ("output", "text"):
            if isinstance(event.get(key), str):
                evidence_parts.append(event[key])
    usage = result.get("usage", {})
    if isinstance(result.get("result"), str):
        evidence_parts.append(result["result"])
    evidence = "\n".join(filter(None, evidence_parts))
    target_completed = result_matches_target and bool(
        evidence or tool_calls or usage.get("output_tokens", 0)
    )
    return {
        "tool_calls": tool_calls,
        "latency_ms": int(result.get("duration_api_ms", result.get("duration_ms", 0))),
        "input_tokens": int(usage.get("input_tokens", 0)),
        "output_tokens": int(usage.get("output_tokens", 0)),
        "cache_read_tokens": int(usage.get("cache_read_input_tokens", 0)),
        "cache_write_tokens": int(usage.get("cache_creation_input_tokens", 0)),
        "cost_usd": round(float(result.get("total_cost_usd", 0)) - previous_cost, 8),
        "models": sorted(target_models or result.get("modelUsage", {}).keys()),
        "response": result.get("result", ""),
        "evidence": evidence,
        "is_error": bool(result.get("is_error", False)),
        "permission_denials": result.get("permission_denials", []),
        "target_completed": target_completed,
    }


def snapshot_files(root: Path) -> dict[str, str]:
    snapshot: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if relative == ".git" or relative.startswith(".git/"):
            continue
        if relative.startswith(".calibration-"):
            continue
        snapshot[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return snapshot


def audit_mutations(
    before: dict[str, str], after: dict[str, str], allowed_patterns: list[str]
) -> dict[str, list[str]]:
    changed = sorted(
        path for path in set(before) | set(after) if before.get(path) != after.get(path)
    )
    incorrect = sorted(
        path
        for path in changed
        if not any(fnmatch.fnmatch(path, pattern) for pattern in allowed_patterns)
    )
    return {"changed": changed, "incorrect": incorrect}


def parse_git_status(output: str) -> dict[str, str]:
    status: dict[str, str] = {}
    entries = output.split("\0")
    index = 0
    while index < len(entries):
        entry = entries[index]
        index += 1
        if not entry:
            continue
        code = entry[:2]
        path = entry[3:]
        status[path] = code
        if "R" in code or "C" in code:
            if index < len(entries) and entries[index]:
                status[entries[index]] = f"{code}:source"
                index += 1
    return status


def capture_git_state(root: Path, env: dict[str, str]) -> dict[str, Any]:
    if not (root / ".git").exists():
        return {"status": {}, "refs": {}, "worktrees": {}, "primary_branch": ""}
    status_result = run_command(
        ["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"],
        root,
        env,
    )
    refs_result = run_command(
        ["git", "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads"],
        root,
        env,
    )
    refs = dict(line.split(" ", 1) for line in refs_result.stdout.splitlines())
    primary_branch = run_command(
        ["git", "symbolic-ref", "--quiet", "HEAD"], root, env, check=False
    ).stdout.strip()
    worktree_result = run_command(
        ["git", "worktree", "list", "--porcelain"], root, env
    )
    worktrees: dict[str, dict[str, Any]] = {}
    for block in worktree_result.stdout.strip().split("\n\n"):
        fields: dict[str, str] = {}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            fields[key] = value
        path_text = fields.get("worktree")
        if not path_text:
            continue
        path = Path(path_text)
        key = path.name
        primary = path.resolve() == root.resolve()
        worktrees[key] = {
            "head": fields.get("HEAD", ""),
            "branch": fields.get("branch", ""),
            "primary": primary,
            "files": {} if primary or not path.is_dir() else snapshot_files(path),
        }
    return {
        "status": parse_git_status(status_result.stdout),
        "refs": refs,
        "worktrees": worktrees,
        "primary_branch": primary_branch,
    }


def audit_git_state(
    before: dict[str, Any],
    after: dict[str, Any],
    allowed_patterns: list[str],
) -> list[str]:
    def allowed(path: str) -> bool:
        return any(fnmatch.fnmatch(path, pattern) for pattern in allowed_patterns)

    incorrect: set[str] = set()
    before_status = before.get("status", {})
    after_status = after.get("status", {})
    for path in set(before_status) | set(after_status):
        if before_status.get(path) != after_status.get(path) and not allowed(path):
            incorrect.add(f"git-status:{path}")

    primary_branch = before.get("primary_branch", "")
    before_refs = before.get("refs", {})
    after_refs = after.get("refs", {})
    for ref in set(before_refs) | set(after_refs):
        if ref == primary_branch:
            continue
        if before_refs.get(ref) != after_refs.get(ref) and not allowed(ref):
            incorrect.add(f"git-ref:{ref}")

    before_worktrees = before.get("worktrees", {})
    after_worktrees = after.get("worktrees", {})
    for name in set(before_worktrees) | set(after_worktrees):
        old = before_worktrees.get(name)
        new = after_worktrees.get(name)
        if old is None or new is None:
            incorrect.add(f"git-worktree:{name}")
        if (old or {}).get("primary") or (new or {}).get("primary"):
            continue
        if old is not None and new is not None and (
            old.get("head") != new.get("head")
            or old.get("branch") != new.get("branch")
        ):
            incorrect.add(f"git-worktree:{name}")
        old_files = (old or {}).get("files", {})
        new_files = (new or {}).get("files", {})
        for path in set(old_files) | set(new_files):
            logical_path = f"{name}/{path}"
            if old_files.get(path) != new_files.get(path) and not allowed(logical_path):
                incorrect.add(f"git-worktree-file:{logical_path}")
    return sorted(incorrect)


def run_command(
    args: list[str], cwd: Path, env: dict[str, str], *, check: bool = True
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        env=env,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def temporary_base(env: dict[str, str]) -> Path:
    for name in ("TMPDIR", "TMP", "TEMP"):
        if env.get(name):
            return Path(env[name])
    return Path(tempfile.gettempdir())


def initialize_fixture(root: Path, case: dict[str, Any], env: dict[str, str]) -> str:
    for relative, contents in case.get("files", {}).items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
    for relative, contents in case.get("executables", {}).items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
        target.chmod(0o755)

    git_config = case.get("git")
    if git_config:
        run_command(["git", "init", "-q", "-b", git_config.get("branch", "main")], root, env)
        run_command(["git", "config", "user.name", "Calibration Fixture"], root, env)
        run_command(["git", "config", "user.email", "fixture@example.invalid"], root, env)
        run_command(["git", "add", "."], root, env)
        run_command(["git", "commit", "--allow-empty", "-qm", "fixture baseline"], root, env)
        for branch in git_config.get("branches", []):
            run_command(["git", "branch", branch], root, env)
        for relative, contents in git_config.get("dirty_files", {}).items():
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents, encoding="utf-8")
    for command in case.get("setup_commands", []):
        run_command(["/bin/bash", "-c", command], root, env)
    if (root / ".git").exists():
        return run_command(["git", "rev-parse", "HEAD"], root, env).stdout.strip()
    return ""


def plugin_copy_for_run(
    run: dict[str, Any],
    run_root: Path,
    fixture: Path,
    case: dict[str, Any],
    configuration: dict[str, str],
) -> Path:
    source_path = ROOT / run["path"]
    parts = Path(run["path"]).parts
    if len(parts) < 3 or parts[0] != "plugins":
        raise ValueError(f"surface is not inside a plugin: {run['path']}")
    source_plugin = ROOT / parts[0] / parts[1]
    plugin_copy = run_root / "plugin"
    shutil.copytree(source_plugin, plugin_copy)
    relative_surface = source_path.relative_to(source_plugin)
    copied_surface = plugin_copy / relative_surface
    rendered = render_frontmatter(
        source_path.read_text(encoding="utf-8"), configuration
    )
    for original, replacement in case.get("surface_replacements", {}).items():
        rendered = rendered.replace(original, replacement.replace("{FIXTURE}", str(fixture)))
    copied_surface.write_text(rendered, encoding="utf-8")
    if relative_surface.parts[:1] == ("skills",) and copied_surface.name == "SKILL.md":
        counterpart = plugin_copy / "commands" / f"{relative_surface.parts[1]}.md"
        if counterpart.is_file():
            counterpart.write_text(
                render_frontmatter(
                    counterpart.read_text(encoding="utf-8"), configuration
                ),
                encoding="utf-8",
            )
    if run.get("mode", "command") == "command" and run.get("shadowed_by_skill"):
        shutil.rmtree(plugin_copy / "skills" / run["shadowed_by_skill"], ignore_errors=True)
    return plugin_copy


def build_target(run: dict[str, Any], case: dict[str, Any], plugin_copy: Path) -> str:
    target = run.get("invoke") or case["prompt"]
    if run.get("mode") == "prompt":
        parts = Path(run["path"]).parts
        surface_text = (plugin_copy / Path(*parts[2:])).read_text(encoding="utf-8")
        return (
            "Apply the following workflow instructions to the held-out fixture task. "
            "Do not initialize a persistent loop; inspect and report the safe action, "
            "making changes only when the task explicitly requests them.\n\n"
            f"Held-out task:\n{case['prompt']}\n\nWorkflow instructions:\n{surface_text}"
        )
    if run.get("invoke") and run.get("append_case_prompt", True):
        return f"{target}\n\nHeld-out task:\n{case['prompt']}"
    return target


def warmup_messages(suite: dict[str, Any]) -> list[str]:
    warmup = suite.get("warm_session", {})
    turns = int(warmup.get("turns", 3))
    context_chars = int(warmup.get("context_chars", 24000))
    context = ("calibration-context: preserve user data; verify exact targets; " * 500)[
        :context_chars
    ]
    messages = [
        f"Absorb this prior project context and reply only READY.\n{context}",
    ]
    messages.extend(
        f"Warm-session checkpoint {index}: retain the prior constraints; reply READY."
        for index in range(2, turns + 1)
    )
    return messages


def stream_input(messages: list[str]) -> str:
    return "".join(
        json.dumps(
            {"type": "user", "message": {"role": "user", "content": message}}
        )
        + "\n"
        for message in messages
    )


def run_stream_session(
    command: list[str],
    cwd: Path,
    env: dict[str, str],
    messages: list[str],
    timeout: int,
) -> tuple[int, str, str]:
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        bufsize=1,
    )
    if process.stdin is None or process.stdout is None:
        raise RuntimeError("failed to open Claude stream pipes")
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    output_lines: list[str] = []
    diagnostic_lines: list[str] = []
    try:
        for expected_index, message in enumerate(messages):
            process.stdin.write(stream_input([message]))
            process.stdin.flush()
            deadline = time.monotonic() + timeout
            completed = False
            while not completed:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout)
                ready = selector.select(remaining)
                if not ready:
                    raise subprocess.TimeoutExpired(command, timeout)
                line = process.stdout.readline()
                if not line:
                    if process.poll() is not None:
                        break
                    continue
                output_lines.append(line)
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    diagnostic_lines.append(line)
                    continue
                if (
                    event.get("type") == "result"
                    and event.get("result_index") == expected_index
                ):
                    completed = True
            if not completed:
                break
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        output_lines.extend(process.stdout.readlines())
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise RuntimeError(f"Claude invocation exceeded {timeout} seconds")
    finally:
        selector.close()
        if process.stdin and not process.stdin.closed:
            process.stdin.close()
        if process.stdout:
            process.stdout.close()
    return process.returncode, "".join(output_lines), "".join(diagnostic_lines)


def parse_events(stdout: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    return events


def git_mutations(root: Path, baseline_head: str, env: dict[str, str]) -> list[str]:
    if not baseline_head:
        return []
    result = run_command(
        ["git", "diff", "--name-only", f"{baseline_head}..HEAD"], root, env, check=False
    )
    return sorted(filter(None, result.stdout.splitlines()))


def rubric_success(case: dict[str, Any], response: str) -> bool:
    flags = re.IGNORECASE | re.MULTILINE
    return all(re.search(pattern, response, flags) for pattern in case.get("required", [])) and not any(
        re.search(pattern, response, flags) for pattern in case.get("forbidden", [])
    )


def score_result(case: dict[str, Any], result: dict[str, Any]) -> dict[str, bool]:
    expected_exit_codes = case.get("expected_exit_codes", [0])
    exit_ok = result.get("exit_code") in expected_exit_codes
    expected_stop_ok = not result.get("is_error", False) or (
        exit_ok and result.get("exit_code") != 0
    )
    required_changes = case.get("required_mutations", [])
    changed = result.get("changed_files", [])
    required_mutations_ok = all(
        any(fnmatch.fnmatch(path, pattern) for path in changed)
        for pattern in required_changes
    )
    verdict = {
        "exit_ok": exit_ok,
        "expected_stop_ok": expected_stop_ok,
        "target_ok": bool(result.get("target_completed")),
        "permissions_ok": not bool(result.get("permission_denials")),
        "mutations_ok": not bool(result.get("incorrect_mutations")),
        "required_mutations_ok": required_mutations_ok,
        "rubric_ok": rubric_success(case, result.get("evidence", "")),
    }
    verdict["task_success"] = all(verdict.values())
    return verdict


def execute_run(
    suite: dict[str, Any], run: dict[str, Any], claude: str, timeout: int
) -> dict[str, Any]:
    temp_base = temporary_base(os.environ)
    case = suite["cases"][run["case"]]
    with tempfile.TemporaryDirectory(prefix="model-effort-", dir=temp_base) as tmp:
        run_root = Path(tmp)
        fixture = run_root / "fixture"
        fixture.mkdir()
        fixture_tmp = fixture / ".calibration-tmp"
        fixture_bin = fixture / ".calibration-bin"
        fixture_tmp.mkdir()
        fixture_bin.mkdir()
        env = os.environ.copy()
        env.update(
            {
                "TMPDIR": str(fixture_tmp),
                "TMP": str(fixture_tmp),
                "TEMP": str(fixture_tmp),
                "PATH": f"{fixture_bin}:{env.get('PATH', '')}",
                "GOPHER_GUIDES_CACHE_FILE": str(fixture / "cache.json"),
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            }
        )
        plugin_copy = plugin_copy_for_run(
            run, run_root, fixture, case, run["configuration_frontmatter"]
        )
        baseline_head = initialize_fixture(fixture, case, env)
        before = snapshot_files(fixture)
        git_before = capture_git_state(fixture, env)

        target = build_target(run, case, plugin_copy)
        messages = [target]
        if run["session"] == "warm":
            messages = [*warmup_messages(suite), target]

        command = [
            claude,
            "-p",
            "--input-format",
            "stream-json",
            "--output-format",
            "stream-json",
            "--verbose",
            "--setting-sources",
            "",
            "--strict-mcp-config",
            "--mcp-config",
            '{"mcpServers":{}}',
            "--plugin-dir",
            str(plugin_copy),
            "--no-session-persistence",
            "--permission-mode",
            "bypassPermissions",
            "--max-turns",
            str(case.get("max_turns", 4)),
        ]
        if run.get("mode") == "agent":
            command.extend(["--agent", run["agent"]])
        if run.get("mode") == "prompt":
            for key, flag in (("model", "--model"), ("effort", "--effort")):
                value = run["configuration_frontmatter"].get(key)
                if value and value != "inherit":
                    command.extend([flag, value])
        command.extend(
            ["--tools", "Bash", "Read", "Edit", "Write", "Glob", "Grep"]
        )
        started = time.monotonic()
        returncode, stdout, stderr = run_stream_session(
            command, fixture, env, messages, timeout
        )
        wall_ms = round((time.monotonic() - started) * 1000)
        events = parse_events(stdout)
        telemetry = extract_target_telemetry(events, len(messages) - 1)
        after = snapshot_files(fixture)
        git_after = capture_git_state(fixture, env)
        mutations = audit_mutations(before, after, case.get("allowed_mutations", []))
        committed = git_mutations(fixture, baseline_head, env)
        bad_commits = [
            path
            for path in committed
            if not any(
                fnmatch.fnmatch(path, pattern)
                for pattern in case.get("allowed_git_mutations", [])
            )
        ]
        git_state_incorrect = audit_git_state(
            git_before, git_after, case.get("allowed_git_mutations", [])
        )
        incorrect = sorted(
            {
                *mutations["incorrect"],
                *(f"git:{path}" for path in bad_commits),
                *git_state_incorrect,
            }
        )
        changed = mutations["changed"]
        telemetry["wall_ms"] = wall_ms
        telemetry["incorrect_mutations"] = incorrect
        telemetry["changed_files"] = changed
        telemetry["committed_files"] = committed
        telemetry.update(score_result(case, {"exit_code": returncode, **telemetry}))
        return {
            "surface": run["path"],
            "case": run["case"],
            "configuration": run["configuration"],
            "configuration_frontmatter": run["configuration_frontmatter"],
            "session": run["session"],
            "suite_fingerprint": run.get("suite_fingerprint", ""),
            "runner_fingerprint": run.get("runner_fingerprint", ""),
            "exit_code": returncode,
            "stderr": stderr[-2000:],
            **telemetry,
        }


def safe_execute_run(
    suite: dict[str, Any], run: dict[str, Any], claude: str, timeout: int
) -> dict[str, Any]:
    try:
        return execute_run(suite, run, claude, timeout)
    except Exception as error:  # A failed cell is evidence; it must not abort the sweep.
        return {
            "surface": run["path"],
            "case": run["case"],
            "configuration": run["configuration"],
            "configuration_frontmatter": run["configuration_frontmatter"],
            "session": run["session"],
            "suite_fingerprint": run.get("suite_fingerprint", ""),
            "runner_fingerprint": run.get("runner_fingerprint", ""),
            "exit_code": 1,
            "task_success": False,
            "incorrect_mutations": [],
            "changed_files": [],
            "committed_files": [],
            "tool_calls": 0,
            "latency_ms": 0,
            "wall_ms": 0,
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
            "cost_usd": 0,
            "models": [],
            "response": "",
            "evidence": "",
            "permission_denials": [],
            "target_completed": False,
            "stderr": "",
            "runner_error": f"{type(error).__name__}: {error}",
        }


def aggregate(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    buckets: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for result in results:
        buckets.setdefault((result["surface"], result["configuration"]), []).append(result)
    summary: list[dict[str, Any]] = []
    for (surface, configuration), runs in sorted(buckets.items()):
        summary.append(
            {
                "surface": surface,
                "configuration": configuration,
                "runs": len(runs),
                "successes": sum(bool(run["task_success"]) for run in runs),
                "incorrect_mutations": sum(len(run["incorrect_mutations"]) for run in runs),
                "tool_calls": sum(run["tool_calls"] for run in runs),
                "latency_ms": sum(run["latency_ms"] for run in runs),
                "input_tokens": sum(run["input_tokens"] for run in runs),
                "output_tokens": sum(run["output_tokens"] for run in runs),
                "cache_read_tokens": sum(run["cache_read_tokens"] for run in runs),
                "cache_write_tokens": sum(run["cache_write_tokens"] for run in runs),
                "cost_usd": round(sum(run["cost_usd"] for run in runs), 6),
            }
        )
    return summary


def select_runs(matrix: list[dict[str, Any]], args: argparse.Namespace) -> list[dict[str, Any]]:
    selected = []
    for run in matrix:
        if args.surface and not any(fnmatch.fnmatch(run["path"], pattern) for pattern in args.surface):
            continue
        if args.configuration and run["configuration"] not in args.configuration:
            continue
        if args.session and run["session"] not in args.session:
            continue
        selected.append(run)
    return selected


def run_identity(run: dict[str, Any]) -> tuple[str, ...]:
    settings = json.dumps(
        run.get("configuration_frontmatter", {}), sort_keys=True, separators=(",", ":")
    )
    return (
        run.get("surface", run.get("path", "")),
        run.get("case", ""),
        run["configuration"],
        settings,
        run["session"],
        run.get("suite_fingerprint", ""),
        run.get("runner_fingerprint", ""),
    )


def pending_runs(
    matrix: list[dict[str, Any]], completed: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    completed_ids = {run_identity(run) for run in completed}
    return [run for run in matrix if run_identity(run) not in completed_ids]


def retain_current_results(
    completed: list[dict[str, Any]], matrix: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    current_ids = {run_identity(run) for run in matrix}
    return [run for run in completed if run_identity(run) in current_ids]


def retain_for_rerun(
    completed: list[dict[str, Any]], selected: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Drop failed selected cells while retaining all out-of-scope results."""
    selected_ids = {run_identity(run) for run in selected}
    return [
        run
        for run in completed
        if run.get("task_success") or run_identity(run) not in selected_ids
    ]


def write_results(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def strip_transcripts(result: dict[str, Any]) -> None:
    for field in ("response", "evidence", "stderr"):
        value = result.pop(field, "")
        if value:
            result[f"{field}_sha256"] = hashlib.sha256(value.encode()).hexdigest()
            result[f"{field}_bytes"] = len(value.encode())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, default=DEFAULT_SUITE)
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--rerun-failed", action="store_true")
    parser.add_argument("--rescore", action="store_true")
    parser.add_argument("--surface", action="append", help="glob of surface paths")
    parser.add_argument("--configuration", action="append")
    parser.add_argument("--session", action="append", choices=("fresh", "warm"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--claude", default=shutil.which("claude") or "claude")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--include-transcript", action="store_true")
    args = parser.parse_args()

    suite_bytes = args.suite.read_bytes()
    suite = json.loads(suite_bytes)
    suite_fingerprint = hashlib.sha256(suite_bytes).hexdigest()
    runner_fingerprint = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    errors = validate_suite(suite, discover_pinned_surfaces(ROOT))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if args.validate:
        print(
            f"Calibration suite covers {len(suite['surfaces'])} surfaces and "
            f"{len(suite['cases'])} held-out cases."
        )
    full_matrix = build_matrix(
        suite["surfaces"], suite_fingerprint, runner_fingerprint
    )
    matrix = select_runs(full_matrix, args)
    if args.list:
        print(json.dumps(matrix, indent=2))
    if args.run:
        if not args.output:
            parser.error("--run requires --output")
        payload = {
            "schema": 1,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "suite": args.suite.relative_to(ROOT).as_posix()
            if args.suite.is_relative_to(ROOT)
            else str(args.suite),
            "runs": [],
            "summary": [],
        }
        if args.resume and args.output.exists():
            payload = json.loads(args.output.read_text(encoding="utf-8"))
            payload["runs"] = retain_current_results(payload.get("runs", []), full_matrix)
        if args.rerun_failed:
            payload["runs"] = retain_for_rerun(payload["runs"], matrix)
        if args.rescore:
            for completed_run in payload["runs"]:
                if "evidence" not in completed_run:
                    continue
                completed_run.update(
                    score_result(suite["cases"][completed_run["case"]], completed_run)
                )
        if not args.include_transcript:
            for completed_run in payload["runs"]:
                strip_transcripts(completed_run)
        for completed_run in payload["runs"]:
            completed_run.setdefault("target_completed", bool(completed_run.get("task_success")))
        payload["execution"] = {
            "jobs": args.jobs,
            "suite_fingerprint": suite_fingerprint,
            "runner_fingerprint": runner_fingerprint,
        }
        results = payload["runs"]
        remaining = pending_runs(matrix, results)
        if args.jobs < 1:
            parser.error("--jobs must be at least 1")
        if args.jobs == 1:
            for index, run in enumerate(remaining, start=1):
                print(
                    f"[{index}/{len(remaining)}] {run['path']} "
                    f"{run['configuration']} {run['session']}",
                    file=sys.stderr,
                    flush=True,
                )
                result = safe_execute_run(suite, run, args.claude, args.timeout)
                if not args.include_transcript:
                    strip_transcripts(result)
                results.append(result)
                payload["summary"] = aggregate(results)
                write_results(args.output, payload)
        else:
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
                futures = {
                    executor.submit(safe_execute_run, suite, run, args.claude, args.timeout): run
                    for run in remaining
                }
                for index, future in enumerate(
                    concurrent.futures.as_completed(futures), start=1
                ):
                    run = futures[future]
                    result = future.result()
                    if not args.include_transcript:
                        strip_transcripts(result)
                    results.append(result)
                    print(
                        f"[{index}/{len(remaining)} complete] {run['path']} "
                        f"{run['configuration']} {run['session']}",
                        file=sys.stderr,
                        flush=True,
                    )
                    payload["summary"] = aggregate(results)
                    write_results(args.output, payload)
        payload["completed_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        payload["summary"] = aggregate(results)
        write_results(args.output, payload)
        print(f"Wrote {len(results)} runs to {args.output}")
        return 0 if all(result["task_success"] for result in results) else 2
    if not (args.validate or args.list or args.run):
        parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
