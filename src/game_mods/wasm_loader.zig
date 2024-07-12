const std = @import("std");
const aio = @import("aio");
const coro = @import("coro");

const Data = @import("mod_folder_parser.zig").Data;
const ModDAG = @import("dep_graph.zig").ModDAG;

pub fn spawnWasmMods(ally: std.mem.Allocator, mod_dir: std.fs.Dir, dag: ModDAG, i: u16, resets: []coro.ResetEvent, pool: *coro.ThreadPool) !void {
    const bytes = try getInitWasmBytes(ally, mod_dir);
    defer ally.free(bytes);
    if (dag.getModDeps(i)) |deps| {
        for (deps) |dep| try resets[dep].wait();
    }
    _ = try pool.yieldForCompletition(createModule, .{bytes}, .{});
    resets[i].set();
}

// TODO: implement this bruh
pub fn createModule(bytes: []const u8) !void {
    _ = bytes;
    return;
}

pub fn getInitWasmBytes(ally: std.mem.Allocator, mod_dir: std.fs.Dir) ![]u8 {
    var init_wasm: std.fs.File = undefined;
    try coro.io.single(aio.OpenAt{ .dir = mod_dir, .path = "init.wasm", .out_file = &init_wasm, .link = .soft });
    defer init_wasm.close();
    const reader: AioFileReader = .{ .fd = init_wasm };
    var tmp_arraylist = try std.ArrayList(u8).initCapacity(ally, (try init_wasm.stat()).size);
    try reader.reader().readAllArrayList(&tmp_arraylist, std.math.maxInt(usize));
    return tmp_arraylist.toOwnedSlice();
}

pub const AioFileReader = struct {
    fd: std.fs.File,

    pub const Reader = std.io.GenericReader(AioFileReader, (aio.Error || aio.Read.Error), readFn);
    pub fn reader(self: @This()) Reader {
        return .{ .context = self };
    }
};

fn readFn(context: AioFileReader, buffer: []u8) (aio.Error || aio.Read.Error)!usize {
    var out_read: usize = undefined;
    var out_error: aio.Read.Error = undefined;
    try coro.io.single(aio.Read{ .buffer = buffer, .file = context.fd, .out_read = &out_read, .out_error = &out_error });
    return switch (out_error) {
        error.Success => out_read,
        else => |e| e,
    };
}
