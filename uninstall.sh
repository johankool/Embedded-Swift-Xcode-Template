#!/bin/bash

# uninstall.sh
# Removes what install.sh installed.
#
# Always removed (used only by ESPSwift):
#   ~/.espswift             ESP-IDF, helper scripts, toolchain record
#   Xcode template          ESP32 RISC-V (and ESP32-C6, its old name)
#
# Removed only when confirmed, or with --all, because other projects
# may use them too:
#   The Swift toolchain install.sh installed
#   ~/.espressif            ESP-IDF's Python environment and compilers
#   ESP-IDF's component download cache
#
# Never removed: Homebrew and the packages it installed (Python, CMake,
# Ninja), swiftly itself, and your projects.
#
# Usage: bash uninstall.sh [--yes] [--all]
#   --yes  Don't ask for confirmation.
#   --all  Also remove the shared items above without asking.

ASSUME_YES=false
REMOVE_ALL=false

for ARG in "$@"; do
    case "$ARG" in
        -y|--yes) ASSUME_YES=true ;;
        --all) REMOVE_ALL=true ;;
        -h|--help)
            sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $ARG" >&2
            echo "Usage: bash uninstall.sh [--yes] [--all]" >&2
            exit 1
            ;;
    esac
done

# ---- Paths ----

ESPSWIFT_HOME="$HOME/.espswift"
XCODE_TEMPLATES_DIR="$HOME/Library/Developer/Xcode/Templates/Project Templates/Other"
# The template was called ESP32-C6 before it supported other chips.
TEMPLATES=("ESP32 RISC-V.xctemplate" "ESP32-C6.xctemplate")
ESPRESSIF_TOOLS="$HOME/.espressif"
COMPONENT_CACHE="$HOME/Library/Caches/Espressif/ComponentManager"

# install.sh records the Swift toolchain it installed. Installs from
# before that used a development snapshot, which is left alone.
SWIFT_TOOLCHAIN=""
if [ -f "$ESPSWIFT_HOME/swift-toolchain" ]; then
    SWIFT_TOOLCHAIN=$(cat "$ESPSWIFT_HOME/swift-toolchain")
    [ -d "$SWIFT_TOOLCHAIN" ] || SWIFT_TOOLCHAIN=""
fi

# Homebrew and swiftly may not be on PATH when run from Finder or Xcode.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.swiftly/bin:$PATH"

# ---- Helpers ----

# Prints a path's size, e.g. "1.7G".
size_of() {
    du -sh "$1" 2>/dev/null | cut -f1 | tr -d ' '
}

# Asks a yes/no question; the default is no.
confirm() {
    if [ ! -t 0 ]; then
        return 1
    fi
    read -r -p "$1 [y/N] " REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

# ---- What will be removed ----

echo "This removes ESPSwift from your Mac:"
echo ""

FOUND_ANYTHING=false

if [ -d "$ESPSWIFT_HOME" ]; then
    echo "  $ESPSWIFT_HOME ($(size_of "$ESPSWIFT_HOME"))"
    FOUND_ANYTHING=true
fi

for TEMPLATE in "${TEMPLATES[@]}"; do
    if [ -d "$XCODE_TEMPLATES_DIR/$TEMPLATE" ]; then
        echo "  Xcode template: ${TEMPLATE%.xctemplate}"
        FOUND_ANYTHING=true
    fi
done

if [ "$FOUND_ANYTHING" = false ]; then
    echo "  Nothing found: ESPSwift doesn't seem to be installed."
fi

echo ""

if [ "$ASSUME_YES" = false ] && [ "$FOUND_ANYTHING" = true ]; then
    if [ ! -t 0 ]; then
        echo "Error: not running in a terminal. Use --yes to uninstall without confirmation." >&2
        exit 1
    fi
    if ! confirm "Continue?"; then
        echo "Nothing was removed."
        exit 0
    fi
fi

# ---- Remove ESPSwift's own files ----

if [ -d "$ESPSWIFT_HOME" ]; then
    rm -rf "$ESPSWIFT_HOME"
    echo "Removed $ESPSWIFT_HOME"
fi

for TEMPLATE in "${TEMPLATES[@]}"; do
    if [ -d "$XCODE_TEMPLATES_DIR/$TEMPLATE" ]; then
        rm -rf "$XCODE_TEMPLATES_DIR/$TEMPLATE"
        echo "Removed Xcode template ${TEMPLATE%.xctemplate}"
    fi
done

# ---- Shared items ----

# Each is removed with --all, or when confirmed. Without a terminal and
# without --all, they are kept.

if [ -n "$SWIFT_TOOLCHAIN" ]; then
    TOOLCHAIN_NAME=$(basename "$SWIFT_TOOLCHAIN" .xctoolchain)
    echo ""
    if [ "$REMOVE_ALL" = true ] || confirm "Remove the Swift toolchain $TOOLCHAIN_NAME ($(size_of "$SWIFT_TOOLCHAIN"))? Other Swift projects may use it."; then
        # Toolchains installed with swiftly are removed with swiftly, so it
        # stays consistent. Release names look like swift-6.4.0-RELEASE.
        SWIFT_VERSION=$(echo "$TOOLCHAIN_NAME" | sed -n 's/^swift-\(.*\)-RELEASE$/\1/p')
        if [ -n "$SWIFT_VERSION" ] && command -v swiftly &>/dev/null \
            && swiftly list 2>/dev/null | grep -Eq "Swift $SWIFT_VERSION( |\$)"; then
            swiftly uninstall "$SWIFT_VERSION" --assume-yes
        else
            rm -rf "$SWIFT_TOOLCHAIN"
        fi
        echo "Removed Swift toolchain $TOOLCHAIN_NAME"
    fi
fi

if [ -d "$ESPRESSIF_TOOLS" ]; then
    echo ""
    if [ "$REMOVE_ALL" = true ] || confirm "Remove ESP-IDF's tools in $ESPRESSIF_TOOLS ($(size_of "$ESPRESSIF_TOOLS"))? Other ESP-IDF installations may use them."; then
        rm -rf "$ESPRESSIF_TOOLS"
        echo "Removed $ESPRESSIF_TOOLS"
    fi
fi

if [ -d "$COMPONENT_CACHE" ]; then
    echo ""
    if [ "$REMOVE_ALL" = true ] || confirm "Remove ESP-IDF's component download cache ($(size_of "$COMPONENT_CACHE"))? It is downloaded again when needed."; then
        rm -rf "$COMPONENT_CACHE"
        echo "Removed $COMPONENT_CACHE"
    fi
fi

# ---- Done ----

echo ""
echo "Uninstall complete."
echo ""
echo "Not removed:"
echo "  - Homebrew and the packages install.sh may have installed with it"
echo "    (python, cmake, ninja). Remove them with 'brew uninstall' if unused."
echo "  - swiftly, and any development snapshot toolchains installed by"
echo "    earlier versions of install.sh (swift-DEVELOPMENT-SNAPSHOT-*)."
echo "  - Your projects, and their build output in Xcode's DerivedData."
