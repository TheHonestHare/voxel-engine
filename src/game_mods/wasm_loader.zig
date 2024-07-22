const std = @import("std");
const aio = @import("aio");
const coro = @import("coro");
const zware = @import("zware");

const Data = @import("mod_folder_parser.zig").Data;
const ModDAG = @import("dep_graph.zig").ModDAG;

pub fn spawnWasmMods(ally: std.mem.Allocator, mod_dir: std.fs.Dir, i: u16, out_bytes: [][]u8) !void {
    out_bytes[i] = try getInitWasmBytes(ally, mod_dir);
    // TODO: determine lifetime requirements of bytes
    // TODO: move the rest of extracting modmeta.json, etc into here
}

// TODO: implement this bruh
pub fn createModule(ally: std.mem.Allocator, bytes: []const u8, store: *zware.Store) !struct { zware.Instance, zware.Module } {
    var module = zware.Module.init(ally, bytes);
    //defer module.deinit();
    try module.decode();
    var instance = zware.Instance.init(ally, store, module);
    try instance.instantiate();
    //defer instance.deinit();
    return .{ instance, module };
}

pub fn getInitWasmBytes(ally: std.mem.Allocator, mod_dir: std.fs.Dir) ![]u8 {
    var init_wasm: std.fs.File = undefined;
    try coro.io.single(aio.OpenAt{ .dir = mod_dir, .path = "main.wasm", .out_file = &init_wasm, .link = .soft });
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
