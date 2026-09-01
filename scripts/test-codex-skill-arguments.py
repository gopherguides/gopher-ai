#!/usr/bin/env python3

import argparse
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
WORKFLOW_ROOT = ROOT_DIR / "plugins/go-workflow"
ARGUMENT_SKILLS = {
    "address-review",
    "cancel-loop",
    "complete-issue",
    "e2e-verify",
    "review-deep",
    "ship",
    "start-issue",
    "tmux-start",
}
COMPATIBILITY_PAYLOAD = (
    "<claude-skill-arguments>\n$ARGUMENTS\n</claude-skill-arguments>"
)
PROBES = (
    ("tmux-start", "$go-workflow:tmux-start 325"),
    ("cancel-loop", "$go-workflow:cancel-loop ship"),
    ("ship", "$go-workflow:ship --no-merge"),
)


def response_events(response_id):
    events = [
        {"type": "response.created", "response": {"id": response_id}},
        {
            "type": "response.output_item.done",
            "item": {
                "type": "message",
                "role": "assistant",
                "id": response_id,
                "content": [{"type": "output_text", "text": "probe-ok"}],
            },
        },
        {
            "type": "response.completed",
            "response": {
                "id": response_id,
                "usage": {
                    "input_tokens": 0,
                    "input_tokens_details": None,
                    "output_tokens": 0,
                    "output_tokens_details": None,
                    "total_tokens": 0,
                },
            },
        },
    ]
    return "".join(
        f"event: {event['type']}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n"
        for event in events
    ).encode()


class ProbeResponsesHandler(BaseHTTPRequestHandler):
    request_bodies = []
    request_lock = threading.Lock()

    def do_POST(self):
        if self.path != "/v1/responses":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        request_body = json.loads(self.rfile.read(content_length))
        with self.request_lock:
            self.request_bodies.append(request_body)
            request_number = len(self.request_bodies)

        body = response_events(f"response-{request_number}")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


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


def cleanup_temp_tree(
    path,
    *,
    attempts=20,
    delay=0.1,
    remove=shutil.rmtree,
    pause=time.sleep,
    path_exists=lambda candidate: candidate.exists(),
):
    for attempt in range(attempts):
        try:
            remove(path)
            return
        except OSError as error:
            if isinstance(error, FileNotFoundError) and not path_exists(path):
                return
            if attempt == attempts - 1:
                raise
            pause(delay)


def assert_static_contract():
    argument_contract = " ".join(
        (WORKFLOW_ROOT / "lib/skill-arguments.md")
        .read_text(encoding="utf-8")
        .split()
    )
    composed_rule = "caller-provided `SKILL_ARGS`"
    empty_value_rule = "including an explicitly empty value"
    compatibility_rule = "trimmed compatibility payload"
    for rule in (composed_rule, empty_value_rule, compatibility_rule):
        if rule not in argument_contract:
            raise AssertionError(f"shared argument contract is missing: {rule}")
    if argument_contract.index(composed_rule) > argument_contract.index(
        compatibility_rule
    ):
        raise AssertionError(
            "composed workflow arguments must take precedence over host binding"
        )

    discovered = set()
    for skill_file in (WORKFLOW_ROOT / "skills").glob("*/SKILL.md"):
        text = skill_file.read_text(encoding="utf-8")
        if "\nargument-hint:" not in text:
            continue

        skill_name = skill_file.parent.name
        discovered.add(skill_name)
        if "`<PLUGIN_ROOT>/lib/skill-arguments.md`" not in text:
            raise AssertionError(f"{skill_name} does not load the shared argument contract")
        if f"`$go-workflow:{skill_name}`" not in text:
            raise AssertionError(f"{skill_name} does not identify its qualified invocation")
        if text.count(COMPATIBILITY_PAYLOAD) != 1:
            raise AssertionError(
                f"{skill_name} must contain exactly one Claude compatibility payload"
            )
        if "$ARGUMENTS" in text.replace(COMPATIBILITY_PAYLOAD, ""):
            raise AssertionError(f"{skill_name} still parses or describes $ARGUMENTS")
        if "SKILL_ARGS" not in text:
            raise AssertionError(f"{skill_name} does not parse the bound SKILL_ARGS value")

    if discovered != ARGUMENT_SKILLS:
        raise AssertionError(
            "argument-bearing skill set changed: "
            f"expected {sorted(ARGUMENT_SKILLS)}, got {sorted(discovered)}"
        )

    support_files = list((WORKFLOW_ROOT / "lib").rglob("*.md"))
    for skill_name in ARGUMENT_SKILLS:
        support_files.extend(
            path
            for path in (WORKFLOW_ROOT / "skills" / skill_name).glob("*.md")
            if path.name != "SKILL.md"
        )
    for path in support_files:
        if path.name == "skill-arguments.md":
            continue
        if "$ARGUMENTS" in path.read_text(encoding="utf-8"):
            raise AssertionError(
                f"{path.relative_to(ROOT_DIR)} still relies on $ARGUMENTS"
            )


def assert_cleanup_retry_contract():
    path = Path("fixture")
    attempts = []
    pauses = []

    def transient_remove(candidate):
        attempts.append(candidate)
        if len(attempts) < 3:
            raise OSError("directory not empty")

    cleanup_temp_tree(
        path,
        attempts=3,
        delay=0.25,
        remove=transient_remove,
        pause=pauses.append,
    )
    if attempts != [path, path, path] or pauses != [0.25, 0.25]:
        raise AssertionError("temporary tree cleanup did not retry bounded failures")

    descendant_attempts = []
    descendant_pauses = []

    def descendant_disappears(candidate):
        descendant_attempts.append(candidate)
        if len(descendant_attempts) == 1:
            raise FileNotFoundError("descendant disappeared")

    cleanup_temp_tree(
        path,
        attempts=2,
        delay=0.25,
        remove=descendant_disappears,
        pause=descendant_pauses.append,
        path_exists=lambda _: True,
    )
    if descendant_attempts != [path, path] or descendant_pauses != [0.25]:
        raise AssertionError("temporary tree cleanup accepted a missing descendant")

    def persistent_remove(candidate):
        raise OSError(f"cannot remove {candidate}")

    try:
        cleanup_temp_tree(
            path,
            attempts=2,
            delay=0,
            remove=persistent_remove,
            pause=lambda _: None,
        )
    except OSError:
        pass
    else:
        raise AssertionError("temporary tree cleanup suppressed a persistent failure")


def run_live_probe(env, workspace, provider, skill_name, invocation):
    request_offset = len(ProbeResponsesHandler.request_bodies)
    run_codex(
        env,
        workspace,
        "exec",
        "--cd",
        str(workspace),
        "--skip-git-repo-check",
        "--dangerously-bypass-hook-trust",
        "--sandbox",
        "read-only",
        "--ephemeral",
        "-c",
        'model_provider="probe"',
        "-c",
        f"model_providers.probe={provider}",
        invocation,
    )

    requests = ProbeResponsesHandler.request_bodies[request_offset:]
    if len(requests) != 1:
        raise AssertionError(
            f"{skill_name} probe expected one model request, got {len(requests)}"
        )

    request_text = json.dumps(requests[0])
    if invocation not in request_text:
        raise AssertionError(
            f"Codex did not preserve the explicit {skill_name} invocation text"
        )
    binding_instruction = (
        "Bind the invocation arguments as `SKILL_ARGS` for "
        f"`$go-workflow:{skill_name}`"
    )
    if binding_instruction not in request_text:
        raise AssertionError(
            f"Codex did not load the {skill_name} argument-binding instruction"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--static-only", action="store_true")
    args = parser.parse_args()

    assert_static_contract()
    assert_cleanup_retry_contract()
    if args.static_only:
        print("Workflow skill argument contract checks passed.")
        return

    ProbeResponsesHandler.request_bodies = []
    server = ThreadingHTTPServer(("127.0.0.1", 0), ProbeResponsesHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    temp_base = os.environ.get("TMPDIR") or os.environ.get("TMP") or os.environ.get("TEMP")
    test_root = None
    try:
        test_root = Path(
            tempfile.mkdtemp(prefix="gopher-ai-skill-arguments-", dir=temp_base)
        )
        codex_home = test_root / ".codex"
        workspace = test_root / "workspace"
        codex_home.mkdir()
        workspace.mkdir()
        env = os.environ.copy()
        env.pop("ARGUMENTS", None)
        env.update(
            {
                "HOME": str(test_root),
                "CODEX_HOME": str(codex_home),
                "OPENAI_API_KEY": "dummy",
            }
        )
        provider = (
            '{ name = "Probe", '
            f'base_url = "http://127.0.0.1:{server.server_port}/v1", '
            'env_key = "OPENAI_API_KEY", wire_api = "responses", '
            "supports_websockets = false }"
        )

        run_codex(env, test_root, "plugin", "marketplace", "add", str(ROOT_DIR), "--json")
        run_codex(env, test_root, "plugin", "add", "go-workflow@gopher-ai", "--json")
        for skill_name, invocation in PROBES:
            run_live_probe(env, workspace, provider, skill_name, invocation)
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)
        if test_root is not None:
            cleanup_temp_tree(test_root)

    print("Codex skill argument probes passed: positional targets and flag.")


if __name__ == "__main__":
    main()
