const std = @import("std");
const mach = @import("mach");
const aio = @import("aio");
const coro = @import("coro");
const JobRunner = @import("JobRunner.zig");
// TODO: remove this functionality from entrypoint, place it in here
const wasm_spawner = @import("game_mods/wasm_loader.zig");

pub usingnamespace @import("./app.zig");
const config = @import("config");
const App = @import("./app.zig");

pub const modules = .{
    mach.Core,
    @import("./app.zig"),
};

// TODO: figure out what to do with assets directory with !config.dev
// TODO: instead of failing, create an init fail function
// TODO: switch based on if we want a clean exit or just let the OS handle it
pub fn main() !void {
    // TODO: release should use c allocator
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const ally = GPA.allocator();
    const scratch = GPA.allocator();
    mach.core.allocator = ally;
    const path = std.fs.selfExeDirPathAlloc(ally) catch ".";
    const assets_path = if (config.dev) try std.mem.concat(ally, u8, &.{ path, config.assets_dir }) else ".";
    std.log.debug("{s}", .{assets_path});
    try std.process.changeCurDir(assets_path);

    var jobs: JobRunner = undefined;
    try jobs.init(ally);
    defer jobs.deinit(ally);

    // TODO: move mods_getter.zig logic here so we don't keep reopening stuff
    {
        var all_mods_dir = try std.fs.cwd().openDir("mods", .{ .iterate = true });
        defer all_mods_dir.close();
        const dataslice, const metaslice, const dag = try @import("game_mods/mods_getter.zig").parseAllModsDir(ally, scratch, all_mods_dir);
        defer {
            for (dataslice, metaslice) |data, meta| {
                data.deinit(ally);
                meta.deinit(ally);
            }
            dag.deinit(ally);
        }

        const mod_dirs = try scratch.alloc(std.fs.Dir, dataslice.len);
        defer {} // TODO
        {
            var i: u16 = 0;
            errdefer for (mod_dirs[0..i]) |*dir| dir.close();
            for (dataslice, mod_dirs) |data, *dir| {
                dir.* = try all_mods_dir.openDir(data.dirname, .{});
                std.debug.assert(i < dataslice.len);
                i += 1;
            }
        }
        defer for (mod_dirs) |*dir| dir.close();

        const get_bytes_tasks = try scratch.alloc(coro.Task.Generic2(wasm_spawner.spawnWasmMods), dataslice.len);
        defer {} // TODO

        const resets = try scratch.alloc(coro.ResetEvent, dataslice.len);
        defer scratch.free(resets);
        @memset(resets, .{});
        {
            errdefer jobs.scheduler.run(.cancel) catch unreachable;
            for (mod_dirs, get_bytes_tasks, 0..) |dir, *task, i| task.* = try jobs.scheduler.spawn(wasm_spawner.spawnWasmMods, .{ ally, dir, dag, @as(u16, @intCast(i)), resets, &jobs.pool }, .{});
        }

        try jobs.scheduler.run(.wait);
        // TODO: error handle for each
    }

    ally.free(path);
    if (config.dev) mach.core.allocator.free(assets_path);

    try mach.core.initModule();
    while (mach.core.tick() catch unreachable) {}
}
