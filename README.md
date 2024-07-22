My attempt at creating a voxel renderer using zig, WGSL, and the Mach framework.

## Building:
You will need zig version 0.13.0-dev.351+64ef45eb0 (this is the version mach uses)
To build, run `zig build` and then any options you need
-Dsave_folder    (path): specifies a debug save folder to put mods in
-Dgame_dir_name  (str) : the name the engine will use for a save folder under the Appdata folder
-Dengine_dev     (bool): gives access to certain developer features for debugging the engine, such as shader hot reloading for the raytrace shader
-Dno_dev         (bool): disables certain mod dev features
-Dno_validation  (bool): disables certain validation checks in parts of the engine
-Dsrc_folder     (path): relative path from exe location to access shaders. Used for shader hot reloading with engine_dev
Keep in mind mods are still unimplemented, so any mod related options are mostly placeholder

For my dev purposes, I use `zig build -Dsave_folder="../../example_save_dir" -Dengine_dev -Dsrc_folder="../../src"`

## Contributing:
Right now this is just a hobby project for me. In the future, if this ever takes off the ground, I'll accept contributions. But as of now, no contributions will be accepted.
