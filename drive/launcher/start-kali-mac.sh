#!/bin/bash
# Starts a guest system VM from this drive on macOS.
# Each vm/<name>-<arch> folder is an OS option; Apple Silicon uses *-arm64, Intel uses *-amd64.
# Usage: start-kali-mac.sh [gui|ssh] [os-name]
set -euo pipefail

MODE="${1:-gui}"
OS_PICK="${2:-}"
SSH_PORT="${KALI_SSH_PORT:-2222}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"

case "$MODE" in gui|ssh) ;; *) echo "Usage: $0 [gui|ssh] [os-name]"; exit 2 ;; esac

if [ "${KALI_SKIP_PREFLIGHT:-0}" != "1" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/preflight-mac.sh"
    run_preflight kali || exit 1
fi

find_tool() {
    local name="$1" dir
    if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return 0; fi
    for dir in /opt/homebrew/bin /usr/local/bin; do
        if [ -x "$dir/$name" ]; then echo "$dir/$name"; return 0; fi
    done
    return 1
}

if [ "$ARCH" = "arm64" ]; then QEMU_NAME=qemu-system-aarch64; SUFFIX="arm64"; else QEMU_NAME=qemu-system-x86_64; SUFFIX="amd64"; fi
if ! QEMU="$(find_tool "$QEMU_NAME")" || ! QEMU_IMG="$(find_tool qemu-img)"; then
    echo "QEMU is not installed. Install it once with: brew install qemu"; exit 1
fi

# Discover systems for this architecture: vm/<name>*SUFFIX folders holding a disk or installer.
FILTERED=()
while IFS= read -r d; do
    if ls "$d"/*.qcow2 >/dev/null 2>&1 || ls "$d"/*.iso >/dev/null 2>&1; then FILTERED+=("$d"); fi
done < <(find "$ROOT/vm" -maxdepth 1 -type d -name "*$SUFFIX" | sort)
[ "${#FILTERED[@]}" -gt 0 ] || { echo "No bootable $SUFFIX system under vm/."; exit 1; }

if [ -n "$OS_PICK" ]; then
    VM_DIR=""
    for d in "${FILTERED[@]}"; do [ "$(basename "$d")" = "$OS_PICK" ] && VM_DIR="$d"; done
    [ -n "$VM_DIR" ] || { echo "System not found: $OS_PICK"; exit 1; }
elif [ "${#FILTERED[@]}" -eq 1 ]; then
    VM_DIR="${FILTERED[0]}"
else
    echo "Choose a system to boot:"
    for i in "${!FILTERED[@]}"; do echo "  [$((i + 1))] $(basename "${FILTERED[$i]}")"; done
    read -r -p "Number: " n
    case "$n" in ''|*[!0-9]*) echo "Invalid choice."; exit 1 ;; esac
    { [ "$n" -ge 1 ] && [ "$n" -le "${#FILTERED[@]}" ]; } || { echo "Invalid choice."; exit 1; }
    VM_DIR="${FILTERED[$((n - 1))]}"
fi
NAME="$(basename "$VM_DIR")"

if lsof -nP -iTCP:"$SSH_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $SSH_PORT is already in use. Is a VM already running?"; exit 1
fi

TOTAL_MB=$(( $(sysctl -n hw.memsize) / 1048576 ))
LOGICAL=$(sysctl -n hw.ncpu)
MEMORY=$(( TOTAL_MB * 40 / 100 ))
[ "$MEMORY" -gt 6144 ] && MEMORY=6144
[ "$MEMORY" -lt 2048 ] && MEMORY=2048
CPUS=$(( LOGICAL / 2 ))
[ "$CPUS" -gt 6 ] && CPUS=6
[ "$CPUS" -lt 2 ] && CPUS=2

COMMON=(
    -name "Watchdog - $NAME"
    -accel hvf
    -cpu host
    -smp "$CPUS"
    -m "$MEMORY"
    -netdev "user,id=net0,tftp=$ROOT/launcher/guest,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
    -device virtio-net-pci,netdev=net0
    -device qemu-xhci
    -device usb-kbd
    -device usb-tablet
    -device virtio-rng-pci
)
if [ "$MODE" = "gui" ]; then DISPLAY_ARGS=(-display cocoa); else DISPLAY_ARGS=(-display none); fi
echo "System: $NAME ($MODE mode, $CPUS CPUs, $MEMORY MB RAM)"
echo "Shut down the VM before ejecting the drive."

if [ "$ARCH" = "arm64" ]; then
    SHARE="$(cd "$(dirname "$QEMU")/../share/qemu" && pwd)"
    CODE="$SHARE/edk2-aarch64-code.fd"
    VARS="$VM_DIR/efivars.fd"
    [ -f "$CODE" ] || { echo "UEFI firmware not found: $CODE"; exit 1; }
    DISK="$(find "$VM_DIR" -name '*.qcow2' -print -quit)"
    INSTALL_ARGS=()
    if [ -z "$DISK" ]; then
        ISO="$(find "$VM_DIR" -name '*.iso' -print -quit)"
        [ -n "$ISO" ] || { echo "No disk or installer in $VM_DIR"; exit 1; }
        [ "$MODE" = "gui" ] || { echo "First run must use gui mode to install."; exit 1; }
        echo "First run: creating the disk and starting the installer."
        DISK="$VM_DIR/disk.qcow2"
        "$QEMU_IMG" create -f qcow2 "$DISK" 100G
        INSTALL_ARGS=(-device virtio-scsi-pci -drive "file=$ISO,if=none,id=cd0,media=cdrom,readonly=on" -device scsi-cd,drive=cd0,bootindex=1)
    fi
    [ -f "$VARS" ] || cp "$SHARE/edk2-arm-vars.fd" "$VARS"
    MACHINE_ARGS=(
        -machine virt,highmem=on
        -drive "if=pflash,format=raw,readonly=on,file=$CODE"
        -drive "if=pflash,format=raw,file=$VARS"
        -drive "file=$DISK,if=none,id=hd0,format=qcow2,cache=writeback,discard=unmap"
        -device virtio-blk-pci,drive=hd0,bootindex=2
        -device virtio-gpu-pci
    )
    exec "$QEMU" "${COMMON[@]}" "${MACHINE_ARGS[@]}" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"} "${DISPLAY_ARGS[@]}"
fi

DISK="$(find "$VM_DIR" -name '*.qcow2' -print -quit)"
[ -n "$DISK" ] || { echo "No .qcow2 in $VM_DIR"; exit 1; }
exec "$QEMU" "${COMMON[@]}" -machine q35 \
    -drive "file=$DISK,if=virtio,format=qcow2,cache=writeback,discard=unmap" \
    -device virtio-vga "${DISPLAY_ARGS[@]}"
