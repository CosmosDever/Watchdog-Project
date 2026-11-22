"""Translation proxy: turns a model's plain-JSON tool output into real OpenAI tool_calls.

Some local models (e.g. WhiteRabbitNeo) print a tool call as a bare JSON object
in the message content instead of the structured tool_calls field that agents need.
This proxy sits between the agent (OpenCode) and llama-server, forwards each request
with streaming disabled, extracts any tool call from the reply, and returns a proper
tool_calls response — re-emitting it as an SSE stream when the client asked for one.

Usage: python -I toolshim.py --listen 127.0.0.1:8080 --backend 127.0.0.1:8081
"""
import argparse
import json
import re
import sys
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND = "http://127.0.0.1:8081"
FENCE = re.compile(r"^\s*```(?:json)?\s*|\s*```\s*$", re.IGNORECASE)
TOOLTAG = re.compile(r"</?tool_call>", re.IGNORECASE)
OBJECT = re.compile(r"\{.*\}", re.DOTALL)


def tool_names(payload):
    names = set()
    for tool in payload.get("tools") or []:
        fn = tool.get("function") or {}
        if fn.get("name"):
            names.add(fn["name"])
    return names


def as_arg_string(arguments):
    if isinstance(arguments, str):
        return arguments
    return json.dumps(arguments, ensure_ascii=False)


def extract_calls(content, names):
    """Return a list of tool_calls found in content, or [] if it is a normal reply."""
    if not content:
        return []
    cleaned = TOOLTAG.sub("", content).strip()
    candidates = []
    stripped = FENCE.sub("", cleaned).strip()
    candidates.append(stripped)
    match = OBJECT.search(cleaned)
    if match:
        candidates.append(match.group(0))

    for text in candidates:
        try:
            data = json.loads(text)
        except (ValueError, TypeError):
            continue
        items = []
        if isinstance(data, dict) and isinstance(data.get("tool_calls"), list):
            items = data["tool_calls"]
        elif isinstance(data, list):
            items = data
        elif isinstance(data, dict):
            items = [data]

        calls = []
        for item in items:
            if not isinstance(item, dict):
                continue
            fn = item.get("function") if isinstance(item.get("function"), dict) else item
            name = fn.get("name")
            if name in names and "arguments" in fn or name in names:
                calls.append({
                    "id": "call_" + uuid.uuid4().hex[:24],
                    "type": "function",
                    "function": {"name": name, "arguments": as_arg_string(fn.get("arguments", {}))},
                })
        if calls:
            return calls
    return []


def backend_call(path, body, headers):
    req = urllib.request.Request(BACKEND + path, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=900) as resp:
        return resp.status, resp.read(), resp.headers.get("Content-Type", "application/json")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, status, body, ctype="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _passthrough_get(self):
        req = urllib.request.Request(BACKEND + self.path, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                self._send(resp.status, resp.read(), resp.headers.get("Content-Type", "application/json"))
        except Exception as exc:  # noqa: BLE001
            self._send(502, json.dumps({"error": str(exc)}).encode())

    def do_GET(self):
        self._passthrough_get()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        if not self.path.startswith("/v1/chat/completions"):
            try:
                status, body, ctype = backend_call(self.path, raw, {"Content-Type": "application/json"})
                self._send(status, body, ctype)
            except Exception as exc:  # noqa: BLE001
                self._send(502, json.dumps({"error": str(exc)}).encode())
            return

        try:
            payload = json.loads(raw)
        except ValueError:
            self._send(400, json.dumps({"error": "invalid JSON"}).encode())
            return

        want_stream = bool(payload.get("stream"))
        names = tool_names(payload)
        backend_payload = dict(payload)
        backend_payload["stream"] = False
        data = json.dumps(backend_payload).encode()

        try:
            status, body, _ = backend_call("/v1/chat/completions", data, {"Content-Type": "application/json"})
        except Exception as exc:  # noqa: BLE001
            self._send(502, json.dumps({"error": str(exc)}).encode())
            return

        if status != 200:
            self._send(status, body)
            return

        result = json.loads(body)
        choice = (result.get("choices") or [{}])[0]
        message = choice.get("message", {})
        if names and not message.get("tool_calls"):
            calls = extract_calls(message.get("content"), names)
            if calls:
                message["tool_calls"] = calls
                message["content"] = None
                choice["finish_reason"] = "tool_calls"

        if not want_stream:
            self._send(200, json.dumps(result).encode())
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        for chunk in self._stream_chunks(result, choice, message):
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n")

    def _stream_chunks(self, result, choice, message):
        base = {"id": result.get("id", "chatcmpl-" + uuid.uuid4().hex[:24]),
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": result.get("model", "local")}
        yield {**base, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]}
        if message.get("tool_calls"):
            for idx, call in enumerate(message["tool_calls"]):
                delta = {"tool_calls": [{"index": idx, "id": call["id"], "type": "function",
                                          "function": {"name": call["function"]["name"],
                                                       "arguments": call["function"]["arguments"]}}]}
                yield {**base, "choices": [{"index": 0, "delta": delta, "finish_reason": None}]}
            yield {**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]}
        else:
            content = message.get("content") or ""
            yield {**base, "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": None}]}
            yield {**base, "choices": [{"index": 0, "delta": {}, "finish_reason": choice.get("finish_reason", "stop")}]}


def main():
    global BACKEND
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1:8080")
    parser.add_argument("--backend", default="127.0.0.1:8081")
    args = parser.parse_args()
    BACKEND = "http://" + args.backend
    host, port = args.listen.split(":")
    server = ThreadingHTTPServer((host, int(port)), Handler)
    print(f"toolshim listening on {args.listen}, backend {BACKEND}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
