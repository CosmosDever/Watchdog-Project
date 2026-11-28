#!/bin/bash
# build-hodo-opencode.sh — build a Hodophylax-branded OpenCode binary and (optionally) drop it
# onto the drive so setup-ai.sh ships it to every Kali.
#
# Run this INSIDE Kali (native Linux — x86_64 or aarch64). Needs internet for the one-time
# clone + `bun install`. This is the heavy, experimental part of the rebrand: the first build
# may surface dependency errors to fix. Re-run after each OpenCode upstream release to re-brand.
#
# Usage:  bash build-hodo-opencode.sh
# It installs the branded binary into ~/.local/bin/opencode for this Kali, and leaves a
# tarball in your home dir that you can copy to the drive from the host (steps printed at end).
set -euo pipefail

WORK="$HOME/hodo-opencode"

# 1) bun toolchain
if ! command -v bun >/dev/null 2>&1; then
    echo "[*] Installing bun..."
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
fi

# 2) fresh clone of upstream OpenCode
echo "[*] Cloning OpenCode..."
rm -rf "$WORK"
git clone --depth 1 https://github.com/sst/opencode "$WORK"
cd "$WORK"

# 3) rebrand the home-screen splash logo (packages/tui/src/logo.ts)
echo "[*] Applying Hodophylax logo..."
cat > packages/tui/src/logo.ts <<'LOGO'
export const logo = {
  left: [
    "                                        ",
    "█ █ █▀█ █▀▄ █▀█ █▀█ █ █ █ █ █   █▀█ █ █",
    "█▀█ █ █ █ █ █ █ █▀▀ █▀█ ▀█▀ █   █▀█ ▀█▀",
    "█ █ █▄█ █▄▀ █▄█ █   █ █  █  █▄▄ █ █ █ █",
  ],
  right: ["", "", "", ""],
}

export const go = {
  left: ["    ", "█▀▀▀", "█_^█", "▀▀▀▀"],
  right: ["    ", "█▀▀█", "█__█", "▀▀▀▀"],
}
LOGO

# 3b) rename user-facing "OpenCode" title strings where safe (best-effort).
grep -rIl 'Update OpenCode' packages/tui/src 2>/dev/null | xargs -r sed -i 's/Update OpenCode/Update Hodophylax/g' || true

# 4) install deps + build the native binary
echo "[*] Installing dependencies (this is the slow part)..."
bun install
echo "[*] Building..."
cd packages/cli
bun run build

# 5) find the produced binary that matches THIS machine (the build emits every platform,
#    so picking the first one can give a Mac/arm64 binary -> "Exec format error").
case "$(uname -m)" in x86_64) T=x64 ;; aarch64) T=arm64 ;; *) T="$(uname -m)" ;; esac
BIN="$(find dist -type f -name opencode -path "*linux-$T*" | head -1 || true)"
if [ -z "$BIN" ]; then
    # fall back to any binary that `file` reports as a native ELF
    while IFS= read -r f; do
        if file "$f" | grep -q 'ELF 64-bit'; then BIN="$f"; break; fi
    done < <(find dist -type f -name opencode)
fi
if [ -z "$BIN" ]; then
    echo "[!] No native linux opencode binary found under dist/. These were built:"
    find dist -type f -name opencode -exec sh -c 'echo "  $1 -> $(file -b "$1")"' _ {} \;
    exit 1
fi
echo "[*] Using binary: $BIN ($(file -b "$BIN" | cut -d, -f1,2))"

# 6) install it for THIS Kali right now — hodo/opencode will use the branded binary immediately
install -m 755 "$BIN" "$HOME/.local/bin/opencode"
echo "[*] Installed the branded binary to ~/.local/bin/opencode."
echo "    Start 'hodo' again to see the HODOPHYLAX splash."

# 7) also pack a tarball so you can ship it on the drive for every machine
OUT="$HOME/opencode-linux-$T.tar.gz"
tar -C "$(dirname "$BIN")" -czf "$OUT" opencode
echo
echo "[*] Tarball for the drive: $OUT ($(du -h "$OUT" | cut -f1))"
echo "    The drive is NOT mounted inside Kali, so copy it out from the WINDOWS host:"
echo "      1) in Kali:    sudo systemctl enable --now ssh"
echo "      2) on Windows: scp -P 2222 kali@127.0.0.1:$OUT \"K:\\launcher\\guest\\opencode-linux-$T.tar.gz\""
echo "    After that, setup-ai.sh on any machine installs the branded binary automatically."
echo "[*] Done."
