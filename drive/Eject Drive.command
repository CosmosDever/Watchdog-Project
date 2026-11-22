#!/bin/bash
# Safely eject the Watchdog drive this file lives on. Double-click to run (or: bash "Eject Drive.command").
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HOME"
echo
echo "Ejecting $DIR ..."
echo "(If this fails, close the Kali VM window and the AI start-llm window first.)"
echo
sync
if diskutil eject "$DIR" 2>/dev/null; then
    echo "Done. The drive is safe to unplug."
else
    echo "Could NOT eject - something is still using the drive."
    echo "Close the Kali VM window and the AI (start-llm) window, then run this again."
fi
echo
read -n 1 -s -r -p "Press any key to close."
echo
