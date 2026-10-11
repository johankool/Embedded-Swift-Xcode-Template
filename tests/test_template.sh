#!/bin/bash

# test_template.sh
# Creates projects from the Xcode template and builds them, to check that
# the template works for every chip it offers.
#
# Each project is laid out the way Xcode lays out a new project, using the
# template's TemplateInfo.plist: every file goes to the place its
# definition names, with Xcode's placeholders (___PROJECTNAME___,
# ___VARIABLE_chip___, ...) filled in. The project is then built with its
# own build.sh, without flashing (ESPSWIFT_BUILD_ONLY=1).
#
# Builds use the ESP-IDF and Swift toolchain that install.sh installed, so
# run install.sh first. Each chip is a full ESP-IDF build of a few minutes.
#
# Not covered: Xcode itself (how it shows the template and fills in the
# placeholders), flashing, and running on a board.
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
            sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
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

    # Build the way Xcode does, but without flashing. TARGET_TEMP_DIR is
    # left unset, so the build output goes to the project's build/ folder.
    START=$(date +%s)
    if (cd "$SOURCE_DIR" && ESPSWIFT_BUILD_ONLY=1 ./build.sh) > "$LOG" 2>&1 \
        && [ -f "$SOURCE_DIR/build/$PROJECT_NAME.bin" ]; then
        echo "Passed in $(( $(date +%s) - START ))s: $(grep -m1 "^$PROJECT_NAME.bin binary size" "$LOG")"
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
