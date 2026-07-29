#!/usr/bin/env python3

import json
import os
import queue
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


QUESTION = "Commit them before shipping, or abort?"
UNAVAILABLE_MESSAGE = "request_user_input is unavailable in Default mode"


def response_events(response_id, output_item):
    events = [
        {
            "type": "response.created",
            "response": {"id": response_id},
        },
        {
            "type": "response.output_item.done",
            "item": output_item,
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

        if request_number == 1:
            arguments = json.dumps(
                {
                    "questions": [
                        {
                            "id": "dirty_tree",
                            "header": "Dirty tree",
                            "question": QUESTION,
                            "options": [
                                {
                                    "label": "Commit (Recommended)",
                                    "description": "Commit the current changes before shipping.",
                                },
                                {
                                    "label": "Abort",
                                    "description": "Stop the ship workflow.",
                                },
                            ],
                        }
                    ]
                },
                separators=(",", ":"),
            )
            output_item = {
                "type": "function_call",
                "call_id": "request-input-1",
                "name": "request_user_input",
                "arguments": arguments,
            }
        else:
            output_item = {
                "type": "message",
                "role": "assistant",
                "id": "fallback-question",
                "content": [{"type": "output_text", "text": QUESTION}],
            }

        body = response_events(f"response-{request_number}", output_item)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


class AppServerClient:
    def __init__(self, command, env):
        self.process = subprocess.Popen(
            command,
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

    def wait_for_notification(self, method):
        deadline = time.monotonic() + 15
        observed = []
        while time.monotonic() < deadline:
            try:
                message = self.messages.get(timeout=deadline - time.monotonic())
            except queue.Empty as error:
                raise AssertionError(f"timed out waiting for {method}") from error
            if message is None:
                raise AssertionError(
                    f"app-server exited while waiting for {method}: {''.join(self.stderr)}"
                )
            observed.append(message)
            if message.get("method") == "item/tool/requestUserInput":
                raise AssertionError("Default mode unexpectedly emitted a typed input request")
            if message.get("method") == method:
                return message, observed
        raise AssertionError(f"timed out waiting for {method}")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)


def main():
    ProbeResponsesHandler.request_bodies = []
    server = ThreadingHTTPServer(("127.0.0.1", 0), ProbeResponsesHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    temp_base = os.environ.get("TMPDIR") or os.environ.get("TMP") or os.environ.get("TEMP")
    with tempfile.TemporaryDirectory(prefix="gopher-ai-codex-input-", dir=temp_base) as root:
        test_root = Path(root)
        codex_home = test_root / ".codex"
        codex_home.mkdir()
        provider = (
            '{ name = "Probe", '
            f'base_url = "http://127.0.0.1:{server.server_port}/v1", '
            'env_key = "OPENAI_API_KEY", wire_api = "responses", '
            "supports_websockets = false }"
        )
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(test_root),
                "CODEX_HOME": str(codex_home),
                "OPENAI_API_KEY": "dummy",
            }
        )
        client = AppServerClient(
            [
                "codex",
                "app-server",
                "--stdio",
                "-c",
                'model_provider="probe"',
                "-c",
                f"model_providers.probe={provider}",
            ],
            env,
        )
        try:
            client.request(
                "initialize",
                {
                    "clientInfo": {
                        "name": "gopher_ai_default_mode_probe",
                        "title": "Gopher AI Default Mode Probe",
                        "version": "1.0.0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            )
            client.send({"method": "initialized", "params": {}})

            collaboration_modes = client.request("collaborationMode/list", {})
            mode_names = {
                item.get("mode") for item in collaboration_modes["data"] if item.get("mode")
            }
            if mode_names != {"default", "plan"}:
                raise AssertionError(
                    f"expected Default and Plan collaboration modes, got {sorted(mode_names)}"
                )

            thread_result = client.request(
                "thread/start",
                {
                    "model": "mock-model",
                    "modelProvider": "probe",
                    "cwd": str(test_root),
                    "approvalPolicy": "never",
                    "ephemeral": True,
                },
            )
            thread_id = thread_result["thread"]["id"]
            client.request(
                "turn/start",
                {
                    "threadId": thread_id,
                    "input": [
                        {
                            "type": "text",
                            "text": "Apply the representative shared ship-skill dirty-tree gate.",
                        }
                    ],
                    "model": "mock-model",
                    "effort": "medium",
                    "approvalPolicy": "never",
                    "collaborationMode": {
                        "mode": "default",
                        "settings": {
                            "model": "mock-model",
                            "reasoning_effort": "medium",
                            "developer_instructions": None,
                        },
                    },
                },
            )

            completion, observed = client.wait_for_notification("turn/completed")
            if completion["params"]["turn"]["status"] != "completed":
                raise AssertionError(f"turn did not complete: {completion}")
            if QUESTION not in json.dumps(observed):
                raise AssertionError("the fallback question was not emitted as assistant prose")
            if "waitingOnUserInput" in json.dumps(observed):
                raise AssertionError("Default mode unexpectedly waited on typed user input")

            request_bodies = ProbeResponsesHandler.request_bodies
            if len(request_bodies) != 2:
                raise AssertionError(
                    f"expected two Responses requests, got {len(request_bodies)}"
                )
            tool_names = {
                tool.get("name")
                for tool in request_bodies[0].get("tools", [])
                if isinstance(tool, dict)
            }
            if "request_user_input" not in tool_names:
                raise AssertionError(
                    "the Default-mode model request did not advertise request_user_input"
                )
            if UNAVAILABLE_MESSAGE not in json.dumps(request_bodies[1]):
                raise AssertionError("the Default-mode tool rejection was not returned to the model")

            thread = client.request(
                "thread/read", {"threadId": thread_id, "includeTurns": False}
            )["thread"]
            if thread["status"] != {"type": "idle"}:
                raise AssertionError(f"thread did not return to idle: {thread['status']}")
        finally:
            client.close()
            server.shutdown()
            server.server_close()

    print("Codex Default-mode input probe passed.")


if __name__ == "__main__":
    main()
