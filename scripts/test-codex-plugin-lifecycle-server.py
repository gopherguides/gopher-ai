#!/usr/bin/env python3

import argparse
import json
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class LifecycleHandler(SimpleHTTPRequestHandler):
    request_count = 0
    request_lock = threading.Lock()
    state_dir = Path()

    def do_POST(self):
        if self.path != "/v1/responses":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(content_length)

        with self.request_lock:
            type(self).request_count += 1
            request_number = type(self).request_count

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
        events = [
            {
                "type": "response.created",
                "response": {"id": response_id},
            },
            {
                "type": "response.output_item.done",
                "item": {
                    "type": "message",
                    "role": "assistant",
                    "id": response_id,
                    "content": [
                        {"type": "output_text", "text": "lifecycle-ok"}
                    ],
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
        body = "".join(
            f"event: {event['type']}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n"
            for event in events
        ).encode("utf-8")

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
