# A mod and an app staged, deployed and packaged through BUILDER, the way a consumer does it (driven by RunSelfTest.cmake).
cmake_minimum_required(VERSION 3.25)
project(BuilderSelfTest LANGUAGES C)

include(FetchContent)
FetchContent_Declare(BUILDER SOURCE_DIR "${BUILDER_ROOT}")
FetchContent_MakeAvailable(BUILDER)

add_subdirectory(plugin)

add_library(DemoDep SHARED dep.c)
set_target_properties(DemoDep PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/depbin")
add_executable(DemoApp app.c)
target_link_libraries(DemoApp PRIVATE DemoDep)
builder_stage_app(DemoApp APP "Demo App" FILES appdata AS data)
builder_package(APP "Demo App")
