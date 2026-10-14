#!/bin/bash

# setup_indexing.sh
# Gives Xcode what it needs for code completion, jump-to-definition and
# inline errors in an ESPSwift project.
#
# Xcode doesn't index the project's build target, because ESP-IDF builds it.
# Instead, projects have an "Indexing" target that Xcode only indexes, never
# builds as part of Cmd+B. Its fixed settings are in the project (including
# the Swift toolchain, which install.sh writes into the template); this
# script provides the parts that depend on the build: .espswift/include-paths.rsp
# in the source folder, the compiler flags with which the firmware's Swift
# code finds what it imports, taken from SwiftPM's build of the firmware
# package (see indexing_flags.py). The Indexing target passes it to the
# Swift frontend with -Xfrontend @file. (A bare @file in OTHER_SWIFT_FLAGS
# is taken as an input file by Xcode 26, and with -Xcc @file Xcode 26's C
# importer compiles the file instead of reading it.)
#
# Called by build.sh after every successful build, so the settings follow
# changes such as switching chips or adding libraries and packages.
#
# Usage: bash setup_indexing.sh <source_folder> <build_folder>
#   source_folder    The folder with CMakeLists.txt and main/.
#   build_folder     ESP-IDF's build folder.

SOURCE_DIR="$1"
BUILD_DIR="$2"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ]; then
    echo "Usage: bash setup_indexing.sh <source_folder> <build_folder>" >&2
    exit 1
fi

mkdir -p "$SOURCE_DIR/.espswift"
python3 "$(dirname "$0")/indexing_flags.py" "$(cd "$SOURCE_DIR/.." && pwd)" "$BUILD_DIR" \
    "$SOURCE_DIR/.espswift/include-paths.rsp"
