#!/bin/bash

# debug.sh
# Debugs the firmware running on the board with LLDB: breakpoints in Swift
# (and C) code, stepping, backtraces and variables.
#
# Uses the chip's built-in USB-JTAG, so the board must be connected through
# its native USB port (on the ESP32-C6-DevKitC-1 the port labelled "USB",
# not "UART"). The ESP32-C2 has no built-in USB-JTAG and needs an external
# JTAG adapter, which this script doesn't set up.
#
# Debugs the project that was built last (~/.espswift/last-build, written
# by build.sh), with the firmware that's on the board: build and run it
# first (Cmd+R in Xcode). Starts OpenOCD, which talks to the chip, and LLDB
# connected to it. Connecting resets the chip, so the script lets the
# firmware start up and pauses it before handing over the (lldb) prompt.
# Quitting LLDB stops OpenOCD and lets the firmware continue.
#
# Breakpoints are hardware breakpoints, as the code runs from flash. The
# chips have 4 of them, so up to 4 breakpoints can be set at once.
#
# Usage: bash debug.sh

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
LAST_BUILD="$HOME/.espswift/last-build"

# ── The Build to Debug ───────────────────────────────────────────

if [ ! -f "$LAST_BUILD" ]; then
    echo "Error: Nothing to debug yet. Build and run the project first (Cmd+R in Xcode)." >&2
    exit 1
fi
{ read -r SOURCE_DIR; read -r BUILD_DIR; } < "$LAST_BUILD"

ELF="$BUILD_DIR/$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["app_elf"])' \
    "$BUILD_DIR/project_description.json" 2>/dev/null)"
if [ ! -f "$ELF" ]; then
    echo "Error: The firmware of the last build wasn't found in $BUILD_DIR. Build the project again." >&2
    exit 1
fi

CHIP=$(sed -n 's/^CONFIG_IDF_TARGET="\(.*\)"$/\1/p' "$SOURCE_DIR/sdkconfig")

# ── Tools ────────────────────────────────────────────────────────

# ESP-IDF's environment provides OpenOCD and its configuration files.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.espswift/python/bin:$PATH"
export IDF_PATH="${IDF_PATH:-$HOME/.espswift/esp-idf}"
if ! source "$IDF_PATH/export.sh" > /dev/null 2>&1; then
    echo "Error: Couldn't set up ESP-IDF from $IDF_PATH. Please run install.sh." >&2
    exit 1
fi

OPENOCD_CONFIG="board/$CHIP-builtin.cfg"
if [ ! -f "$OPENOCD_SCRIPTS/$OPENOCD_CONFIG" ]; then
    echo "Error: The $CHIP has no built-in USB-JTAG; debugging it needs an external JTAG adapter." >&2
    exit 1
fi

# The LLDB of the Swift toolchain the build uses (Xcode's works too).
SWIFT_TOOLCHAIN="${ESPSWIFT_TOOLCHAIN:-$(cat "$HOME/.espswift/swift-toolchain" 2>/dev/null)}"
LLDB="$SWIFT_TOOLCHAIN/usr/bin/lldb"
[ -x "$LLDB" ] || LLDB="$(xcrun --find lldb)"

# ── OpenOCD ──────────────────────────────────────────────────────

WORK_DIR=$(mktemp -d -t espswift-debug)
OPENOCD_LOG="$WORK_DIR/openocd.log"

openocd -f "$OPENOCD_CONFIG" > "$OPENOCD_LOG" 2>&1 &
OPENOCD_PID=$!
trap 'kill $OPENOCD_PID 2>/dev/null; wait $OPENOCD_PID 2>/dev/null; rm -rf "$WORK_DIR"' EXIT

echo "Starting OpenOCD for the $CHIP..."
for _ in $(seq 1 30); do
    grep -q "Listening on port 3333" "$OPENOCD_LOG" && break
    if ! kill -0 $OPENOCD_PID 2>/dev/null; then
        echo "Error: OpenOCD couldn't connect to the board. Is it connected through its native USB port (labelled USB, not UART)?" >&2
        grep -E "^Error" "$OPENOCD_LOG" | head -5 >&2
        exit 1
    fi
    sleep 0.5
done
if ! grep -q "Listening on port 3333" "$OPENOCD_LOG"; then
    echo "Error: OpenOCD didn't start; see its output:" >&2
    tail -5 "$OPENOCD_LOG" >&2
    exit 1
fi

# ── LLDB ─────────────────────────────────────────────────────────

# Connects to OpenOCD, lets the firmware start up after the reset that
# connecting causes (breakpoints set before it would be lost), and pauses.
cat > "$WORK_DIR/espswift_connect.py" <<'EOF'
import lldb, time

def _wait_until_stopped(listener, process, seconds):
    event = lldb.SBEvent()
    end = time.time() + seconds
    while time.time() < end and process.GetState() != lldb.eStateStopped:
        listener.WaitForEvent(1, event)
    return process.GetState() == lldb.eStateStopped

def espswift_connect(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    listener = debugger.GetListener()
    debugger.SetAsync(True)
    error = lldb.SBError()
    process = target.ConnectRemote(listener, "connect://localhost:3333", "gdb-remote", error)
    if not error.Success():
        result.SetError(f"Couldn't connect to OpenOCD: {error}")
        debugger.SetAsync(False)
        return
    _wait_until_stopped(listener, process, 10)
    print("Letting the firmware start up...")
    process.Continue()
    time.sleep(4)
    process.Stop()
    _wait_until_stopped(listener, process, 10)
    debugger.SetAsync(False)
    print()
    print("The firmware is paused. Set breakpoints, then continue. For example:")
    print("  b Firmware.swift:49  breakpoint on line 49 of Firmware.swift")
    print("  c                    continue")
    print("  bt                   backtrace;  v  variables;  n  next line;  s  step in")
    print("  process interrupt    pause (or Ctrl+C);  quit  stop debugging")

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f espswift_connect.espswift_connect espswift-connect")
EOF

"$LLDB" \
    -o "settings set target.require-hardware-breakpoint true" \
    -o "target create \"$ELF\"" \
    -o "command script import \"$WORK_DIR/espswift_connect.py\"" \
    -o "espswift-connect"
