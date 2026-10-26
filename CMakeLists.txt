# ── BUILDER ───────────────────────────────────────────────────────────────────
# Build-time deploy + packaging for the Skyrim projects: every product builds into a stage tree in the build folder,
# laid out exactly as it ships; deploy mirrors that tree into the MO2 mods / tools folder, package zips it.
#
# Consumed via FetchContent (pinned by full commit SHA); the builder_* functions are global once this has run.

cmake_minimum_required(VERSION 3.25)

project(BUILDER
    VERSION 0.1.0
    DESCRIPTION "Stage, deploy and package build output for MO2 mods and tools"
    LANGUAGES NONE)

include("${CMAKE_CURRENT_LIST_DIR}/cmake/Builder.cmake")

option(BUILDER_BUILD_TESTS "Register BUILDER's self-test" ${PROJECT_IS_TOP_LEVEL})
if(BUILDER_BUILD_TESTS)
    enable_testing()
    add_test(NAME builder-selftest
        COMMAND "${CMAKE_COMMAND}"
                "-DBUILDER_ROOT=${CMAKE_CURRENT_SOURCE_DIR}"
                "-DWORK=${CMAKE_CURRENT_BINARY_DIR}/selftest"
                "-DGENERATOR=${CMAKE_GENERATOR}"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/RunSelfTest.cmake")
endif()
