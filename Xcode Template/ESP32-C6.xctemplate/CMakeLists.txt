# Top-level CMakeLists.txt for an ESP-IDF + Embedded Swift project.
# The following boilerplate must be in this exact order for CMake to work.
cmake_minimum_required(VERSION 3.16)

# Force the Embedded Swift toolchain before ESP-IDF detects it.
if(DEFINED ENV{CMAKE_Swift_COMPILER})
    set(CMAKE_Swift_COMPILER "$ENV{CMAKE_Swift_COMPILER}")
else()
    # Fall back to the newest installed development snapshot (build.sh
    # normally sets CMAKE_Swift_COMPILER; this covers running idf.py directly).
    file(GLOB _swift_snapshots "$ENV{HOME}/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-*.xctoolchain")
    if(NOT _swift_snapshots)
        message(FATAL_ERROR "No Embedded Swift development snapshot toolchain found in ~/Library/Developer/Toolchains. Please run install.sh first.")
    endif()
    list(SORT _swift_snapshots)
    list(GET _swift_snapshots -1 _swift_toolchain)
    set(CMAKE_Swift_COMPILER "${_swift_toolchain}/usr/bin/swiftc")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(___PROJECTNAME___)