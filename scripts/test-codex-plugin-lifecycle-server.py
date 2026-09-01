#!/usr/bin/env python3

import argparse
import json
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


PROBE_SENTINEL = "lifecycle-post-tool-use-probe"
PROBE_CALL_ID = "post-tool-use-probe"
PROBE_COMMAND = "printf '%s\\n' 'probe.go:1:1: undefined: lifecycleProbe' >&2; exit 1"


def nested_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nested_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from nested_objects(child)


def has_probe_output(request_body):
    return any(
        item.get("type") in ("function_call_output", "custom_tool_call_output")
        and item.get("call_id") == PROBE_CALL_ID
        for item in nested_objects(request_body)
    )


def probe_call(request_body):
    tools = {
        item.get("name"): item
        for item in nested_objects(request_body)
        if isinstance(item.get("name"), str)
        and isinstance(item.get("parameters"), dict)
    }
    for name in ("shell_command", "exec_command"):
        if name not in tools:
            continue
        properties = tools[name].get("parameters", {}).get("properties", {})
        command_argument = next(
            (candidate for candidate in ("command", "cmd") if candidate in properties),
            None,
        )
        if command_argument is not None:
            return {
                "type": "function_call",
                "call_id": PROBE_CALL_ID,
                "name": name,
                "arguments": json.dumps(
                    {command_argument: PROBE_COMMAND}, separators=(",", ":")
                ),
            }
    custom_exec = next(
        (
            item
            for item in nested_objects(request_body)
            if item.get("type") == "custom" and item.get("name") == "exec"
        ),
        None,
    )
    if custom_exec is not None:
        command = json.dumps(PROBE_COMMAND)
        code = (
            "try {\n"
            f"  const result = await tools.exec_command({{cmd: {command}}});\n"
            "  text(result.output);\n"
            "} catch (error) {\n"
            "  text(String(error));\n"
            "}"
        )
        return {
            "type": "custom_tool_call",
            "call_id": PROBE_CALL_ID,
            "name": "exec",
            "input": code,
        }
    raise ValueError("no supported shell tool was advertised")


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
    ).encode("utf-8")


class LifecycleHandler(SimpleHTTPRequestHandler):
    request_count = 0
    request_lock = threading.Lock()
    state_dir = Path()

    def do_POST(self):
        if self.path != "/v1/responses":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        request_body = json.loads(self.rfile.read(content_length))

        with self.request_lock:
            type(self).request_count += 1
            request_number = type(self).request_count

        self.state_dir.joinpath(f"{request_number}.request.json").write_text(
            json.dumps(request_body, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        self.state_dir.joinpath(f"{request_number}.requested").write_text(
            self.path, encoding="utf-8"
        )
        release_path = self.state_dir / f"{request_number}.release"
        deadline = time.monotonic() + 90
        while not release_path.exists() and time.monotonic() < deadline:
            time.sleep(0.05)

        if not release_path.exists():
            self.send_error(504, "response release timed out")
            return

        response_id = f"response_{request_number}"
        request_text = json.dumps(request_body, separators=(",", ":"))
        if has_probe_output(request_body):
            output_item = {
                "type": "message",
                "role": "assistant",
                "id": response_id,
                "content": [{"type": "output_text", "text": "lifecycle-hook-ok"}],
            }
        elif PROBE_SENTINEL in request_text:
            try:
                output_item = probe_call(request_body)
            except ValueError as error:
                self.send_error(400, str(error))
                return
        else:
            output_item = {
                "type": "message",
                "role": "assistant",
                "id": response_id,
                "content": [{"type": "output_text", "text": "lifecycle-ok"}],
            }
        body = response_events(response_id, output_item)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--port-file", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    args = parser.parse_args()

    args.state_dir.mkdir(parents=True, exist_ok=True)
    LifecycleHandler.state_dir = args.state_dir

    def handler(*handler_args, **handler_kwargs):
        return LifecycleHandler(
            *handler_args, directory=str(args.directory), **handler_kwargs
        )

    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port_path = args.port_file.with_suffix(".tmp")
    port_path.write_text(str(server.server_port), encoding="utf-8")
    port_path.replace(args.port_file)
    server.serve_forever()


if __name__ == "__main__":
    main()
