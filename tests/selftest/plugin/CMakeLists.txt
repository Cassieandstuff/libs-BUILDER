add_library(DemoPlugin SHARED plugin.c)
add_custom_target(DemoGen
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/gen/plugins"
    COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_CURRENT_BINARY_DIR}/gen/plugins/Demo.hky"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/gen/meshes/_1stperson"
    COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_CURRENT_BINARY_DIR}/gen/meshes/_1stperson/a.hkx"
    VERBATIM)

builder_stage_plugin(DemoPlugin MOD "Demo Mod")
builder_stage_files(MOD "Demo Mod" DIR data)
builder_stage_files(MOD "Demo Mod" DIR schema TO "demo/schema" OWNED)
builder_stage_generated(MOD "Demo Mod" DIR gen DEPENDS DemoGen)
builder_package(MOD "Demo Mod" VERSION 1.2.3)
