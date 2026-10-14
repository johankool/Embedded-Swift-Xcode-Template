"""Builds a project's firmware package (Firmware/Package.swift, next to the
Xcode project) for the ESP32 with SwiftPM, as a step of the ESP-IDF build. The project's
main/CMakeLists.txt runs it on every build (SwiftPM itself decides what to
rebuild) and links the library it produces into the firmware.

Swift needs ESP-IDF's headers, as the C code sees them. They're taken from
the compile command of an empty C file in the main component
(compile_commands.json, which CMake writes before the build starts), and go
into a SwiftPM toolset file together with the flags Embedded Swift needs.

Usage: python3 build_package.py <build_dir> <flags_source> <project_dir> <package_dir>
                                <swift_bin_dir> <output_lib> [<implicit_include> ...]
  build_dir         ESP-IDF's build folder.
  flags_source      The C file whose compile command provides ESP-IDF's flags.
  project_dir       The project folder, with the Xcode project.
  package_dir       The folder with the firmware's Package.swift.
  swift_bin_dir     The usr/bin folder of the Swift toolchain.
  output_lib        Where to put the built library (libFirmware.a).
  implicit_include  The C compiler's own include folders, such as picolibc's;
                    CMake leaves them out of compile commands.
"""

import json
import os
import shlex
import shutil
import subprocess
import sys


def swiftpm_scratch_dir(build_dir, project_dir):
    """Where SwiftPM works: in ESP-IDF's build folder, which Xcode builds put
    in DerivedData. A build folder inside the project (idf.py's ./build, for
    builds in Terminal) is in the source folder that Xcode keeps in sync, and
    Xcode would take the Package.swift files of the dependencies SwiftPM
    downloads there for packages of the project. So then SwiftPM works in
    .build/esp-idf in the project folder instead. (indexing_flags.py has a
    copy of this function.)"""
    build_dir, project_dir = os.path.realpath(build_dir), os.path.realpath(project_dir)
    if build_dir.startswith(project_dir + os.sep):
        return os.path.join(project_dir, ".build", "esp-idf")
    return os.path.join(build_dir, "swiftpm")


build_dir, flags_source, project_dir, package_dir, swift_bin_dir, output_lib = sys.argv[1:7]
implicit_includes = sys.argv[7:]
scratch_dir = swiftpm_scratch_dir(build_dir, project_dir)
triple = "riscv32-none-none-eabi"

# ── ESP-IDF's C flags ────────────────────────────────────────────

commands = json.load(open(os.path.join(build_dir, "compile_commands.json")))
entry = next(c for c in commands if os.path.realpath(c["file"]) == os.path.realpath(flags_source))


def expand(args):
    """The arguments, with response files (ESP-IDF's toolchain/cflags) read."""
    for arg in args:
        if arg.startswith("@"):
            yield from expand(shlex.split(open(arg[1:]).read()))
        else:
            yield arg


c_flags = []
march, mabi = None, "-mabi=ilp32"
for arg in expand(entry.get("arguments") or shlex.split(entry["command"])):
    if arg.startswith(("-I", "-D")):
        c_flags.append(arg)
    elif arg.startswith("-march="):
        # Espressif's own ISA extensions (_xesp...) aren't known to Clang.
        march = "_".join(part for part in arg.split("_") if not part.startswith("xesp"))
    elif arg.startswith("-mabi="):
        mabi = arg
# The C compiler's own include folders are system folders, as for GCC: no
# warnings from their headers (picolibc redefines some of ESP-IDF's macros).
for path in implicit_includes:
    c_flags += ["-isystem", path]
c_flags = ([march] if march else []) + [mabi, "-fno-pic", "-fno-pie", "-ffunction-sections"] + c_flags

# The flags of ESP-IDF's idf_swift component, which compiled Swift code for
# ESP-IDF before. SwiftPM passes the C flags on to the Swift compiler's C
# importer itself.
swift_flags = [
    "-enable-experimental-feature", "Embedded",
    "-wmo", "-Osize", "-g",
    "-Xfrontend", "-function-sections",
]

toolset = {
    "schemaVersion": "1.0",
    "swiftCompiler": {"extraCLIOptions": swift_flags},
    "cCompiler": {"extraCLIOptions": c_flags},
    # An ELF archiver. SwiftPM would otherwise use Xcode's libtool, which
    # makes Mach-O archives (and Xcode 27's fails SwiftPM's version check).
    "librarian": {"path": os.path.join(swift_bin_dir, "llvm-ar")},
}
os.makedirs(scratch_dir, exist_ok=True)
toolset_path = os.path.join(scratch_dir, "toolset.json")
with open(toolset_path, "w") as f:
    json.dump(toolset, f, indent=2)

# ── swift build ──────────────────────────────────────────────────

result = subprocess.run([
    os.path.join(swift_bin_dir, "swift"), "build",
    "--package-path", package_dir,
    "--scratch-path", scratch_dir,
    "--triple", triple,
    "--configuration", "release",
    "--toolset", toolset_path,
    "--disable-local-rpath",
    # SwiftPM's own build system. Swift Build, the default since Swift 6.4,
    # links C targets with Apple's linker, which can't link ESP32 code.
    "--build-system", "native",
    "--product", "Firmware",
])
if result.returncode != 0:
    sys.exit(result.returncode)

shutil.copyfile(os.path.join(scratch_dir, triple, "release", "libFirmware.a"), output_lib)
