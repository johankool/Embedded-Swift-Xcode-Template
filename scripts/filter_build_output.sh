#!/bin/bash

# filter_build_output.sh
# Turns ESP-IDF's build output (idf.py) into what Xcode shows well: the
# errors and warnings, as lines Xcode lists in the Issue navigator and that
# jump to the file and line when clicked, and little else. build.sh pipes
# idf.py's output through it, and keeps the full output in a log file.
#
#   - Compiler errors and warnings (Swift, Clang and GCC) are already in the
#     format Xcode recognizes, "/path/file.swift:12:5: error: message", and
#     pass through unchanged, with the source excerpts Swift prints.
#   - CMake errors and warnings ("CMake Error at main/CMakeLists.txt:23")
#     become one line in that format, located at the first line of the
#     project's own files in CMake's call stack. CMake warnings that come
#     from ESP-IDF itself, not from the project, are left out.
#   - Unknown options in sdkconfig.defaults, which ESP-IDF only notes in
#     passing, become warnings on their line.
#   - The rest (CMake's configuration messages, ninja's progress lines and
#     failed commands, idf.py's own messages and flashing instructions,
#     which don't apply here, as Cmd+R flashes) is left out, except for an
#     occasional progress line and the firmware size.
#
# Usage: idf.py build 2>&1 | bash filter_build_output.sh <source_dir> [<count_file>]
#   source_dir  The project's source folder (with CMakeLists.txt); CMake
#               names the project's files relative to it.
#   count_file  If given, receives the number of errors passed on, so the
#               caller can explain a failed build that had none.

SOURCE_DIR="${1:-$PWD}"
COUNT_FILE="$2"

# The project folder: the one with the .xcodeproj, the Sources folder and
# the source folder. Files in it are the project's own, except for the
# libraries the component manager downloads and the build output.
PROJECT_ROOT="$(dirname "$SOURCE_DIR")"

exec awk -v source_dir="$SOURCE_DIR" -v project_root="$PROJECT_ROOT" -v count_file="$COUNT_FILE" '
function out(line) {
    if (line ~ /^[^ ]*: error: / || line ~ /^error: /) errors++
    print line
    fflush()
}

# An absolute path for a file CMake names, which may be relative to the
# source folder.
function absolute(path) {
    return (path ~ /^\//) ? path : source_dir "/" path
}

# Whether a file is one of the project'"'"'s own, which the user can edit.
function is_project_file(path) {
    return index(path, project_root "/") == 1 \
        && path !~ /\/managed_components\// \
        && index(path, source_dir "/build/") != 1
}

# The "file:line" in a line such as "CMake Error at file:line (command):"
# or "  file:line (command)" in a call stack; empty if there is none.
function location(line,    s) {
    if (!match(line, /[^ ]+:[0-9]+ \(/)) return ""
    s = substr(line, RSTART, RLENGTH - 2)
    sub(/^at /, "", s)
    return s
}

# Prints a CMake message (collected by the main loop) as one Xcode issue.
function flush_cmake(    i, loc, path, where, message) {
    where = ""
    for (i = 0; i < n_locations; i++) {
        loc = locations[i]
        path = absolute(substr(loc, 1, match(loc, /:[0-9]+$/) - 1))
        if (is_project_file(path)) {
            where = path substr(loc, RSTART) ": "
            break
        }
    }
    message = cmake_message
    gsub(/  +/, " ", message)
    sub(/^ /, "", message)
    sub(/ $/, "", message)
    if (message == "") message = "CMake " cmake_severity
    if (cmake_severity == "error") {
        out(where "error: " message)
    } else if (where != "") {
        # Warnings outside the project come from ESP-IDF or a library.
        out(where "warning: " message)
    }
    in_cmake = 0
    n_locations = 0
}

BEGIN {
    in_cmake = 0
    n_locations = 0
    progress_total = 0
    progress_shown = -1
    blank = 1
    errors = 0
}

{
    # ESP-IDF and the compilers may color their output; Xcode shows the
    # escape codes as text.
    gsub(/\033\[[0-9;]*[A-Za-z]/, "")
    gsub(/\033\][^\033]*\033\\/, "")
    sub(/\r$/, "")
}

# The command ninja prints after "FAILED:"; the errors follow it.
skip_next { skip_next = 0; next }

# ── CMake messages ───────────────────────────────────────────────

in_cmake {
    if ($0 ~ /^Call Stack/) { in_stack = 1; next }
    if ($0 ~ /^  / || $0 == "") {
        if (in_stack) {
            loc = location($0)
            if (loc != "") locations[n_locations++] = loc
        } else if ($0 != "") {
            cmake_message = cmake_message " " $0
        }
        next
    }
    flush_cmake()
}

/^CMake (Error|Warning|Deprecation (Error|Warning))( \(dev\))?( at |:)/ {
    in_cmake = 1
    in_stack = 0
    cmake_severity = ($0 ~ /^CMake (Deprecation )?Error/) ? "error" : "warning"
    cmake_message = ""
    loc = location($0)
    if (loc != "") {
        locations[n_locations++] = loc
    } else if (match($0, /^CMake [A-Za-z ()]*: /)) {
        # "CMake Error: message", without a file.
        cmake_message = substr($0, RLENGTH + 1)
    }
    next
}

# ── ESP-IDF configuration (Kconfig) ─────────────────────────────

# "NOTE: unknown kconfig symbol "FOO" assigned to "y" in .../sdkconfig.defaults"
/^NOTE: unknown kconfig symbol / {
    symbol = $0; sub(/^NOTE: unknown kconfig symbol '"'"'/, "", symbol); sub(/'"'"'.*/, "", symbol)
    file = $0; sub(/.* in /, "", file)
    line_number = 0
    n = 0
    while ((getline text < file) > 0) {
        n++
        if (index(text, "CONFIG_" symbol "=") == 1) { line_number = n; break }
    }
    close(file)
    where = is_project_file(file) ? file (line_number ? ":" line_number : "") ": " : ""
    out(where "warning: Unknown ESP-IDF option CONFIG_" symbol "; it has no effect. Check its name with idf.py menuconfig.")
    next
}

# ── Noise ────────────────────────────────────────────────────────

/^FAILED: / { skip_next = 1; next }
/^-- / || /^NOTE: / || /^Loading defaults file / { next }
/^CMake Generate step failed/ { next }
/^ninja: (build stopped|error: rebuilding|no work to do)/ { next }
/^(ninja|cmake) failed with exit code / { next }
/^Executing action: / || /^Running (ninja|cmake) in directory / || /^Executing "/ { next }
/^esptool v/ || /^Creating ESP32.* image/ || /^Merged [0-9]+ ELF section/ || /^Successfully created ESP32/ { next }
/^Generated \/.*\.bin$/ || /^Bootloader binary size / { next }
/^Skipping linker script generation/ { next }
/^[0-9]+ errors? generated\.$/ { next }

# SwiftPM, building the Swift package (build_package.py).
/^Building for (production|debugging)\.\.\.$/ || /^Build of product .* complete!/ || /^Build complete!/ { next }
/^warning: .--build-system native. has been deprecated/ { next }
# Building the macros of a dependency for the Mac.
/^ld: warning: building for macOS-[0-9.]+, but linking with dylib .* which was built for newer version/ { next }

# The partition table, between two lines of asterisks.
/^Partition table binary generated/ { in_partitions = 1; next }
in_partitions { if (/^\*+$/ && ++partition_rules == 2) { in_partitions = 0; partition_rules = 0 } next }

# A bridging header with an error also fails its precompiled header; the
# error itself is listed already.
/^error: generate-pch command failed/ || /^<unknown>:0: error: failed to emit precompiled header/ { next }

# The flashing instructions idf.py prints last; Cmd+R flashes.
/^Project build complete\. To flash/ { done = 1; next }
done { next }

# ninja: "[12/1103] Building C object ...". Shows one line per tenth of a
# long build, so it is clear the build is progressing. The bootloader is
# built by a smaller ninja build within it, whose progress is not shown.
match($0, /^\[[0-9]+\/[0-9]+\] /) {
    split(substr($0, 2, RLENGTH - 3), step, "/")
    if (step[2] + 0 > progress_total) { progress_total = step[2] + 0; progress_shown = -1 }
    if (step[2] + 0 == progress_total && progress_total >= 50) {
        tenth = int(step[1] * 10 / progress_total)
        if (tenth > progress_shown) {
            progress_shown = tenth
            out(sprintf("Building... %d%% (%d of %d steps)", tenth * 10, step[1], progress_total))
            blank = 0
        }
    }
    next
}

# ── Everything else ──────────────────────────────────────────────

{
    # Collapse runs of blank lines.
    if ($0 == "") { if (blank) next; blank = 1 } else blank = 0
    out($0)
}

END {
    if (in_cmake) flush_cmake()
    if (count_file != "") print errors > count_file
}
'
