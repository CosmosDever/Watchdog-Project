#!/bin/bash
# Checks that this Mac can run the portable Kali / AI setup, and offers to install
# what is missing. Source this file and call: run_preflight kali   or   run_preflight llm
# Returns 0 if it is safe to continue, non-zero on a hard blocker.

run_preflight() {
    local what="$1"
    local root arch ok=0
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    arch="$(uname -m)"
    echo "Checking this Mac..."

    good() { echo "  [ok]   $1"; }
    warn() { echo "  [warn] $1"; }
    bad()  { echo "  [stop] $1"; ok=1; }

    find_tool() {
        local n="$1" d
        command -v "$n" >/dev/null 2>&1 && { command -v "$n"; return 0; }
        for d in /opt/homebrew/bin /usr/local/bin; do [ -x "$d/$n" ] && { echo "$d/$n"; return 0; }; done
        return 1
    }

    case "$arch" in
        arm64)  good "Apple Silicon Mac" ;;
        x86_64) good "Intel Mac" ;;
        *) bad "Unsupported CPU ($arch)" ;;
    esac

    local ramgb
    ramgb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    if [ "$ramgb" -ge 8 ]; then good "RAM ${ramgb} GB"
    elif [ "$ramgb" -ge 5 ]; then warn "RAM ${ramgb} GB: run Kali and the AI one at a time"
    else bad "RAM ${ramgb} GB is too low"; fi

    if [ "$what" = "kali" ]; then
        local qbin="qemu-system-x86_64"
        [ "$arch" = "arm64" ] && qbin="qemu-system-aarch64"
        if find_tool "$qbin" >/dev/null && find_tool qemu-img >/dev/null; then
            good "QEMU is installed ($("$(find_tool "$qbin")" --version | head -1))"
        else
            warn "QEMU is not installed on this Mac - it is required to run Kali."
            if find_tool brew >/dev/null; then
                local brew; brew="$(find_tool brew)"
                printf "       Install QEMU now with Homebrew? [y/N] "
                read -r ans
                if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                    "$brew" install qemu || bad "QEMU install failed. Run: brew install qemu"
                    find_tool "$qbin" >/dev/null && good "QEMU installed" || bad "QEMU still not found."
                else
                    bad "QEMU is required. Install it with: brew install qemu"
                fi
            else
                warn "Homebrew is not installed. Install it, then QEMU:"
                echo '       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                echo '       brew install qemu'
                bad "Install Homebrew and QEMU, then start Kali again."
            fi
        fi
    fi

    if [ "$what" = "llm" ]; then
        local plat="macos-x64"; [ "$arch" = "arm64" ] && plat="macos-arm64"
        if ls "$root/llm/runtime/macos/"llama-*-bin-"$plat".tar.gz >/dev/null 2>&1; then
            good "llama.cpp runtime for $plat is on the SSD"
        else
            bad "Missing llama.cpp runtime for $plat on the SSD."
        fi
        if command -v python3 >/dev/null 2>&1; then good "python3 is available"; else warn "python3 not found; WhiteRabbitNeo needs it. Qwen still works."; fi
        local n
        n=$(ls "$root/llm/models/"*.gguf 2>/dev/null | wc -l | tr -d ' ')
        if [ "$n" -gt 0 ]; then good "$n model(s) present"; else bad "No .gguf model in llm/models."; fi
    fi

    if [ "$ok" -eq 0 ]; then echo "Ready to start."; else echo "Cannot start: fix the [stop] items above."; fi
    return "$ok"
}
