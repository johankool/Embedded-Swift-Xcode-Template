#!/bin/bash

# setup_indexing.sh
# Gives Xcode (and other editors) what they need for code completion,
# jump-to-definition and inline errors in an ESPSwift project.
#
# Xcode doesn't index the project's build target, because ESP-IDF builds it.
# Instead, projects have an "Indexing" target that Xcode only indexes, never
# builds as part of Cmd+B. Its fixed settings are in the project (including
# the Swift toolchain, which install.sh writes into the template); this
# script provides the parts that depend on the build:
#
#   1. .espswift/include-paths.rsp in the source folder: the include paths
#      ESP-IDF used for the Swift code (for the bridging header), taken from
#      compile_commands.json. The Indexing target passes it to the Swift
#      frontend with -Xfrontend @file. (A bare @file in OTHER_SWIFT_FLAGS is
#      taken as an input file by Xcode 26, and with -Xcc @file Xcode 26's
#      C importer compiles the file instead of reading it.)
#   2. compile_commands.json in the source folder, where SourceKit-LSP based
#      editors (VS Code, Cursor, ...) find it.
#
# Called by build.sh after every successful build, so the settings follow
# changes such as switching chips or adding libraries.
#
# Usage: bash setup_indexing.sh <source_folder> <build_folder>
#   source_folder    The folder with CMakeLists.txt and main/.
#   build_folder     ESP-IDF's build folder (contains compile_commands.json).

SOURCE_DIR="$1"
BUILD_DIR="$2"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ]; then
    echo "Usage: bash setup_indexing.sh <source_folder> <build_folder>" >&2
    exit 1
fi

COMPILE_COMMANDS="$BUILD_DIR/compile_commands.json"
if [ ! -f "$COMPILE_COMMANDS" ]; then
    echo "Error: $COMPILE_COMMANDS not found." >&2
    exit 1
fi

# ── Compiler flags and compile_commands.json ──────────────

mkdir -p "$SOURCE_DIR/.espswift"
rm -f "$SOURCE_DIR/.espswift/swift-flags.rsp"  # written by earlier versions

python3 - "$COMPILE_COMMANDS" "$SOURCE_DIR/.espswift/include-paths.rsp" <<'EOF' || exit 1
import json, shlex, sys

compile_commands, rsp = sys.argv[1:]
swift = [c for c in json.load(open(compile_commands)) if c["file"].endswith(".swift")]
if not swift:
    sys.exit("Error: no Swift sources in compile_commands.json.")
args = swift[0].get("arguments") or shlex.split(swift[0]["command"])

# Only the include paths, which the bridging header needs: the Indexing
# target passes this file to the Swift frontend (-Xfrontend @file). The
# other flags aren't needed for indexing. In a file, the frontend only
# accepts the joined form, -I<path>.
include_paths = []
for i, arg in enumerate(args):
    if arg == "-I" and i + 1 < len(args):
        include_paths.append(args[i + 1])
    elif arg.startswith("-I") and len(arg) > 2:
        include_paths.append(arg[2:])

# One argument per line, quoted so paths with spaces survive.
with open(rsp, "w") as f:
    for path in include_paths:
        f.write('"-I' + path.replace("\\", "\\\\").replace('"', '\\"') + '"\n')
EOF

cp "$COMPILE_COMMANDS" "$SOURCE_DIR/compile_commands.json"
