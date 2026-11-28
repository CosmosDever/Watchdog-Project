#!/bin/bash
# Run once inside the guest. Installs the Hodophylax agent (built on OpenCode), its config,
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

echo "Installing the Hodophylax agent engine..."
curl -fsS --connect-timeout 10 -o "$WORK/$FILE" "tftp://$HOST_IP/$FILE"
echo "$SHA  $WORK/$FILE" | sha256sum -c --quiet
tar -xzf "$WORK/$FILE" -C "$WORK"
install -m 755 "$WORK/opencode" "$HOME/.local/bin/opencode"

# "execute": "deny" turns OFF OpenCode's Code Mode (where the model writes JS that imports
# node:fs etc.) so every tool is a plain direct call. Local models that emit classic tool calls
# (Qwen) work; without this they loop on "Cannot import 'fs': this runtime doesn't provide it".
cat > "$HOME/.config/opencode/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "local/local",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Hodophylax Local",
      "options": { "baseURL": "http://$HOST_IP:8080/v1", "apiKey": "local" },
      "models": { "local": { "name": "Local model" } }
    }
  },
  "permission": { "execute": "deny", "bash": "allow", "edit": "allow", "webfetch": "allow" }
}
EOF

# Pull the branded commands and the rules file from the drive.
for item in hodo target new-engagement web-recon juice-score; do
    curl -fsS --connect-timeout 10 -o "$HOME/.local/bin/$item" "tftp://$HOST_IP/$item"
    chmod 755 "$HOME/.local/bin/$item"
done
curl -fsS --connect-timeout 10 -o "$HOME/.config/opencode/AGENTS.md" "tftp://$HOST_IP/AGENTS.md"

# PATH, once.
grep -q '.local/bin' "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"

# Self-update hook: on each login, refresh the small commands and rules from the drive.
# Silent, ~instant, and a no-op when the host launcher is not running.
if ! grep -q 'hodo-sync' "$HOME/.zshrc" 2>/dev/null; then
cat >> "$HOME/.zshrc" <<'HOOK'
# hodo-sync: keep the Hodophylax agent current from the drive
if [ -z "${HODOPHYLAX_SYNCED:-}" ]; then
  export HODOPHYLAX_SYNCED=1
  for _h in hodo target new-engagement web-recon juice-score; do
    curl -fsS --connect-timeout 2 -o "$HOME/.local/bin/$_h" "tftp://10.0.2.2/$_h" 2>/dev/null && chmod +x "$HOME/.local/bin/$_h" 2>/dev/null
  done
  curl -fsS --connect-timeout 2 -o "$HOME/.config/opencode/AGENTS.md" "tftp://10.0.2.2/AGENTS.md" 2>/dev/null
fi
HOOK
fi

export PATH="$HOME/.local/bin:$PATH"
echo
echo "Done. Hodophylax is installed and will keep itself up to date."
echo "Start a job in one command:  target <ip-or-url> <name>"
echo "   e.g.  target 10.10.10.5 acme-box      (scaffolds the folder and opens the agent)"
echo "Or step by step:  new-engagement myjob  then  cd ~/engagement/myjob && hodo"
