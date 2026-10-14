"""Writes the compiler flags the project's Indexing target uses for code
completion (see setup_indexing.sh) to a response file: the flags with which
the project's Swift code finds what it imports. They're the flags SwiftPM
compiled the Firmware target with (build_package.py), from its build
manifest: ESP-IDF's include paths and definitions, the ESPIDF module, the
modules of the package's dependencies (such as the project's Kit package),
and the macro plugins those use.

The Indexing target passes the response file to the Swift frontend
(-Xfrontend @file), which only accepts the joined form of -I (-I<path>)
there.

Usage: python3 indexing_flags.py <project_dir> <build_dir> <output_rsp>
  project_dir   The project folder, with the Xcode project.
  build_dir     ESP-IDF's build folder.
  output_rsp    The response file to write.
"""

import json
import os
import sys


def swiftpm_scratch_dir(build_dir, project_dir):
    """Where SwiftPM works: in ESP-IDF's build folder, which Xcode builds put
    in DerivedData. A build folder inside the project (idf.py's ./build, for
    builds in Terminal) is in the source folder that Xcode keeps in sync, and
    Xcode would take the Package.swift files of the dependencies SwiftPM
    downloads there for packages of the project. So then SwiftPM works in
    .build/esp-idf in the project folder instead. (A copy of the function in
    build_package.py.)"""
    build_dir, project_dir = os.path.realpath(build_dir), os.path.realpath(project_dir)
    if build_dir.startswith(project_dir + os.sep):
        return os.path.join(project_dir, ".build", "esp-idf")
    return os.path.join(build_dir, "swiftpm")


project_dir, build_dir, output = sys.argv[1:]
triple = "riscv32-none-none-eabi"

# ── SwiftPM's compile command for the Firmware target ────────────

# SwiftPM's build manifest (llbuild YAML) has each compile command on one
# line, as a JSON array: "args: [...]".
lines = open(os.path.join(swiftpm_scratch_dir(build_dir, project_dir), "release.yaml")).read().splitlines()
start = lines.index(f'  "C.Firmware-{triple}-release.module":')
args = next(json.loads(line.strip()[len("args:"):]) for line in lines[start + 1:]
            if line.strip().startswith("args:"))


def for_the_mac(path):
    # Paths SwiftPM adds for the Mac (Xcode's SDK and testing plugins).
    return "/Applications/" in path or ".sdk" in path or "/host/plugins/testing" in path


flags = []
i = 0
while i < len(args):
    arg = args[i]
    value = args[i + 1] if i + 1 < len(args) else ""
    if arg == "-I" and not for_the_mac(value):
        flags.append("-I" + value)  # Swift modules of the package's dependencies
        i += 2
    elif arg == "-Xcc" and value == "-I" and i + 3 < len(args):
        flags.append("-I" + args[i + 3])  # -Xcc -I -Xcc <path>
        i += 4
    elif arg == "-Xcc" and value.startswith("-I"):
        flags.append(value)
        i += 2
    elif arg == "-Xcc" and value == "-isystem" and i + 3 < len(args):
        flags += ["-Xcc", "-isystem" + args[i + 3]]  # -Xcc -isystem -Xcc <path>
        i += 4
    elif arg == "-Xcc" and value.startswith(("-D", "-fmodule-map-file=")) and not for_the_mac(value):
        flags += ["-Xcc", value]
        i += 2
    elif arg == "-Xfrontend" and value in ("-load-plugin-executable", "-load-plugin-library") \
            and i + 3 < len(args) and args[i + 2] == "-Xfrontend":
        # Macros, such as swift-mmio's: -Xfrontend <flag> -Xfrontend <path>.
        if not for_the_mac(args[i + 3]):
            flags += [value, args[i + 3]]
        i += 4
    else:
        i += 1

# ── Response file ────────────────────────────────────────────────

# One argument per line, quoted so paths with spaces survive; each include
# path once.
written = set()
with open(output, "w") as f:
    for flag in flags:
        if flag.startswith("-I") and flag in written:
            continue
        written.add(flag)
        f.write('"' + flag.replace("\\", "\\\\").replace('"', '\\"') + '"\n')
