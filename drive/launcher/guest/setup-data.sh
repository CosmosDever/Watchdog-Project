#!/bin/bash
# Run once inside each Kali VM. Mounts the drive's shared data disk at /data and moves
# ~/engagement onto it. Safe to run again: it never formats a disk that has a filesystem.
set -euo pipefail

DEV=/dev/disk/by-id/virtio-watchdog-data
LABEL=WATCHDOG-DATA
LINK="$HOME/engagement"

if [ ! -e "$DEV" ]; then
    echo "Shared data disk not found. Shut down Kali and start it again with hodo-run."
    exit 1
fi

FSTYPE="$(sudo blkid -o value -s TYPE "$DEV" || true)"
if [ -z "$FSTYPE" ]; then
    # Refuse to format anything that holds partitions or unknown data.
    if [ -n "$(sudo wipefs -n "$DEV")" ] || [ "$(lsblk -nro NAME "$DEV" | wc -l)" -ne 1 ]; then
        echo "The shared disk has unrecognized data. Not formatting it."; exit 1
    fi
    echo "Formatting the new shared data disk..."
    sudo mkfs.ext4 -q -L "$LABEL" "$DEV"
elif [ "$FSTYPE" != "ext4" ] || [ "$(sudo blkid -o value -s LABEL "$DEV")" != "$LABEL" ]; then
    echo "Unexpected filesystem on the shared disk ($FSTYPE). Not touching it."; exit 1
fi

sudo mkdir -p /data
if ! grep -q "LABEL=$LABEL" /etc/fstab; then
    echo "LABEL=$LABEL /data ext4 defaults,nofail,x-systemd.device-timeout=5s 0 2" | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
fi
mountpoint -q /data || sudo mount /data

sudo mkdir -p /data/engagement
sudo chown "$(id -u):$(id -g)" /data /data/engagement

if [ -L "$LINK" ]; then
    [ "$(readlink -f "$LINK")" = "/data/engagement" ] || { echo "$LINK points somewhere else. Not changing it."; exit 1; }
elif [ -d "$LINK" ]; then
    # Copy without overwriting, then keep the original as a backup.
    cp -a -n "$LINK/." /data/engagement/
    if (cd "$LINK" && find . ! -type d -print0) | (cd /data/engagement && while IFS= read -r -d '' f; do [ -e "$f" ] || [ -L "$f" ] || exit 1; done); then
        BACKUP="$LINK.local-backup-$(date +%Y%m%d-%H%M%S)"
        mv "$LINK" "$BACKUP"
        ln -s /data/engagement "$LINK"
        echo "Old folder kept at: $BACKUP"
    else
        echo "Copy check failed. Your original $LINK was left in place."; exit 1
    fi
elif [ -e "$LINK" ]; then
    echo "$LINK exists and is not a folder. Not changing it."; exit 1
else
    ln -s /data/engagement "$LINK"
fi
sudo chown -R "$(id -u):$(id -g)" /data/engagement

echo
echo "Done. ~/engagement now lives on the shared disk at /data/engagement."
df -h /data | tail -1
