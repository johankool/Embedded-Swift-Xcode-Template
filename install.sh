#!/bin/bash

# install.sh
# ESPSwift Template installer script.

# This script sets up the complete development environment for
# Embedded Swift on RISC-V based ESP32 chips, including ESP-IDF and the Embedded
# Swift toolchain. All tools are installed under ~/.espswift. to
# ensure a predictable, isolated path that the Xcode build scripts
# can always rely on.

# Usage: bash install.sh

# Exit immediately if any command fails.
# This prevents the script from continuing in a broken state.
set -e

# ---- Constants ----

# Root directory for all ESPSwift-managed tools.
# Keeping everything under one directory makes uninstallation easy
# and avoids conflicts with other ESP-IDF installations the user
# might already have.
ESPSWIFT_HOME="$HOME/.espswift"

# ESP-IDF will be cloned into this subdirectory.
IDF_PATH="$ESPSWIFT_HOME/esp-idf"

# The ESP-IDF release to install. Pinned to a stable release tag so
# every install gets the same, tested version; cloning without a tag
# would give whatever ESP-IDF's master branch is on that day.
# Releases: https://github.com/espressif/esp-idf/releases
IDF_VERSION="v6.1"

# The Swift release to install. Embedded Swift for RISC-V ships with the
# swift.org release toolchains, so a development snapshot is not needed.
# (Xcode's own toolchain cannot be used: it does not include the Embedded
# Swift standard library.)
# Releases: https://www.swift.org/install/macos/
SWIFT_VERSION="6.4.0"
SWIFT_TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-$SWIFT_VERSION-RELEASE.xctoolchain"

# ESP-IDF's own tool installer (xtensa toolchain, openocd, etc.)
# will place binaries here instead of the default ~/.espressif/.
# IDF_TOOLS_PATH="$ESPSWIFT_HOME/tools"

# ---- Setup ----

echo "Starting ESPSwift installation..."

# Create the root directory if it does not exist.
mkdir -p "$ESPSWIFT_HOME"

# ---- Prerequisites ----

# Check for the tools ESP-IDF needs before downloading anything, so a
# missing tool is reported up front instead of after a large download.
#   - Python 3.10 or newer (macOS's built-in python3 is 3.9)
#   - CMake and Ninja (ESP-IDF expects them from Homebrew on macOS)
# Homebrew is added to PATH explicitly, for Apple silicon and Intel Macs.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MISSING_FORMULAE=()
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' &>/dev/null; then
    MISSING_FORMULAE+=(python)
fi
if ! command -v cmake &>/dev/null; then
    MISSING_FORMULAE+=(cmake)
fi
if ! command -v ninja &>/dev/null; then
    MISSING_FORMULAE+=(ninja)
fi

if [ ${#MISSING_FORMULAE[@]} -gt 0 ]; then
    if command -v brew &>/dev/null; then
        echo "Installing ${MISSING_FORMULAE[*]} via Homebrew..."
        brew install "${MISSING_FORMULAE[@]}"
    else
        echo "Error: ESP-IDF needs Python 3.10 or newer, CMake and Ninja." >&2
        echo "Missing: ${MISSING_FORMULAE[*]}" >&2
        echo "Install Homebrew from https://brew.sh and run this script again," >&2
        echo "or install the missing tools yourself and make sure they are on PATH." >&2
        exit 1
    fi
fi

# ---- Step 1 : ESP-IDF ----

echo "[1/4] Installing ESP-IDF..."

if [ -d "$IDF_PATH" ]; then
    # Skip cloning if ESP-IDF is already present.
    # The user can run this script again safely without re-downloading.
    # An existing installation is never replaced automatically, but
    # warn if it is not the pinned release (e.g. an older install that
    # cloned master).
    INSTALLED_IDF_VERSION=$(git -C "$IDF_PATH" describe --tags 2>/dev/null || echo "unknown")
    if [ "$INSTALLED_IDF_VERSION" = "$IDF_VERSION" ]; then
        echo "ESP-IDF $IDF_VERSION already installed. Skipping."
    else
        echo "Warning: ESP-IDF at $IDF_PATH is $INSTALLED_IDF_VERSION, not $IDF_VERSION." >&2
        echo "To switch, remove it with 'rm -rf $IDF_PATH' and run this script again." >&2
    fi
else
    # Clone the pinned ESP-IDF release with all submodules.
    # --recursive is required because ESP-IDF depends on several
    # git submodules (mbedtls, esp-mqtt, etc.).
    # --depth 1 and --shallow-submodules skip the git history, which
    # is not needed to build and makes the download much smaller.
    git clone --recursive --branch "$IDF_VERSION" --depth 1 --shallow-submodules \
        https://github.com/espressif/esp-idf.git "$IDF_PATH"
    
    # Install the tools for the RISC-V chips the template supports only
    # (Embedded Swift doesn't support the Xtensa chips), which keeps the
    # download small. They all share the same RISC-V compiler.
    # Passing IDF_TOOLS_PATH redirects all binaries to ~/.espswift/tools/
    # instead of the default ~/.espressif/.
    # export IDF_TOOLS_PATH="$IDF_TOOLS_PATH"
    "$IDF_PATH/install.sh" esp32c2,esp32c3,esp32c5,esp32c6,esp32c61,esp32h2,esp32p4

    echo "ESP-IDF installed successfully."
fi


# ---- Step 2: Embedded Swift Toolchain ----

echo "[2/4] Installing Swift $SWIFT_VERSION toolchain..."

if [ -x "$SWIFT_TOOLCHAIN/usr/bin/swiftc" ]; then
    echo "Swift $SWIFT_VERSION already installed. Skipping."
else
    # Use swiftly, the Swift toolchain manager, if the user has it (installed
    # by swift.org's installer in ~/.swiftly, or via Homebrew), so the
    # toolchain shows up in `swiftly list` alongside their others.
    # Without --use, swiftly installs the toolchain without changing which
    # toolchain is active.
    SWIFTLY_BIN=$(command -v swiftly || true)
    if [ -z "$SWIFTLY_BIN" ] && [ -x "$HOME/.swiftly/bin/swiftly" ]; then
        SWIFTLY_BIN="$HOME/.swiftly/bin/swiftly"
    fi

    if [ -n "$SWIFTLY_BIN" ]; then
        echo "Installing with swiftly ($SWIFTLY_BIN)..."
        "$SWIFTLY_BIN" install "$SWIFT_VERSION" --assume-yes
    else
        # Otherwise download swift.org's toolchain installer and install it
        # into ~/Library/Developer/Toolchains, which needs no sudo.
        echo "Downloading Swift $SWIFT_VERSION from swift.org..."
        SWIFT_PKG_DIR=$(mktemp -d)
        SWIFT_PKG="$SWIFT_PKG_DIR/swift-$SWIFT_VERSION-RELEASE-osx.pkg"
        curl -fL "https://download.swift.org/swift-$SWIFT_VERSION-release/xcode/swift-$SWIFT_VERSION-RELEASE/swift-$SWIFT_VERSION-RELEASE-osx.pkg" -o "$SWIFT_PKG"
        installer -pkg "$SWIFT_PKG" -target CurrentUserHomeDirectory
        rm -rf "$SWIFT_PKG_DIR"
    fi

    if [ ! -x "$SWIFT_TOOLCHAIN/usr/bin/swiftc" ]; then
        echo "Error: Swift $SWIFT_VERSION was not installed at $SWIFT_TOOLCHAIN" >&2
        exit 1
    fi

    echo "Swift $SWIFT_VERSION installed successfully."
fi

# Record which toolchain to use. build.sh and the project's CMakeLists.txt
# read this file, so projects follow the toolchain install.sh installed.
echo "$SWIFT_TOOLCHAIN" > "$ESPSWIFT_HOME/swift-toolchain"

# ---- Step 3: Install Xcode Template ----

echo "[3/4] Installing Xcode template..."

# The directory where Xcode looks for custom project templates.
XCODE_TEMPLATES_DIR="$HOME/Library/Developer/Xcode/Templates/Project Templates/Other"
XCODE_BUILTIN_TEMPLATE="/Applications/Xcode.app/Contents/Developer/Library/Xcode/Templates/Project Templates/Other/External Build System.xctemplate"
TARGET_TEMPLATE="$XCODE_TEMPLATES_DIR/ESP32 RISC-V.xctemplate"

# Create the directory if it does not exist.
# This is common on fresh macOS installations where Xcode Templates
# have never been customized before.
mkdir -p "$XCODE_TEMPLATES_DIR"

# The template used to be called ESP32-C6 and supported only that chip.
# Remove it, so Xcode doesn't offer both.
rm -rf "$XCODE_TEMPLATES_DIR/ESP32-C6.xctemplate"

# Start from Xcode's built-in External Build System template,
# which already has the correct Targets, Options, and Image keys.
# We'll then overlay our customizations on top.
# Copy the template's contents ("/.") rather than the folder itself: when
# the template is already installed, copying the folder would nest it
# inside the existing one instead of updating it.
cp -R "$XCODE_BUILTIN_TEMPLATE/." "$TARGET_TEMPLATE"

# Overlay our custom files (main.swift) and overwrite TemplateInfo.plist.
# -R copies the directory recursively.
# Existing files will be overwritten, so re-running install.sh
# always gives the user the latest version of the template.
cp -R "$(dirname "$0")/Xcode Template/ESP32 RISC-V.xctemplate/"* "$TARGET_TEMPLATE/"

# Grant execute permission to build.sh so Xcode can run it.
# cp -R does not always preserve execute permissions.
chmod +x "$TARGET_TEMPLATE/build.sh"

# The template's Indexing target (used for code completion) must name the
# Swift toolchain by its identifier, which includes the build date, so fill
# it in here. Projects keep the toolchain they were created with.
# (An alias toolchain with a fixed identifier would avoid that, but any extra
# toolchain whose usr/ links to another breaks Xcode's code completion.)
SWIFT_TOOLCHAIN_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$SWIFT_TOOLCHAIN/Info.plist")
python3 - "$TARGET_TEMPLATE/TemplateInfo.plist" "$SWIFT_TOOLCHAIN_ID" <<'EOF'
import plistlib, sys
path, toolchain_id = sys.argv[1:]
with open(path, "rb") as f:
    template = plistlib.load(f)
for target in template["Targets"]:
    settings = target.get("SharedSettings", {})
    if settings.get("TOOLCHAINS") == "ESPSWIFT_SWIFT_TOOLCHAIN_ID":
        settings["TOOLCHAINS"] = toolchain_id
with open(path, "wb") as f:
    plistlib.dump(template, f, sort_keys=True)
EOF

echo "Xcode Template installed successfully."

# ---- Step 4: Install helper scripts ----

echo "[4/4] Installing helper scripts..."

# Copy all helper scripts (detect_port.sh, flash.sh, monitor.sh, setup_scheme.sh) into ~/.espswift/scripts/
# so that the Xcode build script (build.sh) can call them via a known path.
# These scripts are responsible for finding the connected board,
# flashing the compiled binary to it, and reading the serial output.
mkdir -p "$ESPSWIFT_HOME/scripts"
cp "$(dirname "$0")/scripts/"*.sh "$ESPSWIFT_HOME/scripts/"
chmod +x "$ESPSWIFT_HOME/scripts/"*.sh

# Compile the monitor wrapper binary. Xcode's Scheme > Run > Executable
# only accepts native Mach-O binaries, not shell scripts. This tiny C
# wrapper does nothing but execve() into monitor.sh, satisfying Xcode's
# requirement while keeping the actual logic in shell.
echo "Compiling monitor wrapper binary..."
clang -o "$ESPSWIFT_HOME/scripts/monitor" "$(dirname "$0")/scripts/monitor_wrapper.c"
chmod +x "$ESPSWIFT_HOME/scripts/monitor"

echo "Helper scripts installed successfully."

# ---- Done ----

echo ""
echo "Installation complete."
echo "Restart Xcode and create a new project to use the ESP32 RISC-V Embedded Swift template."