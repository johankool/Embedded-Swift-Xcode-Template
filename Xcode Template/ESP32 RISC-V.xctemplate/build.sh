#!/bin/bash

# build.sh
# Run by Xcode when you press Build (Cmd+B) or Clean.
#
# The build itself is ESPSwift's build.sh in ~/.espswift/scripts, which
# install.sh installs and updates, so updating ESPSwift updates the build of
# this project too. Set ESPSWIFT_SCRIPTS to use the scripts from elsewhere.

# The version of the ESPSwift template this project's files match. When
# ESPSwift needs projects to change, the build warns about older projects;
# ~/.espswift/scripts/update_project.sh updates them.
export ESPSWIFT_PROJECT_VERSION=1

ESPSWIFT_SCRIPTS="${ESPSWIFT_SCRIPTS:-$HOME/.espswift/scripts}"

if [ ! -f "$ESPSWIFT_SCRIPTS/build.sh" ]; then
    echo "Error: ESPSwift's build script wasn't found at $ESPSWIFT_SCRIPTS/build.sh." >&2
    echo "Please run install.sh from the Embedded Swift Xcode Template." >&2
    exit 1
fi

# Build in the folder this script is in: the project's source folder.
cd "$(dirname "$0")" || exit 1
exec bash "$ESPSWIFT_SCRIPTS/build.sh" "$@"
