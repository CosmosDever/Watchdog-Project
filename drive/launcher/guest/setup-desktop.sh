#!/bin/bash
# Run inside Kali once. Enables two-way clipboard and automatic screen resizing.
set -euo pipefail

if ! dpkg-query -W -f='${Status}' spice-vdagent 2>/dev/null | grep -q 'install ok installed'; then
    echo "Installing spice-vdagent (needs internet and your Kali password)..."
    sudo apt-get update
    sudo apt-get install -y spice-vdagent
fi

sudo systemctl enable spice-vdagentd.service 2>/dev/null || true
sudo systemctl restart spice-vdagentd.service
if systemctl is-active --quiet spice-vdagentd.service; then
    echo "Clipboard service: OK"
else
    echo "Clipboard service: failed to start"
    exit 1
fi
echo "Done. Restart Kali once with: sudo reboot"
