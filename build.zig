const std = @import("std");
const mach = @import("mach");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();

    const dev = !(b.option(bool, "no_dev", "disables development features useful for mod devs") orelse false);
    options.addOption(bool, "dev", dev);

    const engine_dev = (b.option(bool, "engine_dev", "enabled debugging features that literally only I (the writer of the engine) care about") orelse false);
    options.addOption(bool, "engine_dev", engine_dev);
    // TODO: option for removing hash validation
    const src_folder = b.option([]const u8, "src_folder", "path to src folder relative to the executable location. Used for shader hot reloading");
    options.addOption(?[]const u8, "src_folder", src_folder);

    const save_folder = b.option([]const u8, "save_folder", "path to a custom development save folder from executable location. Must follow the same save structure as usual");
    options.addOption(?[]const u8, "save_folder", save_folder);
    
    const game_dir = b.option([]const u8, "game_dir_name", "The directory name to use for save folder under std.fs.getAppDataDir");
    options.addOption(?[]const u8, "game_dir_name", game_dir);

    const validation = !(b.option(bool, "no_validation", "disables validation checking") orelse false);
    options.addOption(bool, "validate", validation);

    const exe = b.addExecutable(.{
        .name = "voxel_renderer",
        .root_source_file = b.path("./src/entrypoint.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("config", options);

    const mach_dep = b.dependency("mach", .{ .target = target, .optimize = optimize, .core = true });
    @import("mach").link(mach_dep.builder, exe);
    exe.root_module.addImport("mach", mach_dep.module("mach"));

    if (!target.result.isWasm()) {
        const zware_dep = b.dependency("zware", .{ .target = target, .optimize = optimize });
        exe.root_module.addImport("zware", zware_dep.module("zware"));
    } else return error.WasmNotSupportedYet;

    const aio_dep = b.dependency("zig_aio", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("aio", aio_dep.module("aio"));
    exe.root_module.addImport("coro", aio_dep.module("coro"));

    if (!dev) {
        exe.subsystem = .Windows;
    }
    exe.root_module.addOptions("config", options);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&b.addRunArtifact(exe).step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("./src/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
