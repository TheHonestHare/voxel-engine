const std = @import("std");
const zware = @import("zware");
const fp = @import("mod_folder_parser.zig");
const DAG = @import("dep_graph.zig").ModDAG;
// TODO: maybe use asychronous io for files etc instead of native std.fs
/// all returned values are allocated with ally, scratch is temporary memory that gets freed
pub fn parseAllModsDir(ally: std.mem.Allocator, scratch: std.mem.Allocator, all_mods_dir: std.fs.Dir) !struct { []fp.Mod, DAG } {
    const mod_slice = try getAllMods(ally, all_mods_dir);
    errdefer for(mod_slice) |mod| mod.deinit(ally); 
    const order_to_load = try DAG.create(ally, scratch, mod_slice);
    return .{ mod_slice, order_to_load };

}
/// dir must be opened with iterating capability
pub fn getAllMods(ally: std.mem.Allocator, all_mods_dir: std.fs.Dir) ![]fp.Mod {
    var iter = all_mods_dir.iterate();
    var out: std.ArrayListUnmanaged(fp.Mod) = .{};
    errdefer out.deinit(ally);
    // max of 2^16 - 2 mods
    var i: u16 = 0;
    errdefer for (out.items[0..i]) |mod| mod.deinit(ally);
    while (try iter.next()) |val| : (i += 1) {
        // TODO: theres probably a better way to do this
        if (val.kind != .directory) continue;
        const mod = try fp.readModDir(ally, all_mods_dir, val.name);
        errdefer mod.deinit(ally);
        try out.append(ally, mod);
    }
    std.debug.assert(i < std.math.maxInt(u16));
    return out.toOwnedSlice(ally);
}
