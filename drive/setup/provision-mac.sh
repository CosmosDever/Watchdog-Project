#!/bin/bash
# Watchdog in-place provisioner (macOS / Linux). Lives on the drive at setup/.
# Downloads and hash-verifies the macOS llama.cpp runtimes, the agent engine, the OS image,
# and the models INTO this drive, reading config/watchdog.json. QEMU comes from Homebrew
# (brew install qemu) — the launcher offers it. Usage: bash setup/provision-mac.sh [-y]
set -euo pipefail

YES="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/config/watchdog.json"
[ -f "$CONFIG" ] || CONFIG="$ROOT/config/watchdog.example.json"
[ -f "$CONFIG" ] || { echo "No manifest in $ROOT/config/."; exit 1; }

LLAMA_BUILD="b12625"
OPENCODE_VER="v1.19.6"
OPENCODE_X64_SHA="47734e08968b30cc22a0bffb6d9feeed76ad4aa743213a12122040392d09a057"
OPENCODE_ARM64_SHA="5b68c1f4c5e75b4134e664cc8f36d634d64208d4fcfe5bcf3b48bab699c2dbac"
LLAMA_MAC_ARM64_SHA="99103c75e32c6ecdf51543e76e63c816ecbc870cd76ba369c80751c5efba98db"
LLAMA_MAC_X64_SHA="5ef445049fdadde64db17d3eadc522a9e417b9665b4aa3de7a83de666498ecd9"

jq_get() { python3 -c "import json,sys;d=json.load(open('$CONFIG'));print(eval(sys.argv[1]))" "$1"; }

if [ "$YES" != "-y" ]; then
    printf 'This downloads about 6 GB (llama.cpp, Kali, models) onto %s. Continue? [Y/n] ' "$ROOT"
    read -r a; case "$a" in [nN]*) echo "Cancelled."; exit 0 ;; esac
fi

verify() { # url path sha
    if [ -f "$2" ] && [ -n "$3" ] && [ "$(shasum -a 256 "$2" | awk '{print $1}')" = "$3" ]; then echo "  cached $(basename "$2")"; return; fi
    echo "  downloading $(basename "$2")..."
    curl -fL --retry 5 --retry-delay 5 -C - -o "$2" "$1"
    if [ -n "$3" ]; then got="$(shasum -a 256 "$2" | awk '{print $1}')"; [ "$got" = "$3" ] || { rm -f "$2"; echo "HASH MISMATCH $(basename "$2")"; exit 1; }; fi
}

DL="$ROOT/_downloads"
OS_NAME="$(jq_get "d['os']['name']")"; OS_ARCH="$(jq_get "d['os']['arch']")"
OS_TYPE="$(jq_get "d['os']['type']")"; OS_URL="$(jq_get "d['os']['url']")"; OS_SHA="$(jq_get "d['os']['sha256']")"
OSDIR="$ROOT/vm/$OS_NAME-$OS_ARCH"
mkdir -p "$ROOT/llm/models" "$ROOT/llm/runtime/macos" "$ROOT/launcher/guest" "$OSDIR" "$ROOT/shared" "$DL"

echo "llama.cpp (macOS runtimes)..."
verify "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD/llama-$LLAMA_BUILD-bin-macos-arm64.tar.gz" "$ROOT/llm/runtime/macos/llama-$LLAMA_BUILD-bin-macos-arm64.tar.gz" "$LLAMA_MAC_ARM64_SHA"
verify "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD/llama-$LLAMA_BUILD-bin-macos-x64.tar.gz" "$ROOT/llm/runtime/macos/llama-$LLAMA_BUILD-bin-macos-x64.tar.gz" "$LLAMA_MAC_X64_SHA"

echo "Agent engine (OpenCode) for the guest..."
verify "https://github.com/anomalyco/opencode/releases/download/$OPENCODE_VER/opencode-linux-x64.tar.gz" "$ROOT/launcher/guest/opencode-linux-x64.tar.gz" "$OPENCODE_X64_SHA"
verify "https://github.com/anomalyco/opencode/releases/download/$OPENCODE_VER/opencode-linux-arm64.tar.gz" "$ROOT/launcher/guest/opencode-linux-arm64.tar.gz" "$OPENCODE_ARM64_SHA"

echo "Guest OS image..."
IMG="$DL/os-image.${OS_URL##*.}"
verify "$OS_URL" "$IMG" "$OS_SHA"
if [ "$OS_TYPE" = "qemu-image" ]; then tar -xf "$IMG" -C "$OSDIR"; else cp "$IMG" "$OSDIR/"; fi

echo "Models..."
N="$(jq_get "len(d['models'])")"
for i in $(seq 0 $((N - 1))); do
    MN="$(jq_get "d['models'][$i]['name']")"; MU="$(jq_get "d['models'][$i]['url']")"; MS="$(jq_get "d['models'][$i]['sha256']")"
    verify "$MU" "$ROOT/llm/models/$MN" "$MS"
done

echo "Done. Run 'brew install qemu' once, then run watchdog-run from the drive."
