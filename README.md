# BUILDER

Build-time deploy and packaging for the Skyrim projects. A build only ever writes into its build folder: every product
(an SKSE mod or a desktop app) is staged there as `stage/<config>/<Name>`, laid out exactly as it ships. Deploy then
mirrors that tree into the MO2 mods folder or the tools folder, and `package` zips the same tree for release.

## Opting in

```cmake
include(FetchContent)
FetchContent_Declare(BUILDER
    GIT_REPOSITORY https://github.com/Cassieandstuff/libs-BUILDER.git
    GIT_TAG        <full 40-character commit SHA>)
FetchContent_MakeAvailable(BUILDER)
```

That's all: the `builder_*` functions are global from here on. Pin a full SHA, never a branch. To work on BUILDER
and a consumer together, point the consumer at your checkout in its `CMakeUserPresets.json`:
`"FETCHCONTENT_SOURCE_DIR_BUILDER": "D:/Projects/Common/internal/BUILDER"`.

When a project fetches another project that also uses BUILDER, the first declaration wins: the outer project's pin
governs both.

## Functions

```cmake
builder_stage_plugin(<target> MOD "<Mod Name>")
builder_stage_files(MOD "<Mod Name>" DIR <source dir> [TO <subpath>] [OWNED])
builder_stage_generated(MOD "<Mod Name>" DIR <build dir> DEPENDS <target>... [TO <subpath>] [OWNED])
builder_stage_app(<target> APP "<App Name>" [FILES <dir> AS <name>]...)
builder_package(MOD|APP "<Name>" [VERSION <v>])
```

| Function | Stages into `stage/<config>/<Name>` |
|---|---|
| `builder_stage_plugin` | the plugin DLL and its `.pdb` → `SKSE/Plugins/` |
| `builder_stage_files` | a source tree (`Data/<x>`, a schema folder, …) → the product root or `TO` |
| `builder_stage_generated` | a tree the build makes (packed bundles, compiled menus); `DEPENDS` builds it first |
| `builder_stage_app` | the exe, its `.pdb`, every DLL it loads, Qt's plugins (via `windeployqt` when the target links Qt 6), and each `FILES` folder as `<name>` |
| `builder_package` | adds a zip of the stage to the `package` target |

Rules every stage follows:

- **`_` means "not shipped"**: any path with a `_`-prefixed folder or file, at any depth, is left out.
- **Merge by default**: deploy copies a file only when its contents differ and never deletes what it didn't stage
  (a regenerated bundle beside yours survives). `OWNED` marks a subfolder BUILDER controls completely: it is cleared
  in the stage and at the destination before copying. `FILES` folders of an app are always owned.
- **Symbols travel with their binary**: a `.pdb` is staged and deployed with its DLL/exe; when a build makes none,
  the old one is removed instead of left beside a new binary.
- **App folders hold no stale DLLs**: DLLs at the top of an app folder that the current build didn't stage are removed
  (a Debug/Release switch can't mix runtimes).
- **Debugging runs the stage**: an app's Visual Studio debugger command is set to the staged exe, unless the project
  set its own `VS_DEBUGGER_COMMAND`.

Call every function for one product in the directory that creates its target: CMake only accepts post-build commands
there, and BUILDER wires them at the end of that directory.

**Limitation**: staging and deploy run after the product's target builds. Editing only data files (no code change)
doesn't rebuild the target, so it doesn't redeploy; rebuild the target to push data-only edits.

## Environment variables

Read at configure time (re-run configure after changing one). These are the only place destinations come from.

| Variable | Used for | Unset | Set to a missing folder |
|---|---|---|---|
| `SKYRIM_MODS_FOLDER` | MO2's `mods` folder: mod `<Name>` deploys to `<root>/<Name>/` | mods aren't deployed | configure fails |
| `SKYRIM_TOOLS_FOLDER` | the tools folder: app `<Name>` deploys to `<root>/<Name>/` | apps aren't deployed | configure fails |
| `SKYRIM_PACKAGE_FOLDER` | release zips, as `<root>/<project>/<git branch>/<Name>[ <version>].zip` | zips go to `build/…/package/<config>/` | configure fails |

Configure prints where each product goes. `-DBUILDER_DEPLOY=OFF` turns deploying off for one build tree without
touching the environment.

## Building and packaging

```bash
cmake --build <build dir> --config RelWithDebInfo                    # builds, stages, deploys
cmake --build <build dir> --config RelWithDebInfo --target package   # release zips (no .pdb)
```

## Self-test

```bash
cmake -DBUILDER_ROOT=<this repo> -DWORK=D:/CB-tmp/builder-selftest "-DGENERATOR=Visual Studio 18 2026" -P tests/RunSelfTest.cmake
```

Builds `tests/selftest` (a mod and an app) with every `SKYRIM_*` folder pointed inside `WORK`, then checks the
deployed layouts, the zips and the configure-time refusals. It never touches a real MO2 or tools folder.
