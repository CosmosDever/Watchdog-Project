#!/bin/bash
# Run once inside the guest. Installs the Watchdog agent (built on OpenCode), its config,
# and a login hook that keeps the agent and rules current from the drive automatically.
# After this runs once, you never run it again — the hook self-updates on every login.
set -euo pipefail

HOST_IP="10.0.2.2"
case "$(uname -m)" in
    x86_64)  FILE="opencode-linux-x64.tar.gz"
             SHA="47734e08968b30cc22a0bffb6d9feeed76ad4aa743213a12122040392d09a057" ;;
    aarch64) FILE="opencode-linux-arm64.tar.gz"
             SHA="5b68c1f4c5e75b4134e664cc8f36d634d64208d4fcfe5bcf3b48bab699c2dbac" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$HOME/.local/bin" "$HOME/.config/opencode" "$HOME/engagement"

echo "Installing the Watchdog agent engine..."
curl -fsS --connect-timeout 10 -o "$WORK/$FILE" "tftp://$HOST_IP/$FILE"
echo "$SHA  $WORK/$FILE" | sha256sum -c --quiet
tar -xzf "$WORK/$FILE" -C "$WORK"
install -m 755 "$WORK/opencode" "$HOME/.local/bin/opencode"

cat > "$HOME/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "local/local",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Watchdog Local",
      "options": { "baseURL": "http://$HOST_IP:8080/v1", "apiKey": "local" },
      "models": { "local": { "name": "Local model" } }
    }
  },
  "permission": { "bash": "allow", "edit": "allow", "webfetch": "allow" }
}
EOF

# Pull the branded commands and the rules file from the drive.
for item in watchdog-ai new-engagement web-recon juice-score; do
    curl -fsS --connect-timeout 10 -o "$HOME/.local/bin/$item" "tftp://$HOST_IP/$item"
    chmod 755 "$HOME/.local/bin/$item"
done
curl -fsS --connect-timeout 10 -o "$HOME/.config/opencode/AGENTS.md" "tftp://$HOST_IP/AGENTS.md"

# PATH, once.
grep -q '.local/bin' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"

# Self-update hook: on each login, refresh the small commands and rules from the drive.
# Silent, ~instant, and a no-op when the host launcher is not running.
if ! grep -q 'watchdog-sync' "$HOME/.zshrc" 2>/dev/null; then
cat >> "$HOME/.zshrc" <<'HOOK'
# watchdog-sync: keep the Watchdog agent current from the drive
if [ -z "${WATCHDOG_SYNCED:-}" ]; then
  export WATCHDOG_SYNCED=1
  for _h in watchdog-ai new-engagement web-recon juice-score; do
    curl -fsS --connect-timeout 2 -o "$HOME/.local/bin/$_h" "tftp://10.0.2.2/$_h" 2>/dev/null && chmod +x "$HOME/.local/bin/$_h" 2>/dev/null
  done
  curl -fsS --connect-timeout 2 -o "$HOME/.config/opencode/AGENTS.md" "tftp://10.0.2.2/AGENTS.md" 2>/dev/null
fi
HOOK
fi

export PATH="$HOME/.local/bin:$PATH"
echo
echo "Done. Watchdog is installed and will keep itself up to date."
echo "Start a job:  new-engagement myjob"
echo "Then:         cd ~/engagement/myjob && watchdog-ai"
