#!/bin/bash
# build-hodo-opencode.sh — build a Hodophylax-branded OpenCode binary and (optionally) drop it
# onto the drive so setup-ai.sh ships it to every Kali.
#
# Run this INSIDE Kali (native Linux — x86_64 or aarch64). Needs internet for the one-time
# clone + `bun install`. This is the heavy, experimental part of the rebrand: the first build
# may surface dependency errors to fix. Re-run after each OpenCode upstream release to re-brand.
#
# Usage:
#   bash build-hodo-opencode.sh [/path/to/drive/launcher/guest]
#   e.g. bash build-hodo-opencode.sh /media/kali/HODOPHYLAX/launcher/guest
set -euo pipefail

DEST="${1:-}"
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

# 5) find the produced binary and pack the tarball setup-ai.sh expects
BIN="$(find dist -type f -name opencode | head -1 || true)"
[ -n "$BIN" ] || { echo "[!] Build produced no 'opencode' binary under dist/. Inspect the build output above."; exit 1; }
case "$(uname -m)" in x86_64) T=x64 ;; aarch64) T=arm64 ;; *) T="$(uname -m)" ;; esac
OUT="$HOME/opencode-linux-$T.tar.gz"
tar -C "$(dirname "$BIN")" -czf "$OUT" opencode
echo "[*] Built: $OUT ($(du -h "$OUT" | cut -f1))"

# 6) place on the drive if a guest dir was given
if [ -n "$DEST" ] && [ -d "$DEST" ]; then
    cp "$OUT" "$DEST/opencode-linux-$T.tar.gz"
    echo "[*] Installed to $DEST/opencode-linux-$T.tar.gz"
    echo "    Re-run setup-ai.sh in each Kali to pick up the branded binary."
else
    echo "[*] No drive guest dir given. Copy $OUT to <drive>/launcher/guest/ yourself."
fi
echo "[*] Done."
