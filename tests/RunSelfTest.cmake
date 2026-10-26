# cmake -DBUILDER_ROOT=<repo> -DWORK=<scratch dir> [-DGENERATOR=<generator>] -P RunSelfTest.cmake
#
# Configures + builds tests/selftest with every SKYRIM_* root pointed into WORK (never a real MO2 or tools folder),
# then checks the deployed layouts, the packages, and the configure-time refusals.
cmake_minimum_required(VERSION 3.25)

if(NOT BUILDER_ROOT OR NOT WORK)
    message(FATAL_ERROR "RunSelfTest.cmake: -DBUILDER_ROOT= and -DWORK= are required")
endif()
set(src "${BUILDER_ROOT}/tests/selftest")
set(gen_args "")
if(GENERATOR)
    set(gen_args -G "${GENERATOR}")
endif()

function(expect cond what)
    if(${cond})
        message(STATUS "ok   ${what}")
    else()
        message(SEND_ERROR "FAIL ${what}")
    endif()
endfunction()
macro(present path)
    expect("EXISTS;${path}" "present: ${path}")
endmacro()
macro(absent path)
    expect("NOT;EXISTS;${path}" "absent:  ${path}")
endmacro()

function(run)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE r OUTPUT_VARIABLE o ERROR_VARIABLE o)
    if(NOT r EQUAL 0)
        message(FATAL_ERROR "command failed (${r}): ${ARGN}\n${o}")
    endif()
endfunction()

file(REMOVE_RECURSE "${WORK}")
set(mods  "${WORK}/mods")
set(tools "${WORK}/tools")
set(pkg   "${WORK}/packages")
file(MAKE_DIRECTORY "${mods}" "${tools}" "${pkg}")

# What an earlier deploy left behind: owned leftovers must go, a regenerated bundle beside ours must stay.
file(WRITE "${mods}/Demo Mod/demo/schema/stale.yaml" "old")
file(WRITE "${mods}/Demo Mod/plugins/Skyrim.hky" "kept")
file(WRITE "${tools}/Demo App/Old.dll" "old")
file(WRITE "${tools}/Demo App/data/stale.txt" "old")

set(ENV{SKYRIM_MODS_FOLDER}    "${mods}")
set(ENV{SKYRIM_TOOLS_FOLDER}   "${tools}")
set(ENV{SKYRIM_PACKAGE_FOLDER} "${pkg}")

set(b "${WORK}/build")
run("${CMAKE_COMMAND}" -S "${src}" -B "${b}" ${gen_args} "-DBUILDER_ROOT=${BUILDER_ROOT}")
run("${CMAKE_COMMAND}" --build "${b}" --config Debug)
run("${CMAKE_COMMAND}" --build "${b}" --config Debug --target package)

set(m "${mods}/Demo Mod")
present("${m}/SKSE/Plugins/DemoPlugin.dll")
present("${m}/SKSE/Plugins/DemoPlugin.pdb")
present("${m}/keep.txt")
present("${m}/sub/k.txt")
absent("${m}/sub/_skip.txt")
absent("${m}/_notes")
present("${m}/demo/schema/a.yaml")
absent("${m}/demo/schema/stale.yaml")
present("${m}/plugins/Demo.hky")
present("${m}/plugins/Skyrim.hky")

set(a "${tools}/Demo App")
present("${a}/DemoApp.exe")
present("${a}/DemoApp.pdb")
present("${a}/DemoDep.dll")
present("${a}/data/x.txt")
absent("${a}/Old.dll")
absent("${a}/data/stale.txt")

execute_process(COMMAND git rev-parse --abbrev-ref HEAD WORKING_DIRECTORY "${src}"
    OUTPUT_VARIABLE branch OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE r)
if(NOT r EQUAL 0 OR branch STREQUAL "" OR branch STREQUAL "HEAD")
    file(GLOB branch_dirs LIST_DIRECTORIES true "${pkg}/BuilderSelfTest/*")
    list(GET branch_dirs 0 zipdir)
else()
    string(REGEX REPLACE "[^A-Za-z0-9._-]" "-" branch "${branch}")
    set(zipdir "${pkg}/BuilderSelfTest/${branch}")
endif()
set(modzip "${zipdir}/Demo Mod 1.2.3.zip")
set(appzip "${zipdir}/Demo App.zip")
present("${modzip}")
present("${appzip}")
if(EXISTS "${modzip}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar tf "${modzip}" OUTPUT_VARIABLE listing)
    expect("listing;MATCHES;SKSE/Plugins/DemoPlugin.dll" "mod zip holds the plugin at its Data-relative path")
    expect("NOT;listing;MATCHES;\\.pdb" "mod zip holds no pdb")
    expect("NOT;listing;MATCHES;_skip" "mod zip holds no _-prefixed path")
endif()

# A root that is set but missing refuses to configure; BUILDER_DEPLOY=OFF builds without deploying anywhere.
set(ENV{SKYRIM_MODS_FOLDER} "${WORK}/no-such-folder")
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${src}" -B "${WORK}/build-missing" ${gen_args}
        "-DBUILDER_ROOT=${BUILDER_ROOT}"
    RESULT_VARIABLE r OUTPUT_VARIABLE o ERROR_VARIABLE o)
expect("NOT;r;EQUAL;0" "configure refuses a missing SKYRIM_MODS_FOLDER")
expect("o;MATCHES;SKYRIM_MODS_FOLDER is set to" "the refusal names the variable")

execute_process(COMMAND "${CMAKE_COMMAND}" -S "${src}" -B "${WORK}/build-off" ${gen_args}
        "-DBUILDER_ROOT=${BUILDER_ROOT}" -DBUILDER_DEPLOY=OFF
    RESULT_VARIABLE r OUTPUT_VARIABLE o ERROR_VARIABLE o)
expect("r;EQUAL;0" "BUILDER_DEPLOY=OFF configures with a missing root")
expect("o;MATCHES;deploy off \\(BUILDER_DEPLOY=OFF\\)" "BUILDER_DEPLOY=OFF says so")
