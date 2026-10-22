# doa4 - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(doa4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(DOA4_SOURCES
    src/main.cpp
)

if(WIN32)
    list(APPEND DOA4_SOURCES src/doa4.rc)  # exe icon (src/doa4.ico)
endif()

if(WIN32)
    add_executable(doa4 WIN32 ${DOA4_SOURCES})
else()
    add_executable(doa4 ${DOA4_SOURCES})
endif()

rexglue_setup_target(doa4 GPU_PLUGINS xenos)

# Player-facing launcher and settings dialog, built into the project root (src/launcher.cpp; plain Win32, no SDK).
if(WIN32)
    cmake_path(RELATIVE_PATH CMAKE_BINARY_DIR BASE_DIRECTORY ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE DOA4_BUILD_REL)
    add_executable(doa4_launcher WIN32 src/launcher.cpp src/launcher.rc src/launcher.manifest)
    add_executable(doa4_settings WIN32 src/launcher.cpp src/launcher.rc src/launcher.manifest)
    target_compile_definitions(doa4_settings PRIVATE DOA4_SETTINGS_ONLY)
    set_target_properties(doa4_launcher PROPERTIES OUTPUT_NAME "Dead or Alive 4")
    set_target_properties(doa4_settings PROPERTIES OUTPUT_NAME "Dead or Alive 4 Settings")
    foreach(t doa4_launcher doa4_settings)
        target_compile_definitions(${t} PRIVATE "DOA4_GAME_EXE=\"${DOA4_BUILD_REL}/doa4.exe\"")
        set_target_properties(${t} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}
                                              PDB_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
    endforeach()
endif()
