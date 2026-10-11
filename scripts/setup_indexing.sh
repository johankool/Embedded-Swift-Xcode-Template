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
#   1. .espswift/swift-flags.rsp in the source folder: the include paths,
#      defines and compiler flags ESP-IDF used for the Swift code, taken from
#      compile_commands.json. The Indexing target reads it with @file.
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

python3 - "$COMPILE_COMMANDS" "$SOURCE_DIR/.espswift/swift-flags.rsp" <<'EOF' || exit 1
import json, shlex, sys

compile_commands, rsp = sys.argv[1:]
swift = [c for c in json.load(open(compile_commands)) if c["file"].endswith(".swift")]
if not swift:
    sys.exit("Error: no Swift sources in compile_commands.json.")
args = swift[0].get("arguments") or shlex.split(swift[0]["command"])

# Leave out what the Indexing target sets itself (target, Embedded mode,
# bridging header, module name, whole-module mode) and what only applies to
# ESP-IDF's build (outputs, parallelism, optimization).
skip_with_value = {"-target", "-module-name", "-module-link-name", "-import-bridging-header",
                   "-output-file-map", "-emit-module-path", "-pch-output-dir", "-j", "-num-threads"}
skip = {"-c", "-emit-module", "-static", "-wmo", "-parse-as-library", "-color-diagnostics", "-Osize"}

flags = []
i = 1  # skip the compiler path
while i < len(args):
    arg = args[i]
    if arg in skip_with_value:
        i += 2
    elif arg == "-enable-experimental-feature" and args[i + 1] == "Embedded":
        i += 2
    elif arg in skip or arg.endswith(".swift"):
        i += 1
    else:
        flags.append(arg)
        i += 1

# One argument per line, quoted so paths with spaces survive.
with open(rsp, "w") as f:
    for flag in flags:
        f.write('"' + flag.replace("\\", "\\\\").replace('"', '\\"') + '"\n')
EOF

cp "$COMPILE_COMMANDS" "$SOURCE_DIR/compile_commands.json"
