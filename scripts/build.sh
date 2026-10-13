#!/bin/bash

# build.sh
# Builds an ESPSwift project. Each project's own build.sh, which Xcode runs
# when the user presses Build (Cmd+B) or Clean, only calls this script, so
# that updating ESPSwift (install.sh) updates the build of every project.
# Delegates the actual compilation to ESP-IDF, since the Embedded Swift
# toolchain and ESP-IDF are not directly integrated with Xcode's build system.
#
# Runs in the project's source folder (the one with CMakeLists.txt).
# Usage: bash build.sh [build|clean]

echo "================================================="
echo " ESP32 Embedded Swift Build"
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

# ESP-IDF finds its Python environment by the version of the first python3
# on PATH. install.sh pins that version in ~/.espswift/python/bin, so that a
# newer Homebrew Python doesn't break the build.
export PATH="$HOME/.espswift/python/bin:$PATH"

# Source the ESP-IDF environment so idf.py is on PATH.
source "$IDF_PATH/export.sh"

# ── Embedded Swift Toolchain ─────────────────────────────────────

# Use the Swift toolchain install.sh installed, which it records in
# ~/.espswift/swift-toolchain. Set ESPSWIFT_TOOLCHAIN to a .xctoolchain
# path to use a different one. Xcode's own toolchain cannot be used: it
# does not include the Embedded Swift standard library.
if [ -z "$ESPSWIFT_TOOLCHAIN" ] && [ -f "$HOME/.espswift/swift-toolchain" ]; then
    ESPSWIFT_TOOLCHAIN=$(cat "$HOME/.espswift/swift-toolchain")
fi

# Older installs used a development snapshot and did not record it, so
# fall back to the newest installed snapshot. swift-latest.xctoolchain is
# not used, because it points at whichever toolchain was installed last.
if [ -z "$ESPSWIFT_TOOLCHAIN" ]; then
    ESPSWIFT_TOOLCHAIN=$(ls -d "$HOME/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-"*.xctoolchain 2>/dev/null | sort | tail -1)
fi

if [ ! -x "$ESPSWIFT_TOOLCHAIN/usr/bin/swiftc" ]; then
    echo "Error: Swift toolchain not found${ESPSWIFT_TOOLCHAIN:+ at $ESPSWIFT_TOOLCHAIN}." >&2
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

# ── Project Checks ───────────────────────────────────────────────

# Warn (in Xcode's Issue navigator) when the project needs updating with
# update_project.sh, which brings older projects up to date:
#   - its files are older than the template (ESPSWIFT_PROJECT_VERSION, set by
#     the project's build.sh; projects without it predate the version stamp)
#   - its Indexing target, which code completion uses, names another Swift
#     toolchain than the build, e.g. after a Swift upgrade
CURRENT_PROJECT_VERSION=1
UPDATE_COMMAND="~/.espswift/scripts/update_project.sh \"${PROJECT_DIR:-<project folder>}\""

if [ "${ESPSWIFT_PROJECT_VERSION:-0}" -lt "$CURRENT_PROJECT_VERSION" ]; then
    echo "warning: This project was created with an older version of the ESPSwift template. To update it, run in Terminal: $UPDATE_COMMAND"
fi

PBXPROJ="$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj"
if [ -n "$PROJECT_DIR" ] && [ -f "$PBXPROJ" ]; then
    INDEXING_TOOLCHAINS=$(sed -n 's/^[[:space:]]*TOOLCHAINS = \(.*\);$/\1/p' "$PBXPROJ" | sort -u)
    if [ -n "$INDEXING_TOOLCHAINS" ] && [ "$INDEXING_TOOLCHAINS" != "$TOOLCHAINS" ]; then
        echo "warning: Code completion uses another Swift toolchain ($INDEXING_TOOLCHAINS) than the build ($TOOLCHAINS). To update the project, run in Terminal: $UPDATE_COMMAND"
    fi
fi

# ── Build Directory ──────────────────────────────────────────────

# Keep ESP-IDF's build output out of the source tree, in Xcode's
# DerivedData like any other Xcode build. Xcode passes its build
# settings to this script as environment variables; TARGET_TEMP_DIR
# is this target's intermediates folder, so Product > Clean Build
# Folder and deleting DerivedData both remove it.
# Outside Xcode, fall back to ESP-IDF's default ./build directory.
if [ -n "$TARGET_TEMP_DIR" ]; then
    BUILD_DIR="$TARGET_TEMP_DIR/esp-idf"
else
    BUILD_DIR="$PWD/build"
fi

echo "Build directory: $BUILD_DIR"

# ── Target Setup ─────────────────────────────────────────────────

# The chip is set by CONFIG_IDF_TARGET in sdkconfig.defaults. ESP-IDF
# records the chip it configured the project for in sdkconfig, so set the
# target on the first build (which creates sdkconfig) and again whenever
# the chip in sdkconfig.defaults has changed. Setting the target recreates
# sdkconfig from sdkconfig.defaults; the previous one is kept as
# sdkconfig.old.
# Every idf.py call exits on failure so Xcode reports the build as failed.
CHIP=$(sed -n 's/^CONFIG_IDF_TARGET="\(.*\)"$/\1/p' sdkconfig.defaults 2>/dev/null)
CHIP=${CHIP:-esp32c6}
CONFIGURED_CHIP=$(sed -n 's/^CONFIG_IDF_TARGET="\(.*\)"$/\1/p' sdkconfig 2>/dev/null)

if [ "$CONFIGURED_CHIP" != "$CHIP" ]; then
    # Setting the target first cleans the build directory, which idf.py
    # refuses to do if it isn't a CMake build directory. A build that
    # failed before CMake configured the project leaves such a directory
    # behind, holding only idf.py's logs; remove it, so the build doesn't
    # stay stuck. Anything else in it is left to idf.py.
    if [ -d "$BUILD_DIR" ] && [ ! -f "$BUILD_DIR/CMakeCache.txt" ] \
        && [ -z "$(ls -A "$BUILD_DIR" | grep -v '^log$')" ]; then
        echo "Removing an unconfigured build directory left by a failed build..."
        rm -rf "$BUILD_DIR"
    fi
    echo "Setting target to $CHIP..."
    idf.py -B "$BUILD_DIR" set-target "$CHIP" || exit 1
fi

# ── Action ───────────────────────────────────────────────────────

ACTION=${1:-build}

# The helper scripts next to this one (~/.espswift/scripts once installed).
ESPSWIFT_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

if [ "$ACTION" = "clean" ]; then
    echo "Cleaning project..."
    idf.py -B "$BUILD_DIR" fullclean || exit 1
else
    echo "Building project..."
    idf.py -B "$BUILD_DIR" build || exit 1

    # Give the project's Indexing target, which Xcode uses for code
    # completion and jump-to-definition, the compiler settings of this
    # build (see setup_indexing.sh). A failure here doesn't fail the build.
    SETUP_INDEXING="$ESPSWIFT_SCRIPTS/setup_indexing.sh"
    if [ -f "$SETUP_INDEXING" ]; then
        bash "$SETUP_INDEXING" "$PWD" "$BUILD_DIR" || \
            echo "Warning: Could not set up code completion."
    fi
fi

# The build doesn't flash the board: Cmd+R does (run.sh, which Xcode starts
# through the monitor binary), so builds are faster and work without a
# board. Set ESPSWIFT_BUILD_ONLY=1 to also skip recording the build and
# setting up the Xcode scheme (used by tests/test_template.sh).
if [ "$ACTION" != "clean" ] && [ "$ESPSWIFT_BUILD_ONLY" != "1" ]; then
    # ── Record the Build ─────────────────────────────────────────
    # Cmd+R builds and then starts run.sh, which flashes the firmware
    # this records: the source folder and ESP-IDF's build folder.
    printf '%s\n%s\n' "$PWD" "$BUILD_DIR" > "$HOME/.espswift/last-build"

    # ── Xcode Scheme Setup ───────────────────────────────────────
    # On first build, generate a properly configured Xcode scheme
    # so that pressing Cmd+R flashes the board and shows its serial
    # output, instead of asking the user to configure Edit Scheme → Run.
    #
    # setup_scheme.sh is idempotent: it skips if the scheme exists,
    # so subsequent builds incur no overhead and user customizations
    # are preserved.
    SETUP_SCHEME="$ESPSWIFT_SCRIPTS/setup_scheme.sh"
    if [ -x "$SETUP_SCHEME" ]; then
        "$SETUP_SCHEME" "$PROJECT_DIR" "$PROJECT_NAME" || true
    fi
fi

echo "================================================="
echo " Build Complete"
echo "================================================="

