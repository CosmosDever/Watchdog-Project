#!/bin/bash
# Starts the local LLM on macOS. It listens on 127.0.0.1 only.
# WhiteRabbitNeo is served through a tool-call proxy so agents get proper tool_calls.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${LLM_PORT:-8080}"
CONTEXT="${LLM_CONTEXT:-16384}"
BUILD="b12625"
case "$(uname -m)" in
    arm64) PLATFORM="macos-arm64" ;;
    *)     PLATFORM="macos-x64" ;;
esac

if [ "${KALI_SKIP_PREFLIGHT:-0}" != "1" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/preflight-mac.sh"
    run_preflight llm || exit 1
fi

ARCHIVE="$ROOT/llm/runtime/macos/llama-$BUILD-bin-$PLATFORM.tar.gz"
CACHE="$HOME/Library/Caches/kali-portable-llm/$BUILD-$PLATFORM"
[ -f "$ARCHIVE" ] || { echo "Runtime not found: $ARCHIVE"; exit 1; }
SERVER="$(find "$CACHE" -name llama-server -type f -print -quit 2>/dev/null || true)"
if [ -z "$SERVER" ]; then
    mkdir -p "$CACHE"
    tar -xzf "$ARCHIVE" -C "$CACHE"
    SERVER="$(find "$CACHE" -name llama-server -type f -print -quit)"
fi
[ -n "$SERVER" ] || { echo "llama-server not found in $ARCHIVE"; exit 1; }
chmod +x "$SERVER"

MODELS=()
while IFS= read -r file; do MODELS+=("$file"); done < <(find "$ROOT/llm/models" -maxdepth 1 -name '*.gguf' ! -name '._*' | sort)
[ "${#MODELS[@]}" -gt 0 ] || { echo "No .gguf model found in llm/models."; exit 1; }
if [ "${#MODELS[@]}" -eq 1 ]; then
    MODEL="${MODELS[0]}"
else
    for i in "${!MODELS[@]}"; do echo "[$((i + 1))] $(basename "${MODELS[$i]}")"; done
    read -r -p "Choose a model: " CHOICE
    case "$CHOICE" in ''|*[!0-9]*) echo "Invalid choice."; exit 1 ;; esac
    if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#MODELS[@]}" ]; then echo "Invalid choice."; exit 1; fi
    MODEL="${MODELS[$((CHOICE - 1))]}"
fi

NAME="$(basename "$MODEL")"
CORES="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)"
COMMON=(-m "$MODEL" --alias local -c "$CONTEXT" --jinja -fa on -t "$CORES" -ngl 99)

USE_SHIM=0
case "$NAME" in *WhiteRabbitNeo*|*DeepHat*) USE_SHIM=1 ;; esac

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
port_busy "$PORT" && { echo "Port $PORT is already in use. Is the LLM already running?"; exit 1; }

echo "Model: $NAME"
echo "API: http://127.0.0.1:$PORT/v1 (from Kali: http://10.0.2.2:$PORT/v1)"
echo "Perf: Metal offload, flash-attn on, $CORES threads, context $CONTEXT"

if [ "$USE_SHIM" -eq 0 ]; then
    echo "Mode: direct"
    exec "$SERVER" "${COMMON[@]}" --host 127.0.0.1 --port "$PORT"
fi

PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "python3 is required for the tool-call proxy (install Xcode command line tools)."; exit 1; }
BACKEND_PORT=$((PORT + 1))
port_busy "$BACKEND_PORT" && { echo "Port $BACKEND_PORT is already in use."; exit 1; }
echo "Mode: tool-call proxy (backend on $BACKEND_PORT)"

"$SERVER" "${COMMON[@]}" --host 127.0.0.1 --port "$BACKEND_PORT" >/tmp/kali-portable-llm.log 2>&1 &
BE=$!
cleanup() { kill "$BE" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:$BACKEND_PORT/health" >/dev/null 2>&1; then break; fi
    kill -0 "$BE" 2>/dev/null || { echo "Backend failed to start:"; tail -n 10 /tmp/kali-portable-llm.log; exit 1; }
    sleep 0.5
done
echo "Ready. Press Ctrl+C to stop."
"$PY" "$ROOT/llm/proxy/toolshim.py" --listen "127.0.0.1:$PORT" --backend "127.0.0.1:$BACKEND_PORT"
