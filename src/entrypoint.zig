const std = @import("std");
const mach = @import("mach");
const aio = @import("aio");
const coro = @import("coro");
const JobRunner = @import("JobRunner.zig");
const tracer = @import("tracer");
const zware = @import("zware");
const allys = @import("allocators.zig");
// TODO: remove this functionality from entrypoint, place it in here
const wasm_spawner = @import("game_mods/wasm_loader.zig");

const save = @import("save_resolver.zig");

pub usingnamespace @import("./app.zig");
const config = @import("config");
const App = @import("./app.zig");

pub const modules = .{
    mach.Core,
    @import("./app.zig"),
};

pub const tracer_impl = tracer.none;

// TODO: figure out what to do with assets directory with !config.dev
// TODO: instead of failing, create an init fail function
// TODO: in all files: get rid of using mach.core.allocator, use one from allys
// TODO: move wasm module creating code to a mach module??
// TODO: turn this into a "library" of sorts aka let the app handle the entrypoint
pub fn main() !void {
    allys.init();
    defer allys.deinit();

    const ally = allys.LongAllocator; // TODO: remove this alias
    _ = ally; // autofix
    const scratch = allys.TickAllocator; // TODO: remove this alias
    mach.core.allocator = allys.LongAllocator;
    save.changeCWDToSave(scratch); // args specified in build options

    // var jobs: JobRunner = undefined;
    // try jobs.init(ally);
    // defer jobs.deinit(ally);

    // var wasm_mod_bytes: [][]u8 = undefined;
    // // TODO: move mods_getter.zig logic here so we don't keep reopening stuff
    // {
    //     var all_mods_dir = try std.fs.cwd().openDir("all_available_mods", .{ .iterate = true });
    //     defer all_mods_dir.close();
    //     const dataslice, const metaslice, const dag = try @import("game_mods/mods_getter.zig").parseAllModsDir(ally, scratch, all_mods_dir);
    //     defer {
    //         for (dataslice, metaslice) |data, meta| {
    //             data.deinit(ally);
    //             meta.deinit(ally);
    //         }
    //         dag.deinit(ally);
    //     }
    //     wasm_mod_bytes = try ally.alloc([]u8, dataslice.len);
    //     errdefer ally.free(wasm_mod_bytes);
    //     const mod_dirs = try scratch.alloc(std.fs.Dir, dataslice.len);
    //     defer {} // TODO
    //     {
    //         var i: u16 = 0;
    //         errdefer for (mod_dirs[0..i]) |*dir| dir.close();
    //         for (dataslice, mod_dirs) |data, *dir| {
    //             dir.* = try all_mods_dir.openDir(data.dirname, .{});
    //             std.debug.assert(i < dataslice.len);
    //             i += 1;
    //         }
    //     }
    //     defer for (mod_dirs) |*dir| dir.close();

    //     const get_bytes_tasks = try scratch.alloc(coro.Task.Generic2(wasm_spawner.spawnWasmMods), dataslice.len);
    //     defer {} // TODO

    //     const resets = try scratch.alloc(coro.ResetEvent, dataslice.len);
    //     defer scratch.free(resets);
    //     @memset(resets, .{});

    //     {
    //         errdefer jobs.scheduler.run(.cancel) catch unreachable;
    //         for (mod_dirs, get_bytes_tasks, 0..) |dir, *task, i| task.* = try jobs.scheduler.spawn(wasm_spawner.spawnWasmMods, .{ ally, dir, @as(u16, @intCast(i)), wasm_mod_bytes }, .{});
    //     }
    //     try jobs.scheduler.run(.wait);
    //     // TODO: error handle for each potential failed task, or just quit the application
    // }
    // defer ally.free(wasm_mod_bytes);
    // var store = zware.Store.init(ally);
    // defer store.deinit();

    // for (wasm_mod_bytes) |bytes| {
    //     _ = try wasm_spawner.createModule(ally, bytes, &store);
    // }
    _ = allys.TickArena.reset(.retain_capacity);
    try mach.core.initModule();
    while (mach.core.tick() catch unreachable) {}
}
