"""Writes the compiler flags the project's Indexing target uses for code
completion (see setup_indexing.sh) to a response file: the flags with which
the project's Swift code finds what it imports. They're the flags SwiftPM
compiled the Firmware target with (build_package.py), from its build
manifest: ESP-IDF's include paths and definitions, the ESPIDF module, the
package's dependencies, and the macro plugins those use.

The Indexing target compiles all the Swift code in Sources/ as one module,
so that every file gets code completion. One package target importing
another (`import Blink`) would then see its declarations twice, once
compiled and once from SwiftPM's module, and calls would be ambiguous. So
the Indexing target finds Swift modules in a folder of its own,
.espswift/modules: SwiftPM's modules for the package's dependencies, and
empty stand-ins for the package's own targets.

The Indexing target passes the response file to the Swift frontend
(-Xfrontend @file), which only accepts the joined form of -I (-I<path>)
there.

Usage: python3 indexing_flags.py <project_dir> <build_dir> <espswift_dir>
  project_dir   The folder with Package.swift and Sources/.
  build_dir     ESP-IDF's build folder.
  espswift_dir  Where to write include-paths.rsp and modules/ (the source
                folder's .espswift folder).
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

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


project_dir, build_dir, espswift_dir = sys.argv[1:]
triple = "riscv32-none-none-eabi"

# ── SwiftPM's compile command for the Firmware target ────────────

# SwiftPM's build manifest (llbuild YAML) has each compile command on one
# line, as a JSON array: "args: [...]".
lines = open(os.path.join(swiftpm_scratch_dir(build_dir, project_dir), "release.yaml")).read().splitlines()
start = lines.index(f'  "C.Firmware-{triple}-release.module":')
args = next(json.loads(line.strip()[len("args:"):]) for line in lines[start + 1:]
            if line.strip().startswith("args:"))
swiftc = args[0]


def for_the_mac(path):
    # Paths SwiftPM adds for the Mac (Xcode's SDK and testing plugins).
    return "/Applications/" in path or ".sdk" in path or "/host/plugins/testing" in path


flags = []
swiftpm_modules = None
i = 0
while i < len(args):
    arg = args[i]
    value = args[i + 1] if i + 1 < len(args) else ""
    if arg == "-I" and value.endswith("/Modules"):
        swiftpm_modules = value  # replaced by .espswift/modules, below
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

# ── Swift modules ────────────────────────────────────────────────

# The package's own Swift targets: the folders in Sources/ with Swift files.
sources = os.path.join(project_dir, "Sources")
own_targets = {name for name in os.listdir(sources)
               if any(f.endswith(".swift") for _, _, files in os.walk(os.path.join(sources, name)) for f in files)}

modules = os.path.join(espswift_dir, "modules")
os.makedirs(modules, exist_ok=True)
wanted = set()

# Dependencies: links to SwiftPM's modules, which stay up to date.
for entry in sorted(os.listdir(swiftpm_modules)) if swiftpm_modules else []:
    name, extension = os.path.splitext(entry)
    if extension == ".swiftmodule" and name not in own_targets:
        link = os.path.join(modules, entry)
        if os.path.realpath(link) != os.path.realpath(os.path.join(swiftpm_modules, entry)):
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(os.path.join(swiftpm_modules, entry), link)
        wanted.add(entry)

# The package's own targets: empty modules, made once (and again after a
# Swift update), so the files Xcode indexes don't change on every build.
for name in sorted(own_targets):
    stand_in = os.path.join(modules, name + ".swiftmodule")
    if not os.path.isfile(stand_in) or os.path.getmtime(stand_in) < os.path.getmtime(swiftc):
        with tempfile.TemporaryDirectory() as temp:
            empty = os.path.join(temp, "Empty.swift")
            open(empty, "w").close()
            module = os.path.join(temp, name + ".swiftmodule")
            subprocess.run([swiftc, "-emit-module", "-module-name", name, "-parse-as-library",
                            "-target", triple, "-enable-experimental-feature", "Embedded", "-wmo",
                            "-emit-module-path", module, empty], check=True)
            shutil.copyfile(module, stand_in)
    wanted.add(name + ".swiftmodule")

for entry in os.listdir(modules):
    if entry not in wanted:
        path = os.path.join(modules, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
flags.insert(0, "-I" + modules)

# ── Response file ────────────────────────────────────────────────

# One argument per line, quoted so paths with spaces survive; each include
# path once.
written = set()
with open(os.path.join(espswift_dir, "include-paths.rsp"), "w") as f:
    for flag in flags:
        if flag.startswith("-I") and flag in written:
            continue
        written.add(flag)
        f.write('"' + flag.replace("\\", "\\\\").replace('"', '\\"') + '"\n')
