"""Translation proxy: turns a model's plain-JSON tool output into real OpenAI tool_calls.

Some local models (e.g. WhiteRabbitNeo) print a tool call as a bare JSON object
in the message content instead of the structured tool_calls field that agents need.
This proxy sits between the agent (OpenCode) and llama-server. It buffers the full
reply from the backend (so tool-call extraction is reliable), but keeps the client's
streaming connection alive the whole time: it sends the SSE headers and an initial
role delta immediately, then emits a keepalive comment every few seconds while the
backend is still generating. That stops agents from timing out and hanging during a
long generation. Each request is logged to the console so you can see what is going on.

Usage: python -I toolshim.py --listen 127.0.0.1:8080 --backend 127.0.0.1:8081
"""
import argparse
import json
import re
import sys
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND = "http://127.0.0.1:8081"
FENCE = re.compile(r"^\s*```(?:json)?\s*|\s*```\s*$", re.IGNORECASE)
TOOLTAG = re.compile(r"</?tool_call>", re.IGNORECASE)
OBJECT = re.compile(r"\{.*\}", re.DOTALL)
BACKEND_TIMEOUT = 900
KEEPALIVE_SECONDS = 5


def log(msg):
    print("[toolshim] " + msg, flush=True)


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
            if name in names:
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
    with urllib.request.urlopen(req, timeout=BACKEND_TIMEOUT) as resp:
        return resp.status, resp.read(), resp.headers.get("Content-Type", "application/json")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    # --- low-level writes, guarded against a client that hung up -------------
    def _write_raw(self, data):
        try:
            self.wfile.write(data)
            self.wfile.flush()
            return True
        except (BrokenPipeError, ConnectionResetError, OSError):
            return False

    def _write_sse(self, obj):
        return self._write_raw(("data: " + json.dumps(obj) + "\n\n").encode())

    def _send(self, status, body, ctype="application/json"):
        try:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

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

        # Anything that is not a chat completion is forwarded verbatim.
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
        model = payload.get("model", "local")
        log(f"POST /v1/chat/completions stream={want_stream} tools={len(names)}")

        if want_stream:
            self._handle_stream(payload, names, model)
        else:
            self._handle_blocking(payload, names)

    # --- blocking (non-streaming) path --------------------------------------
    def _run_backend(self, payload, names):
        backend_payload = dict(payload)
        backend_payload["stream"] = False
        data = json.dumps(backend_payload).encode()
        started = time.time()
        status, body, _ = backend_call("/v1/chat/completions", data, {"Content-Type": "application/json"})
        took = time.time() - started
        if status != 200:
            log(f"backend {status} in {took:.1f}s")
            return status, None, took
        result = json.loads(body)
        choice = (result.get("choices") or [{}])[0]
        message = choice.get("message", {})
        if names and not message.get("tool_calls"):
            calls = extract_calls(message.get("content"), names)
            if calls:
                message["tool_calls"] = calls
                message["content"] = None
                choice["finish_reason"] = "tool_calls"
                log(f"backend 200 in {took:.1f}s, extracted {len(calls)} tool_call(s)")
            else:
                clen = len(message.get("content") or "")
                log(f"backend 200 in {took:.1f}s, content {clen} chars")
        else:
            ncalls = len(message.get("tool_calls") or [])
            log(f"backend 200 in {took:.1f}s, native tool_calls={ncalls}")
        return 200, result, took

    def _handle_blocking(self, payload, names):
        try:
            status, result, _ = self._run_backend(payload, names)
        except Exception as exc:  # noqa: BLE001
            log(f"backend error: {exc}")
            self._send(502, json.dumps({"error": str(exc)}).encode())
            return
        if result is None:
            self._send(status, json.dumps({"error": f"backend returned {status}"}).encode())
            return
        self._send(200, json.dumps(result).encode())

    # --- streaming path: keep the client warm while the backend works -------
    def _handle_stream(self, payload, names, model):
        base = {"id": "chatcmpl-" + uuid.uuid4().hex[:24],
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": model}

        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
        except (BrokenPipeError, ConnectionResetError, OSError):
            return

        # First byte now, so the client's "time to first token" timer resets.
        if not self._write_sse({**base, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]}):
            log("client closed before first token")
            return

        holder = {}

        def worker():
            try:
                holder["result"] = self._run_backend(payload, names)
            except Exception as exc:  # noqa: BLE001
                holder["error"] = exc

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()

        # Heartbeat while the backend is still generating.
        while thread.is_alive():
            thread.join(timeout=KEEPALIVE_SECONDS)
            if thread.is_alive():
                if not self._write_raw(b": keepalive\n\n"):
                    log("client hung up mid-generation (keepalive failed)")
                    return

        if "error" in holder:
            log(f"backend error: {holder['error']}")
            self._emit_text(base, f"[toolshim] backend error: {holder['error']}", "stop")
            return

        status, result, _ = holder["result"]
        if result is None:
            self._emit_text(base, f"[toolshim] backend returned {status}", "stop")
            return

        choice = (result.get("choices") or [{}])[0]
        message = choice.get("message", {})

        if message.get("tool_calls"):
            for idx, call in enumerate(message["tool_calls"]):
                delta = {"tool_calls": [{"index": idx, "id": call["id"], "type": "function",
                                         "function": {"name": call["function"]["name"],
                                                      "arguments": call["function"]["arguments"]}}]}
                if not self._write_sse({**base, "choices": [{"index": 0, "delta": delta, "finish_reason": None}]}):
                    return
            self._write_sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]})
            self._write_raw(b"data: [DONE]\n\n")
        else:
            self._emit_text(base, message.get("content") or "", choice.get("finish_reason", "stop"))

    def _emit_text(self, base, content, finish_reason):
        if not self._write_sse({**base, "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": None}]}):
            return
        self._write_sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": finish_reason}]})
        self._write_raw(b"data: [DONE]\n\n")


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
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
