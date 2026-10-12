#!/bin/bash

# flash.sh
# Flashes a built ESP32 project to a connected board.
#
# This script is typically called from the Xcode Run Script Phase after
# a successful build, but it can also be run manually from the terminal.
#
# Rather than calling esptool.py directly with a single binary, we delegate
# the actual flashing to `idf.py flash`. ESP-IDF projects are not just a
# single .bin file — they consist of three separate binaries that must
# all be written to specific flash offsets:
#
#   1. Bootloader      (build/bootloader/bootloader.bin)     -> 0x0
#   2. Partition table (build/partition_table/partition.bin) -> 0x8000
#   3. Application     (build/<PROJECT>.bin)                 -> 0x10000
#
# `idf.py flash` reads the build directory's flash_args file and writes
# all three binaries in one operation. This is safer than flashing the
# application alone, since mismatched bootloader/partition/app versions
# can cause SHA-256 verification failures at boot time.
#
# Usage: bash flash.sh <project_directory> [build_directory]
# Where <project_directory> is the folder containing CMakeLists.txt
# (e.g. ~/Developer/MyProject/MyProject), and [build_directory] is the
# ESP-IDF build directory. When built from Xcode, the build directory
# lives in DerivedData and build.sh passes it in; it defaults to the
# build/ subdirectory of the project directory.

# ── Argument Validation ──────────────────────────────────────────

# This script expects the path to the project directory as its first
# argument. When called from Xcode, this is the directory containing
# CMakeLists.txt; when called manually, the user provides it.
PROJECT_DIR="$1"

# If no argument was given, $1 is empty. -z tests for empty string.
if [ -z "$PROJECT_DIR" ]; then
    echo "Error: No project directory provided." >&2
    echo "Usage: bash flash.sh <project_directory>" >&2
    exit 1
fi

# The build directory is created by idf.py build. Its absence means
# the project hasn't been built yet, so there's nothing to flash.
# -d tests whether the path exists and is a directory.
BUILD_DIR="${2:-$PROJECT_DIR/build}"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found at $BUILD_DIR" >&2
    echo "Please build the project first." >&2
    exit 1
fi

# ── ESP-IDF Environment Setup ────────────────────────────────────

# Point IDF_PATH at the ESP-IDF installation managed by install.sh.
# All ESPSwift installations live under ~/.espswift/ for predictability.
export IDF_PATH="$HOME/.espswift/esp-idf"

# Xcode's PATH is heavily restricted and does not include Homebrew,
# so /opt/homebrew/bin must be added explicitly before sourcing
# export.sh, or ESP-IDF's setup script will fail to find python3.
# We prepend Homebrew paths so they take precedence over any
# system-bundled Python that might be too old.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

# ESP-IDF finds its Python environment by the version of the first python3
# on PATH. install.sh pins that version in ~/.espswift/python/bin, so that a
# newer Homebrew Python doesn't break the build.
export PATH="$HOME/.espswift/python/bin:$PATH"

# Source ESP-IDF's setup script. This adds idf.py to PATH and exports
# additional environment variables (IDF_TOOLS_EXPORT_CMD, etc.) that
# idf.py needs to find its tools. It also selects the Python virtual
# environment (~/.espressif/python_env/idf<version>_py<version>_env/)
# matching this ESP-IDF version and the detected python3, so
# IDF_PYTHON_ENV_PATH is deliberately left unset.
source "$IDF_PATH/export.sh"

# ── Port Detection ───────────────────────────────────────────────

# Find detect_port.sh in the same directory as this script.
# $0 is this script's path; dirname strips the filename to give the
# containing directory. Using "$(dirname "$0")" makes flash.sh
# location-independent — it works regardless of where the user runs it.
DETECT_PORT="$(dirname "$0")/detect_port.sh"

echo "Detecting ESP32 board..."

# Run the port detection script and capture its stdout into PORT.
# detect_port.sh prints the device path (e.g. /dev/cu.usbmodem...) on
# success and exits 0, or prints an error to stderr and exits 1.
PORT=$(bash "$DETECT_PORT")

# $? holds the exit code of the most recent command. A non-zero exit
# code from detect_port.sh means no device was found.
if [ $? -ne 0 ]; then
    echo "Error: Could not detect an ESP32 board. Is it connected via USB?" >&2
    exit 1
fi

echo "Found Device at $PORT"

# ── Flashing ─────────────────────────────────────────────────────

# idf.py must be run from the project directory. cd with `|| exit 1`
# ensures we abort if the directory becomes unavailable between the
# check above and this point (race condition guard).
cd "$PROJECT_DIR" || exit 1

echo "Flashing project to $PORT..."

# Run idf.py flash with the detected port.
#   -B <dir>   : the build directory to flash from.
#   -p <port>  : the serial port to write to.
#   flash      : the action; reads flash_args from the build directory
#                and writes all three binaries (bootloader, partition
#                table, app).
# idf.py handles baud rate negotiation, reset sequencing, and SHA
# verification automatically.
idf.py -B "$BUILD_DIR" -p "$PORT" flash

echo "Flash complete."