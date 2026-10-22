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
    add_executable(doa4 WIN32 ${DOA4_SOURCES})
else()
    add_executable(doa4 ${DOA4_SOURCES})
endif()

rexglue_setup_target(doa4 GPU_PLUGINS xenos)
