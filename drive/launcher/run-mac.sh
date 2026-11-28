#!/bin/bash
# One-command startup for macOS: checks the Mac, offers the local AI, then opens Kali.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-gui}"
source "$DIR/preflight-mac.sh"

echo '==================== Hodophylax ===================='

# If the drive has no VM / model yet, offer to download and install them.
HAS_VM="$(find "$DIR/../vm" -name '*.qcow2' -print -quit 2>/dev/null || true)"
HAS_MODEL="$(find "$DIR/../llm/models" -maxdepth 1 -name '*.gguf' -print -quit 2>/dev/null || true)"
if [ -z "$HAS_VM" ] || [ -z "$HAS_MODEL" ]; then
    echo 'This drive is not set up yet (no VM or model found).'
    if [ -f "$DIR/../setup/provision-mac.sh" ]; then
        printf 'Download and install Kali + the default model now? (~6 GB) [Y/n] '
        read -r a
        case "$a" in
            [nN]*) echo 'Set it up later with:  bash setup/provision-mac.sh'; exit 0 ;;
            *) bash "$DIR/../setup/provision-mac.sh" -y || { echo 'Setup failed.'; exit 1; } ;;
        esac
    else
        echo 'Run the provisioner to set it up:  bash setup/provision-mac.sh'; exit 1
    fi
fi

run_preflight kali || { echo 'Press Enter to close'; read -r _; exit 1; }

echo ''
echo 'AI backend for this session:'
echo '  [1] Local model  - runs on this Mac, private and offline'
echo '  [2] Cloud API    - Claude / OpenAI / OpenRouter, set your key inside Kali'
echo '  [3] None'
printf 'Choose [1/2/3] '
read -r choice
case "$choice" in
    2)
        echo 'Cloud API: after Kali opens, set your key and run the agent, e.g.'
        echo '  export ANTHROPIC_API_KEY=...   then   hodo   (use /models to pick)'
        echo 'The local model server will not be started.'
        ;;
    3)
        echo 'No AI backend started.'
        ;;
    *)
        if run_preflight llm; then
            if command -v osascript >/dev/null 2>&1; then
                osascript -e "tell application \"Terminal\" to do script \"KALI_SKIP_PREFLIGHT=1 bash '$DIR/start-llm-mac.sh'\"" >/dev/null 2>&1 \
                    && echo 'The local AI is starting in a new Terminal window. Pick a model there.'
            else
                KALI_SKIP_PREFLIGHT=1 bash "$DIR/start-llm-mac.sh" &
                echo 'The local AI is starting in the background.'
            fi
            sleep 2
        else
            echo 'Skipping the local AI: this Mac is not ready for it.'
        fi
        ;;
esac

echo 'Opening Kali...'
exec env KALI_SKIP_PREFLIGHT=1 bash "$DIR/start-kali-mac.sh" "$MODE"
