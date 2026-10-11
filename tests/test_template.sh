#!/bin/bash

# test_template.sh
# Creates projects from the Xcode template and builds them, to check that
# the template works for every chip it offers.
#
# Each project is laid out the way Xcode lays out a new project, using the
# template's TemplateInfo.plist: every file goes to the place its
# definition names, with Xcode's placeholders (___PROJECTNAME___,
# ___VARIABLE_chip___, ...) filled in. The project is then built with its
# own build.sh, without flashing (ESPSWIFT_BUILD_ONLY=1), using this
# repository's helper scripts. Finally the project's Indexing target, which
# Xcode uses for code completion, is built with xcodebuild, using the
# template's settings for it and an Xcode project from tests/fixtures.
#
# Builds use the ESP-IDF and Swift toolchain that install.sh installed, so
# run install.sh first. Each chip is a full ESP-IDF build of a few minutes.
#
# Not covered: Xcode itself (how it shows the template, fills in the
# placeholders and indexes), flashing, and running on a board.
#
# Usage: bash tests/test_template.sh [--keep] [--work-dir DIR] [chip ...]
#   chip            One or more chips from the template's Chip pop-up,
#                   e.g. esp32c6. Default: all of them.
#   --keep          Keep the generated projects and build logs. They are
#                   always kept when a build fails, or with --work-dir.
#   --work-dir DIR  Where to create the projects and logs (<chip>.log).
#                   Default: a new temporary directory.

KEEP=false
WORK_DIR=""
CHIPS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=true ;;
        --work-dir)
            WORK_DIR="$2"
            shift
            ;;
        -h|--help)
            # Print the comment block at the top of this file.
            awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "$0"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *) CHIPS+=("$1") ;;
    esac
    shift
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/Xcode Template/ESP32 RISC-V.xctemplate"
PROJECT_NAME="TemplateTest"

# The chips the template offers, from its Chip pop-up.
ALL_CHIPS=($(python3 -c '
import plistlib, sys
plist = plistlib.load(open(sys.argv[1], "rb"))
chip = next(o for o in plist["Options"] if o["Identifier"] == "chip")
print(" ".join(chip["Values"]))
' "$TEMPLATE/TemplateInfo.plist")) || exit 1

if [ ${#CHIPS[@]} -eq 0 ]; then
    CHIPS=("${ALL_CHIPS[@]}")
fi

for CHIP in "${CHIPS[@]}"; do
    if [[ ! " ${ALL_CHIPS[*]} " =~ " $CHIP " ]]; then
        echo "Error: '$CHIP' is not offered by the template (${ALL_CHIPS[*]})." >&2
        exit 1
    fi
done

if [ -n "$WORK_DIR" ]; then
    mkdir -p "$WORK_DIR" && WORK_DIR="$(cd "$WORK_DIR" && pwd)" || exit 1
else
    WORK_DIR=$(mktemp -d -t espswift-template-test)
    CREATED_WORK_DIR=true
fi
echo "Testing the template for: ${CHIPS[*]}"
echo "Working directory: $WORK_DIR"

# Creates a project for a chip in $WORK_DIR/<chip>, laid out like Xcode
# does it. Fails if a placeholder is left unfilled.
create_project() {
    python3 - "$TEMPLATE" "$WORK_DIR/$1" "$PROJECT_NAME" "$1" <<'EOF'
import os, plistlib, re, sys

template, root, name, chip = sys.argv[1:]
plist = plistlib.load(open(os.path.join(template, "TemplateInfo.plist"), "rb"))
placeholders = {
    "___PROJECTNAME___": name,
    "___FULLUSERNAME___": "Template Test",
    "___DATE___": "today",
    "___VARIABLE_chip___": chip,
}

for node in plist["Nodes"]:
    definition = plist["Definitions"][node]
    # Files go in the source folder (named after the project), except
    # top-level ones, which go next to the .xcodeproj.
    base = root if definition.get("IsTopLevel") else os.path.join(root, name)
    destination = os.path.normpath(os.path.join(base, node))
    os.makedirs(os.path.dirname(destination), exist_ok=True)

    source = os.path.join(template, definition["Path"])
    text = open(source, encoding="utf-8").read()
    for placeholder, value in placeholders.items():
        text = text.replace(placeholder, value)
    leftover = re.findall(r"___[A-Za-z_:]+___", text)
    if leftover:
        sys.exit(f"Unfilled placeholder {leftover[0]} in {definition['Path']}")
    with open(destination, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(destination, os.stat(source).st_mode)
EOF
}

# Adds an Xcode project to the generated project, as Xcode would create it
# from the template. Only Xcode can create one from a template, so this is
# a project Xcode created (tests/fixtures/project.pbxproj); check_indexing
# applies the template's current Indexing settings on top of it.
add_xcode_project() {
    mkdir -p "$WORK_DIR/$1/$PROJECT_NAME.xcodeproj"
    sed "s/___PROJECTNAME___/$PROJECT_NAME/g" "$REPO_ROOT/tests/fixtures/project.pbxproj" \
        > "$WORK_DIR/$1/$PROJECT_NAME.xcodeproj/project.pbxproj"
}

# Builds the Indexing target with xcodebuild, the way Xcode's indexer
# compiles it: with the Indexing target's settings from TemplateInfo.plist
# and the swift-flags.rsp build.sh generated. Checks it compiles exactly the
# Swift files ESP-IDF compiles (both use everything in Sources/).
check_indexing() {
    python3 - "$TEMPLATE" "$WORK_DIR/$1" "$PROJECT_NAME" <<'EOF'
import json, os, plistlib, subprocess, sys

template, project_dir, name = sys.argv[1:]
plist = plistlib.load(open(os.path.join(template, "TemplateInfo.plist"), "rb"))
target = next(t for t in plist["Targets"] if t.get("Name") == "Indexing")

# Xcode only indexes files that belong to the Indexing target, which the
# template declares per file with the target's identifier.
for node, definition in plist["Definitions"].items():
    if node.endswith(".swift") and target.get("TargetIdentifier") not in definition.get("TargetIdentifiers", []):
        sys.exit(f"{node} doesn't belong to the Indexing target ({target.get('TargetIdentifier')}).")

source_dir = os.path.join(project_dir, name)
for generated in (".espswift/swift-flags.rsp", "compile_commands.json"):
    if not os.path.exists(os.path.join(source_dir, generated)):
        sys.exit(f"Missing {generated}: setup_indexing.sh didn't run.")

# install.sh replaces the toolchain placeholder with the identifier of the
# Swift toolchain it installed; do the same with the toolchain the build used.
if target["SharedSettings"].get("TOOLCHAINS") != "ESPSWIFT_SWIFT_TOOLCHAIN_ID":
    sys.exit("The Indexing target's TOOLCHAINS must be ESPSWIFT_SWIFT_TOOLCHAIN_ID, which install.sh replaces.")
toolchain = os.environ.get("ESPSWIFT_TOOLCHAIN") or open(os.path.expanduser("~/.espswift/swift-toolchain")).read().strip()
toolchain_id = plistlib.load(open(os.path.join(toolchain, "Info.plist"), "rb"))["CFBundleIdentifier"]

output = os.path.join(project_dir, "xcodebuild")
settings = [f"{key}={value.replace('___PROJECTNAME___', name).replace('ESPSWIFT_SWIFT_TOOLCHAIN_ID', toolchain_id)}"
            for key, value in target["SharedSettings"].items()]
result = subprocess.run(["xcodebuild", "-project", os.path.join(project_dir, name + ".xcodeproj"),
                         "-target", "Indexing", "-configuration", "Debug",
                         "SYMROOT=" + os.path.join(output, "Products"),
                         "OBJROOT=" + os.path.join(output, "Intermediates"), *settings, "build"],
                        capture_output=True, text=True)
if result.returncode != 0:
    errors = [line for line in result.stdout.splitlines() if "error:" in line]
    sys.exit("Building the Indexing target failed:\n" + "\n".join(errors[:20] or result.stdout.splitlines()[-20:]))

# The Swift files the Indexing target compiled, and those ESP-IDF compiled.
file_lists = [os.path.join(root, f) for root, _, files in os.walk(output)
              for f in files if f == "Indexing.SwiftFileList"]
indexed = {os.path.realpath(line.strip()) for line in open(file_lists[0]) if line.strip()}
compiled = {os.path.realpath(os.path.join(c["directory"], c["file"]))
            for c in json.load(open(os.path.join(source_dir, "compile_commands.json")))
            if c["file"].endswith(".swift")}
if indexed != compiled:
    sys.exit(f"The Indexing target compiles {sorted(indexed)}, but ESP-IDF compiles {sorted(compiled)}.")
EOF
}

FAILED=()

for CHIP in "${CHIPS[@]}"; do
    echo ""
    echo "================================================="
    echo " $CHIP"
    echo "================================================="

    LOG="$WORK_DIR/$CHIP.log"
    SOURCE_DIR="$WORK_DIR/$CHIP/$PROJECT_NAME"

    if ! create_project "$CHIP"; then
        FAILED+=("$CHIP")
        continue
    fi
    add_xcode_project "$CHIP"

    # Build the way Xcode does (which sets PROJECT_DIR and PROJECT_NAME),
    # but without flashing. TARGET_TEMP_DIR is left unset, so the build
    # output goes to the project's build/ folder.
    START=$(date +%s)
    if (cd "$SOURCE_DIR" && ESPSWIFT_BUILD_ONLY=1 ESPSWIFT_SCRIPTS="$REPO_ROOT/scripts" \
            PROJECT_DIR="$WORK_DIR/$CHIP" PROJECT_NAME="$PROJECT_NAME" ./build.sh) > "$LOG" 2>&1 \
        && [ -f "$SOURCE_DIR/build/$PROJECT_NAME.bin" ]; then
        if check_indexing "$CHIP" >> "$LOG" 2>&1; then
            echo "Passed in $(( $(date +%s) - START ))s: $(grep -m1 "^$PROJECT_NAME.bin binary size" "$LOG")"
        else
            echo "Built, but the indexing check failed. Last lines of $LOG:"
            tail -20 "$LOG"
            FAILED+=("$CHIP")
        fi
    else
        echo "Failed after $(( $(date +%s) - START ))s. Last lines of $LOG:"
        tail -20 "$LOG"
        FAILED+=("$CHIP")
    fi
done

echo ""
echo "================================================="
if [ ${#FAILED[@]} -eq 0 ]; then
    echo " All ${#CHIPS[@]} chip(s) passed: ${CHIPS[*]}"
    echo "================================================="
    # Only a temporary directory this script created is removed; a
    # --work-dir directory is left as it is.
    if [ "$KEEP" = false ] && [ "$CREATED_WORK_DIR" = true ]; then
        rm -rf "$WORK_DIR"
    else
        echo "Projects and logs kept in $WORK_DIR"
    fi
    exit 0
else
    echo " Failed: ${FAILED[*]}"
    echo "================================================="
    echo "Projects and logs kept in $WORK_DIR"
    exit 1
fi
