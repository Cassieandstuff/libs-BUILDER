# A mod and an app staged, deployed and packaged through BUILDER, the way a consumer does it (driven by RunSelfTest.cmake).
cmake_minimum_required(VERSION 3.25)
project(BuilderSelfTest LANGUAGES C)

include(FetchContent)
FetchContent_Declare(BUILDER SOURCE_DIR "${BUILDER_ROOT}")
FetchContent_MakeAvailable(BUILDER)

add_subdirectory(plugin)

add_library(DemoDep SHARED dep.c)
set_target_properties(DemoDep PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/depbin")
# DemoLoaded sits beside the exe but nothing imports it, the way a render backend is loaded by name.
add_library(DemoLoaded SHARED dep.c)
add_executable(DemoApp app.c)
set_target_properties(DemoApp DemoLoaded PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/appbin")
target_link_libraries(DemoApp PRIVATE DemoDep)
add_dependencies(DemoApp DemoLoaded)
builder_stage_app(DemoApp APP "Demo App" LOADED "DemoLoad*.dll" FILES appdata AS data)
builder_package(APP "Demo App")

# Last, so the zips' umbrella has to find CPack after every product was wired.
if(SELFTEST_CPACK)
    include(CPack)
endif()
