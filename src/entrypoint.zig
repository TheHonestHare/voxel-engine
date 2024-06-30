const std = @import("std");
const mach = @import("mach");

pub usingnamespace @import("./app.zig");
const config = @import("config");
const App = @import("./app.zig");

pub const modules = .{
    mach.Core,
    @import("./app.zig"),
};

// TODO: figure out what to do with assets directory with !config.dev
pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = GPA.deinit();
    mach.core.allocator = GPA.allocator();
    const path = std.fs.selfExeDirPathAlloc(mach.core.allocator) catch ".";
    const assets_path = if (config.dev) try std.mem.concat(mach.core.allocator, u8, &.{ path, config.assets_dir }) else ".";
    std.log.err("{s}", .{assets_path});
    try std.process.changeCurDir(assets_path);
    mach.core.allocator.free(path);
    if (config.dev) mach.core.allocator.free(assets_path);

    try mach.core.initModule();
    while (mach.core.tick() catch unreachable) {}
}
