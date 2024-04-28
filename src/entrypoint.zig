const std = @import("std");
const mach = @import("mach");

pub usingnamespace @import("./app.zig");
const config = @import("config");
const App = @import("./app.zig");

pub const GPUInterface = mach.core.wgpu.dawn.Interface;

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = GPA.deinit();
    mach.core.allocator = GPA.allocator();
    const path = std.fs.selfExeDirPathAlloc(mach.core.allocator) catch ".";
    const assets_path = try std.mem.concat(mach.core.allocator, u8, &.{ path, config.assets_dir });
    std.log.err("{s}", .{assets_path});
    try std.os.chdir(assets_path);
    mach.core.allocator.free(path);
    mach.core.allocator.free(assets_path);
    var app: App = undefined;

    try GPUInterface.init(mach.core.allocator, .{});
    try app.init();
    defer app.deinit();
    while (!try mach.core.update(&app)) {}
}
