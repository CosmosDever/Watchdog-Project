#!/bin/bash
# Safely eject the Watchdog drive this file lives on. Double-click to run (or: bash "Eject Drive.command").

# bash keeps its script open, so a script on the drive would block its own eject.
# Restart from a temporary copy on the Mac before touching the drive.
if [ -z "${WATCHDOG_EJECT_DIR:-}" ]; then
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SELF_COPY="$(mktemp "${TMPDIR:-/tmp}/watchdog-eject.XXXXXX")" || exit 1
    cp "${BASH_SOURCE[0]}" "$SELF_COPY" || exit 1
    cd "$HOME" || exit 1
    WATCHDOG_EJECT_DIR="$DIR" WATCHDOG_EJECT_COPY="$SELF_COPY" exec /bin/bash "$SELF_COPY"
fi

DIR="$WATCHDOG_EJECT_DIR"
trap 'rm -f "$WATCHDOG_EJECT_COPY"' EXIT
cd "$HOME" || exit 1
echo
echo "Ejecting $DIR ..."
echo "This also ejects any other volume on the same physical drive."
echo
sync
if OUTPUT="$(diskutil eject "$DIR" 2>&1)"; then
    echo "Done. The drive is safe to unplug."
else
    echo "Could NOT eject. Do not unplug the drive yet."
    echo "$OUTPUT"
    echo
    echo "Close the app named above, plus the Kali VM and AI (start-llm) windows, then run this again."
fi
echo
read -n 1 -s -r -p "Press any key to close."
echo
