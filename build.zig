const std = @import("std");
const mach = @import("mach");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{ .target = target, .optimize = optimize, .core = true });

    const dev = !(b.option(bool, "no_dev", "disables development features") orelse false);
    const options = b.addOptions();
    options.addOption(bool, "dev", dev);
    const config = options.createModule();
    _ = config; // autofix

    const assets_dir = b.option([]const u8, "assets_dir", "path to assets folder") orelse "\\..\\..\\src\\assets";
    options.addOption([]const u8, "assets_dir", assets_dir);

    const validation = !(b.option(bool, "no_validation", "disables validation checking") orelse false);
    options.addOption(bool, "validate", validation);

    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "voxel_renderer",
        .src = "src/app.zig",
        .custom_entrypoint = "src/entrypoint.zig",
        .target = target,
        .optimize = optimize,
        //.deps = &[_]std.Build.Module.Import{.{.module = options.createModule(), .name = "config"}},
    });

    if (!dev) {
        app.compile.subsystem = .Windows;
    }
    app.compile.root_module.addOptions("config", options);

    if (b.args) |args| app.run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
