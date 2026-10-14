#!/bin/bash

# run.sh
# Run by Xcode when the user presses Run (Cmd+R), through the monitor
# binary (see monitor_wrapper.c): flashes the firmware to the connected
# board, then shows the board's serial output in Xcode's console.
#
# Cmd+R first builds the project; build.sh records which project it built
# and where ESP-IDF put the build output (~/.espswift/last-build), and that
# is what this script flashes. Building (Cmd+B) doesn't flash the board.
#
# Usage: bash run.sh

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
LAST_BUILD="$HOME/.espswift/last-build"

# ── Flash ────────────────────────────────────────────────────────

if [ ! -f "$LAST_BUILD" ]; then
    echo "Error: Nothing to flash yet. Build the project first (Cmd+B), then run it (Cmd+R)." >&2
    exit 1
fi

# The source folder (with CMakeLists.txt) and ESP-IDF's build folder.
{ read -r SOURCE_DIR; read -r BUILD_DIR; } < "$LAST_BUILD"

echo "================================================="
echo " Flashing $(basename "$SOURCE_DIR")"
echo "================================================="

if ! bash "$SCRIPTS_DIR/flash.sh" "$SOURCE_DIR" "$BUILD_DIR"; then
    echo "Error: Flashing failed; see the messages above." >&2
    exit 1
fi

# ── Monitor ──────────────────────────────────────────────────────

echo ""
exec bash "$SCRIPTS_DIR/monitor.sh"
