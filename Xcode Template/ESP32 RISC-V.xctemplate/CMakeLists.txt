# Top-level CMakeLists.txt for an ESP-IDF + Embedded Swift project.
# The following boilerplate must be in this exact order for CMake to work.
cmake_minimum_required(VERSION 3.16)

# Force the Embedded Swift toolchain before ESP-IDF detects it.
# build.sh normally sets CMAKE_Swift_COMPILER; the fallbacks cover running
# idf.py directly. Like build.sh, use the toolchain install.sh recorded in
# ~/.espswift/swift-toolchain, or the newest development snapshot on older
# installs that did not record one.
if(DEFINED ENV{CMAKE_Swift_COMPILER})
    set(CMAKE_Swift_COMPILER "$ENV{CMAKE_Swift_COMPILER}")
elseif(EXISTS "$ENV{HOME}/.espswift/swift-toolchain")
    file(STRINGS "$ENV{HOME}/.espswift/swift-toolchain" _swift_toolchain LIMIT_COUNT 1)
    set(CMAKE_Swift_COMPILER "${_swift_toolchain}/usr/bin/swiftc")
else()
    file(GLOB _swift_snapshots "$ENV{HOME}/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-*.xctoolchain")
    if(NOT _swift_snapshots)
        message(FATAL_ERROR "No Swift toolchain found for Embedded Swift. Please run install.sh first.")
    endif()
    list(SORT _swift_snapshots)
    list(GET _swift_snapshots -1 _swift_toolchain)
    set(CMAKE_Swift_COMPILER "${_swift_toolchain}/usr/bin/swiftc")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(___PROJECTNAME___)

# Some components declare C/C++ compiler flags as PUBLIC, so CMake passes
# them on to everything that links them, including the Swift compiler,
# which rejects them ("error: unknown argument"). Limit those flags to C,
# C++ and assembly. Options that are already generator expressions are
# left alone.
idf_build_get_property(_components BUILD_COMPONENTS)
foreach(_component ${_components})
    idf_component_get_property(_lib ${_component} COMPONENT_LIB)
    if(NOT TARGET ${_lib})
        continue()
    endif()
    get_target_property(_options ${_lib} INTERFACE_COMPILE_OPTIONS)
    if(NOT _options)
        continue()
    endif()
    set(_wrapped_options)
    foreach(_option ${_options})
        if(NOT _option MATCHES "^\\$<")
            # A ">" in the flag (e.g. -DHEADER=<path.h>) would end the
            # generator expression early, so escape it.
            string(REPLACE ">" "$<ANGLE-R>" _option "${_option}")
            set(_option "$<$<COMPILE_LANGUAGE:C,CXX,ASM>:${_option}>")
        endif()
        list(APPEND _wrapped_options "${_option}")
    endforeach()
    set_target_properties(${_lib} PROPERTIES INTERFACE_COMPILE_OPTIONS "${_wrapped_options}")
endforeach()
