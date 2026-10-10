#!/bin/bash

# build.sh
# Invoked by Xcode when the user presses Build (Cmd+B).
# Delegates the actual compilation to ESP-IDF, since the Embedded Swift
# toolchain and ESP-IDF are not directly integrated with Xcode's build system.

echo "================================================="
echo " ESP32-C6 Embedded Swift Build"
echo "================================================="

# Xcode provides PROJECT_DIR and PROJECT_NAME.
# The actual source files are in a subdirectory named after the project.
if [ -n "$PROJECT_DIR" ] && [ -n "$PROJECT_NAME" ]; then
    cd "$PROJECT_DIR/$PROJECT_NAME" || exit 1
fi

# ── ESP-IDF Setup ────────────────────────────────────────────────

# ESP-IDF is installed by install.sh into ~/.espswift/esp-idf.
# If a user has their own ESP-IDF and exported IDF_PATH, respect that.
if [ -z "$IDF_PATH" ]; then
    export IDF_PATH="$HOME/.espswift/esp-idf"
fi

if [ ! -d "$IDF_PATH" ]; then
    echo "Error: ESP-IDF not found at $IDF_PATH" >&2
    echo "Please run install.sh first." >&2
    exit 1
fi

# Use the default ESP-IDF tools path (~/.espressif)
# IDF_TOOLS_PATH override did not work as expected during installation.
# IDF_PYTHON_ENV_PATH is left unset: export.sh selects the Python virtual
# environment matching this ESP-IDF version and the detected python3.

# Xcode's PATH is restricted. Add Homebrew BEFORE sourcing export.sh
# so that ESP-IDF can find python3.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

# Source the ESP-IDF environment so idf.py is on PATH.
source "$IDF_PATH/export.sh"

# ── Embedded Swift Toolchain ─────────────────────────────────────

# Use the newest installed development snapshot (install.sh installs
# main-snapshot, whose dated name changes with every snapshot).
# Set ESPSWIFT_TOOLCHAIN to a .xctoolchain path to pin a specific one.
# swift-latest.xctoolchain is not used, because it points at whichever
# toolchain was installed last, which may be a release toolchain.
if [ -z "$ESPSWIFT_TOOLCHAIN" ]; then
    ESPSWIFT_TOOLCHAIN=$(ls -d "$HOME/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-"*.xctoolchain 2>/dev/null | sort | tail -1)
fi

if [ ! -x "$ESPSWIFT_TOOLCHAIN/usr/bin/swiftc" ]; then
    echo "Error: Embedded Swift development snapshot toolchain not found in ~/Library/Developer/Toolchains." >&2
    echo "Please run install.sh first." >&2
    exit 1
fi

echo "Using toolchain: $ESPSWIFT_TOOLCHAIN"

# AFTER sourcing, prepend the Embedded Swift toolchain so it takes
# priority over Xcode's default Swift compiler.
export PATH="$ESPSWIFT_TOOLCHAIN/usr/bin:$PATH"

# Force CMake to use the Embedded Swift toolchain compiler.
export CMAKE_Swift_COMPILER="$ESPSWIFT_TOOLCHAIN/usr/bin/swiftc"

# Select the same toolchain by its bundle identifier.
TOOLCHAINS=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$ESPSWIFT_TOOLCHAIN/Info.plist")
export TOOLCHAINS

# ── Target Setup ─────────────────────────────────────────────────

# Set the target to esp32c6 on first build (creates sdkconfig).
# Every idf.py call exits on failure so Xcode reports the build as failed.
if [ ! -f "sdkconfig" ]; then
    echo "Setting target to esp32c6..."
    idf.py set-target esp32c6 || exit 1
fi

# ── Action ───────────────────────────────────────────────────────

ACTION=${1:-build}

if [ "$ACTION" = "clean" ]; then
    echo "Cleaning project..."
    idf.py fullclean || exit 1
else
    echo "Building project..."
    idf.py build || exit 1

    # After a successful build, attempt to flash the firmware to a
    # connected ESP32-C6 automatically. This mimics the Arduino IDE
    # workflow where Cmd+B both compiles and uploads in one step.
    #
    # If no board is connected, flash.sh will exit with a non-zero
    # status, but we don't propagate that as a build failure since
    # the binary itself built successfully.
    FLASH_SCRIPT="$HOME/.espswift/scripts/flash.sh"
    if [ -x "$FLASH_SCRIPT" ]; then
        echo ""
        echo "================================================="
        echo " Auto-Flashing to ESP32-C6"
        echo "================================================="
        "$FLASH_SCRIPT" "$PROJECT_DIR/$PROJECT_NAME" || \
            echo "Warning: Flash failed or no device connected."
    fi

    # ── Xcode Scheme Setup ───────────────────────────────────────
    # On first build, generate a properly configured Xcode scheme
    # so that pressing Cmd+R launches the serial monitor instead of
    # asking the user to manually configure Edit Scheme → Run.
    #
    # setup_scheme.sh is idempotent: it skips if the scheme exists,
    # so subsequent builds incur no overhead and user customizations
    # are preserved.
    SETUP_SCHEME="$HOME/.espswift/scripts/setup_scheme.sh"
    if [ -x "$SETUP_SCHEME" ]; then
        "$SETUP_SCHEME" "$PROJECT_DIR" "$PROJECT_NAME" || true
    fi
fi

echo "================================================="
echo " Build Complete"
echo "================================================="

