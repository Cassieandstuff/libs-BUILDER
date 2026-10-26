# BUILDER — working notes

Build-time stage / deploy / package for the Skyrim projects, fetched by pinned commit. README.md is the contract.

## Rules
- The build writes only into the build folder (`stage/<config>/<Name>`); deploy and package read that stage. Nothing
  else in a consumer reads `SKYRIM_MODS_FOLDER` / `SKYRIM_TOOLS_FOLDER` / `SKYRIM_PACKAGE_FOLDER`.
- State lives in GLOBAL properties, never directory variables: functions are global, variables aren't, and a
  consumer may call from any subdirectory or from inside a FetchContent'd project.
- POST_BUILD commands can only be added in the target's own directory, so each product is wired by a deferred call
  at the end of the directory that registered it.
- Lists crossing into a build command are `|`-joined: one argument, no `;` splitting.
- Run `tests/RunSelfTest.cmake` after any change. It points every root into a scratch folder; never test against the
  real MO2 or tools folder.
