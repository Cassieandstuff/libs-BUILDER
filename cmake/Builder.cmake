# Builder.cmake — the builder_* API. See README.md for the contract; comments here carry only the why.
#
# Every product (a mod or an app) is staged into ${CMAKE_BINARY_DIR}/stage/<config>/<Name>, the exact shipped layout.
# The staging and the deploy run as POST_BUILD commands of the product's target ("driver"), emitted once at the end of
# the directory that created it: CMake only accepts POST_BUILD commands from the target's own directory.
include_guard(GLOBAL)

option(BUILDER_DEPLOY "Deploy every staged product at the end of its build (needs SKYRIM_MODS_FOLDER / SKYRIM_TOOLS_FOLDER)" ON)

# ── internals ─────────────────────────────────────────────────────────────────

function(_builder_stage_dir out name)
    set(${out} "${CMAKE_BINARY_DIR}/stage/$<CONFIG>/${name}" PARENT_SCOPE)
endfunction()

# Registers (or re-finds) a product. All builder_* calls for one product must come from one directory, before its end.
function(_builder_product out kind name)
    if(name STREQUAL "")
        message(FATAL_ERROR "builder: a product needs a name")
    endif()
    string(MAKE_C_IDENTIFIER "${name}" id)
    get_property(known GLOBAL PROPERTY BUILDER_${id}_KIND SET)
    if(known)
        get_property(k GLOBAL PROPERTY BUILDER_${id}_KIND)
        get_property(dir GLOBAL PROPERTY BUILDER_${id}_DIR)
        get_property(emitted GLOBAL PROPERTY BUILDER_${id}_EMITTED)
        if(NOT k STREQUAL kind)
            message(FATAL_ERROR "builder: '${name}' is staged both as ${k} and as ${kind}")
        endif()
        if(emitted OR NOT dir STREQUAL CMAKE_CURRENT_SOURCE_DIR)
            message(FATAL_ERROR "builder: '${name}' belongs to ${dir}; call every builder_* function for it there "
                                "(POST_BUILD commands can only be added in the target's own directory)")
        endif()
    else()
        set_property(GLOBAL PROPERTY BUILDER_${id}_KIND "${kind}")
        set_property(GLOBAL PROPERTY BUILDER_${id}_NAME "${name}")
        set_property(GLOBAL PROPERTY BUILDER_${id}_DIR  "${CMAKE_CURRENT_SOURCE_DIR}")
        cmake_language(EVAL CODE "cmake_language(DEFER CALL _builder_emit ${id})")
    endif()
    set(${out} ${id} PARENT_SCOPE)
endfunction()

function(_builder_driver id target)
    if(NOT TARGET ${target})
        message(FATAL_ERROR "builder: '${target}' is not a target")
    endif()
    get_property(drv GLOBAL PROPERTY BUILDER_${id}_DRIVER)
    get_property(name GLOBAL PROPERTY BUILDER_${id}_NAME)
    if(drv AND NOT drv STREQUAL target)
        message(FATAL_ERROR "builder: '${name}' already stages ${drv}; one plugin or app per product")
    endif()
    set_property(GLOBAL PROPERTY BUILDER_${id}_DRIVER ${target})
endfunction()

# Appends script steps; '|' joins lists inside one argument so ';' never splits a path list in a build command.
function(_builder_step id)
    set_property(GLOBAL APPEND PROPERTY BUILDER_${id}_COMMANDS
        COMMAND "${CMAKE_COMMAND}" ${ARGN} -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuilderRun.cmake")
endfunction()

function(_builder_tree id dir to owned filter)
    get_property(name GLOBAL PROPERTY BUILDER_${id}_NAME)
    _builder_stage_dir(stage "${name}")
    if(to)
        set(stage "${stage}/${to}")
    endif()
    if(owned)
        if(NOT to)
            message(FATAL_ERROR "builder: OWNED needs TO <subpath> ('${name}'): an owned product root would erase "
                                "everything else in its destination")
        endif()
        set_property(GLOBAL APPEND PROPERTY BUILDER_${id}_OWNED "${to}")
        set(owned 1)
    else()
        set(owned 0)
    endif()
    _builder_step(${id} -DMODE=tree "-DSRC=${dir}" "-DDST=${stage}" -DOWNED=${owned} -DFILTER=${filter})
endfunction()

function(_builder_env out var)
    set(value "$ENV{${var}}")
    if(value STREQUAL "")
        set(${out} "" PARENT_SCOPE)
        return()
    endif()
    file(TO_CMAKE_PATH "${value}" value)
    if(NOT IS_DIRECTORY "${value}")
        message(FATAL_ERROR "builder: ${var} is set to '${value}', which is not a directory. Fix the variable, or "
                            "configure with -DBUILDER_DEPLOY=OFF to build without deploying.")
    endif()
    set(${out} "${value}" PARENT_SCOPE)
endfunction()

function(_builder_branch_slug out)
    get_property(slug GLOBAL PROPERTY BUILDER_BRANCH_SLUG)
    if(NOT slug)
        set(slug "no-branch")
        find_package(Git QUIET)
        if(GIT_EXECUTABLE)
            execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --abbrev-ref HEAD
                WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE b RESULT_VARIABLE r
                OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
            if(r EQUAL 0 AND b STREQUAL "HEAD")
                execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --short HEAD
                    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE b RESULT_VARIABLE r
                    OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
            endif()
            if(r EQUAL 0 AND NOT b STREQUAL "")
                string(REGEX REPLACE "[^A-Za-z0-9._-]" "-" slug "${b}")
            endif()
        endif()
        set_property(GLOBAL PROPERTY BUILDER_BRANCH_SLUG "${slug}")
    endif()
    set(${out} "${slug}" PARENT_SCOPE)
endfunction()

# The app step is built at emit time: Qt usage is only known once the target's links are all declared.
function(_builder_app_step id target out)
    get_property(name GLOBAL PROPERTY BUILDER_${id}_NAME)
    _builder_stage_dir(stage "${name}")

    set(search "$<TARGET_FILE_DIR:${target}>")
    if(VCPKG_INSTALLED_DIR AND VCPKG_TARGET_TRIPLET)
        list(APPEND search "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/$<$<CONFIG:Debug>:debug/>bin")
    endif()
    list(JOIN search "|" search)

    set(qt "")
    get_target_property(libs ${target} LINK_LIBRARIES)
    if(libs MATCHES "Qt6?::" AND TARGET Qt6::windeployqt)
        set(qt "-DWINDEPLOYQT=$<TARGET_FILE:Qt6::windeployqt>" "-DQT_DEBUG=$<CONFIG:Debug>")
    endif()

    set(pdb "")
    if(MSVC)
        set(pdb "-DPDB=$<TARGET_PDB_FILE:${target}>")
        set_property(GLOBAL APPEND PROPERTY BUILDER_${id}_PAIRED "$<TARGET_PDB_FILE_NAME:${target}>")
    endif()

    set(${out} COMMAND "${CMAKE_COMMAND}" -DMODE=app
        "-DEXE=$<TARGET_FILE:${target}>" ${pdb}
        "-DRUNTIME_DLLS=$<JOIN:$<TARGET_RUNTIME_DLLS:${target}>,|>"
        "-DSEARCH=${search}" ${qt}
        "-DDST=${stage}"
        -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuilderRun.cmake" PARENT_SCOPE)

    # F5 runs the staged (runnable) copy, unless the project chose its own debugger command.
    get_target_property(cmd ${target} VS_DEBUGGER_COMMAND)
    if(NOT cmd)
        set_target_properties(${target} PROPERTIES
            VS_DEBUGGER_COMMAND           "${stage}/$<TARGET_FILE_NAME:${target}>"
            VS_DEBUGGER_WORKING_DIRECTORY "${stage}")
    endif()
endfunction()

function(_builder_emit id)
    set_property(GLOBAL PROPERTY BUILDER_${id}_EMITTED TRUE)
    get_property(kind     GLOBAL PROPERTY BUILDER_${id}_KIND)
    get_property(name     GLOBAL PROPERTY BUILDER_${id}_NAME)
    get_property(driver   GLOBAL PROPERTY BUILDER_${id}_DRIVER)
    get_property(depends  GLOBAL PROPERTY BUILDER_${id}_DEPENDS)
    get_property(commands GLOBAL PROPERTY BUILDER_${id}_COMMANDS)
    get_property(package  GLOBAL PROPERTY BUILDER_${id}_PACKAGE)
    get_property(version  GLOBAL PROPERTY BUILDER_${id}_VERSION)

    if(NOT driver AND depends)
        list(GET depends 0 driver)
    endif()
    if(NOT driver)
        message(FATAL_ERROR "builder: '${name}' has nothing to build it: stage a plugin or app, or give "
                            "builder_stage_generated a DEPENDS target")
    endif()
    foreach(d IN LISTS depends)
        if(NOT d STREQUAL driver)
            add_dependencies(${driver} ${d})
        endif()
    endforeach()

    get_property(app GLOBAL PROPERTY BUILDER_${id}_APP_TARGET)
    if(app)
        _builder_app_step(${id} ${app} app_cmd)
        set(commands ${app_cmd} ${commands})
    endif()

    _builder_stage_dir(stage "${name}")
    if(BUILDER_DEPLOY)
        if(kind STREQUAL "APP")
            set(var SKYRIM_TOOLS_FOLDER)
        else()
            set(var SKYRIM_MODS_FOLDER)
        endif()
        _builder_env(root ${var})
        if(root)
            get_property(owned  GLOBAL PROPERTY BUILDER_${id}_OWNED)
            get_property(paired GLOBAL PROPERTY BUILDER_${id}_PAIRED)
            list(JOIN owned "|" owned)
            list(JOIN paired "|" paired)
            if(kind STREQUAL "APP")
                set(is_app 1)
            else()
                set(is_app 0)
            endif()
            list(APPEND commands COMMAND "${CMAKE_COMMAND}" -DMODE=deploy
                "-DSRC=${stage}" "-DDST=${root}/${name}" "-DOWNED=${owned}" "-DPAIRED=${paired}" -DAPP=${is_app}
                -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuilderRun.cmake")
            message(STATUS "BUILDER: ${name} -> ${root}/${name}")
        else()
            message(STATUS "BUILDER: ${name}: deploy off (${var} unset)")
        endif()
    else()
        message(STATUS "BUILDER: ${name}: deploy off (BUILDER_DEPLOY=OFF)")
    endif()

    add_custom_command(TARGET ${driver} POST_BUILD ${commands}
        COMMENT "BUILDER: staging ${name}"
        VERBATIM)

    if(package)
        _builder_env(proot SKYRIM_PACKAGE_FOLDER)
        if(proot)
            _builder_branch_slug(slug)
            set(zipdir "${proot}/${CMAKE_PROJECT_NAME}/${slug}")
        else()
            set(zipdir "${CMAKE_BINARY_DIR}/package/$<CONFIG>")
        endif()
        set(zip "${zipdir}/${name}")
        if(version)
            string(APPEND zip " ${version}")
        endif()
        add_custom_target(builder-package-${id}
            COMMAND "${CMAKE_COMMAND}" -DMODE=package "-DSRC=${stage}" "-DZIP=${zip}.zip"
                    "-DTMP=${CMAKE_BINARY_DIR}/package-stage/$<CONFIG>/${name}" -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuilderRun.cmake"
            COMMENT "BUILDER: packaging ${name}"
            VERBATIM)
        add_dependencies(builder-package-${id} ${driver})
        set_target_properties(builder-package-${id} PROPERTIES FOLDER "BUILDER")
        if(NOT TARGET package)
            add_custom_target(package)
            set_target_properties(package PROPERTIES FOLDER "BUILDER")
        endif()
        add_dependencies(package builder-package-${id})
    endif()
endfunction()


# ── API ───────────────────────────────────────────────────────────────────────

# builder_stage_plugin(<target> MOD "<Mod Name>")
function(builder_stage_plugin target)
    cmake_parse_arguments(PARSE_ARGV 1 A "" "MOD" "")
    _builder_product(id MOD "${A_MOD}")
    _builder_driver(${id} ${target})
    _builder_stage_dir(stage "${A_MOD}")
    set(pdb "")
    if(MSVC)
        # A stale pdb beside a new dll makes crash loggers resolve every frame to the wrong function.
        set(pdb "-DOPTIONAL=$<TARGET_PDB_FILE:${target}>")
        set_property(GLOBAL APPEND PROPERTY BUILDER_${id}_PAIRED "SKSE/Plugins/$<TARGET_PDB_FILE_NAME:${target}>")
    endif()
    _builder_step(${id} -DMODE=files "-DFILES=$<TARGET_FILE:${target}>" ${pdb} "-DDST=${stage}/SKSE/Plugins")
endfunction()

# builder_stage_files(MOD "<Mod Name>" DIR <source dir> [TO <subpath>] [OWNED])
function(builder_stage_files)
    cmake_parse_arguments(PARSE_ARGV 0 A "OWNED" "MOD;DIR;TO" "")
    _builder_product(id MOD "${A_MOD}")
    cmake_path(ABSOLUTE_PATH A_DIR BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE)
    if(NOT IS_DIRECTORY "${A_DIR}")
        message(FATAL_ERROR "builder_stage_files: '${A_DIR}' is not a directory")
    endif()
    _builder_tree(${id} "${A_DIR}" "${A_TO}" "${A_OWNED}" 1)
endfunction()

# builder_stage_generated(MOD|APP "<Name>" DIR <build dir> DEPENDS <target>... [TO <subpath>] [OWNED])
# Staged verbatim, no '_' rule: build output is already exactly what ships (Skyrim's own _1stperson folders included).
function(builder_stage_generated)
    cmake_parse_arguments(PARSE_ARGV 0 A "OWNED" "MOD;APP;DIR;TO" "DEPENDS")
    if(NOT A_DEPENDS)
        message(FATAL_ERROR "builder_stage_generated: DEPENDS names the target(s) that produce '${A_DIR}'")
    endif()
    if(A_MOD AND NOT A_APP)
        _builder_product(id MOD "${A_MOD}")
    elseif(A_APP AND NOT A_MOD)
        _builder_product(id APP "${A_APP}")
    else()
        message(FATAL_ERROR "builder_stage_generated: give exactly one of MOD or APP")
    endif()
    cmake_path(ABSOLUTE_PATH A_DIR BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" NORMALIZE)
    set_property(GLOBAL APPEND PROPERTY BUILDER_${id}_DEPENDS ${A_DEPENDS})
    _builder_tree(${id} "${A_DIR}" "${A_TO}" "${A_OWNED}" 0)
endfunction()

# builder_stage_app(<target> APP "<App Name>" [FILES <dir> AS <name>]...)
function(builder_stage_app target)
    cmake_parse_arguments(PARSE_ARGV 1 A "" "APP" "FILES")
    _builder_product(id APP "${A_APP}")
    _builder_driver(${id} ${target})
    set_property(GLOBAL PROPERTY BUILDER_${id}_APP_TARGET ${target})
    list(LENGTH A_FILES n)
    math(EXPR rem "${n} % 3")
    if(NOT rem EQUAL 0)
        message(FATAL_ERROR "builder_stage_app: FILES takes '<dir> AS <name>' triples")
    endif()
    while(A_FILES)
        list(POP_FRONT A_FILES dir as fname)
        if(NOT as STREQUAL "AS")
            message(FATAL_ERROR "builder_stage_app: FILES takes '<dir> AS <name>' triples (got '${as}')")
        endif()
        cmake_path(ABSOLUTE_PATH dir BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE)
        if(NOT IS_DIRECTORY "${dir}")
            message(FATAL_ERROR "builder_stage_app: '${dir}' is not a directory")
        endif()
        _builder_tree(${id} "${dir}" "${fname}" TRUE 1)
    endwhile()
endfunction()

# builder_package(MOD|APP "<Name>" [VERSION <v>])
function(builder_package)
    cmake_parse_arguments(PARSE_ARGV 0 A "" "MOD;APP;VERSION" "")
    if(A_MOD AND NOT A_APP)
        _builder_product(id MOD "${A_MOD}")
    elseif(A_APP AND NOT A_MOD)
        _builder_product(id APP "${A_APP}")
    else()
        message(FATAL_ERROR "builder_package: give exactly one of MOD or APP")
    endif()
    set_property(GLOBAL PROPERTY BUILDER_${id}_PACKAGE TRUE)
    set_property(GLOBAL PROPERTY BUILDER_${id}_VERSION "${A_VERSION}")
endfunction()
