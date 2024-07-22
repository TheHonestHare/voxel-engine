const std = @import("std");
const fp = @import("mod_folder_parser.zig");

pub const DAG = @import("dep_graph.zig").ModDAG;
pub const hashModFolder = fp.hashModFolder;
pub const Mod = fp.Mod;
pub const Data = fp.Data;
pub const MetaData = fp.MetaData;
// TODO: maybe use asychronous io for files etc instead of native std.fs
// TODO: decide if next 2 functions should go in seperate files
/// all returned values are allocated with ally, scratch is temporary memory that gets freed
pub fn parseAllModsDir(ally: std.mem.Allocator, scratch: std.mem.Allocator, all_mods_dir: std.fs.Dir) !struct { []const Data, []const MetaData, DAG } {
    const dataslice, const metaslice = try getAllMods(ally, all_mods_dir);
    errdefer for (dataslice, metaslice) |data, meta| {
        data.deinit(ally);
        meta.deinit(ally);
    };
    const order_to_load = try DAG.create(ally, scratch, dataslice);
    return .{ dataslice, metaslice, order_to_load };
}
// TODO: using MultiArrayList here is bad since they're pointers anyways, we should use MultiArrayList on the types directly
/// dir must be opened with iterating capability
pub fn getAllMods(ally: std.mem.Allocator, all_mods_dir: std.fs.Dir) !struct { []const Data, []const MetaData } {
    var iter = all_mods_dir.iterate();
    var out: std.MultiArrayList(fp.Mod) = .{};
    errdefer out.deinit(ally);
    // max of 2^16 - 2 mods
    var i: u16 = 0;

    errdefer {
        const slice = out.slice();
        for (slice.items(.data)[0..i], slice.items(.meta)[0..i]) |data, meta| {
            data.deinit(ally);
            meta.deinit(ally);
        }
    }
    while (try iter.next()) |val| : (i += 1) {
        // TODO: theres probably a better way to do this
        if (val.kind != .directory) continue;
        const mod = try fp.readModDir(ally, all_mods_dir, val.name);
        errdefer mod.deinit(ally);
        try out.append(ally, mod);
    }
    std.debug.assert(i < std.math.maxInt(u16));
    const slice = out.toOwnedSlice();
    return .{ slice.items(.data), slice.items(.meta) };
}
