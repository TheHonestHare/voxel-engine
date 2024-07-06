const std = @import("std");
const util = @import("util.zig");
const Data = @import("folder_parser.zig").Data;

pub const ModDAG = struct {
    len: u16,
    hashes: [*]u64,
    /// deps has max size of tri_num(hashes.len-1)
    /// connection value of 2^16 - 2 means no connections
    connections: [*]u16,

    /// returns null if root node, else slice into connections that are nonempty
    pub fn getModDeps(self: ModDAG, i: u16) ?[]const u16 {
        if (i == 0) return null;
        const offset = tri_num(i);
        const next_offset = tri_num(i + 1);
        const empty_start = std.mem.indexOfScalar(u16, self.hashes[offset..next_offset], std.math.maxInt(u16)) orelse next_offset;
        return self.connections[offset..empty_start];
    }
    pub fn getHashIndex(self: @This(), hash: u64) ?u16 {
        return @intCast(std.mem.indexOfScalar(u64, self.hashes[0..self.len], hash));
    }
    // TODO: should runtime adding and removing mods be allowed?
    /// mods in earlier indexes will be applied first
    /// asserts a max of 2^16-1-1 mods but I don't think anything in this engine will reach that
    /// 2^16-1 in connections is reserved for empty element
    pub fn create(ally: std.mem.Allocator, scratch: std.mem.Allocator, mods: []const Data) !@This() {
        std.debug.assert(mods.len < std.math.maxInt(u16));
        if (mods.len == 0) return error.NoMods;
        var tmp: @This() = undefined;
        tmp.len = @intCast(mods.len);
        const hashes_buf = (try ally.alloc(u64, tmp.len));
        errdefer ally.free(hashes_buf);
        tmp.hashes = hashes_buf.ptr;
        // TODO: we don't need the absolute worst case amount of connections allocated thats stupid
        const connection_buf = (try ally.alloc(u16, tri_num(tmp.len)));
        tmp.connections = connection_buf.ptr;
        errdefer ally.free(connection_buf);

        var unused = try std.ArrayListUnmanaged(u16).initCapacity(scratch, tmp.len);
        defer unused.deinit(scratch);
        for (unused.addManyAtAssumeCapacity(0, tmp.len), 0..) |*dst, i| dst.* = @intCast(i);
        const hash_dep_buff = try scratch.alloc(u16, tmp.len - 1);
        defer scratch.free(hash_dep_buff);

        var hash_to_i: std.AutoHashMapUnmanaged(u64, u16) = .{};
        try hash_to_i.ensureTotalCapacity(scratch, tmp.len);
        defer hash_to_i.deinit(scratch);

        var hash_i: u16 = 0;
        // writes all nodes with no deps, erroring if none
        {
            var i: u16 = 0;
            while (i < unused.items.len) {
                if (mods[unused.items[i]].deps) |_| {
                    i += 1;
                    continue;
                }
                tmp.hashes[hash_i] = mods[unused.items[i]].hash;
                if (hash_to_i.getOrPutAssumeCapacity(tmp.hashes[hash_i]).found_existing) return error.DuplicateEntry;
                if (hash_i != 0) @memset(tmp.connections[tri_num(hash_i)..tri_num(hash_i + 1)], std.math.maxInt(u16));
                _ = unused.swapRemove(i);
                hash_i += 1;
            } else if (hash_i == 0) return error.NoRootNode;
        }
        // similar process but now checks for dependencies, mods[x].deps gauranteed not null now
        var prev_unused_len: u16 = @intCast(unused.items.len + 1);
        loop: while (unused.items.len < prev_unused_len) {
            if (unused.items.len == 0) break :loop; // this isn't in condition so else branch isn't executed when breaking
            prev_unused_len = @intCast(unused.items.len);
            var i: u16 = 0;
            iter: while (i < unused.items.len) {
                const curr_mod = &mods[unused.items[i]];
                if (curr_mod.deps.?.len > hash_i) {
                    i += 1;
                    continue :iter;
                }

                for (curr_mod.deps.?, 0..) |hash, j| {
                    hash_dep_buff[j] = hash_to_i.get(hash) orelse {
                        i += 1;
                        continue :iter;
                    };
                }
                @memcpy(tmp.connections[tri_num(hash_i)..], hash_dep_buff[0..curr_mod.deps.?.len]);
                @memset(tmp.connections[curr_mod.deps.?.len..tri_num(hash_i + 1)], std.math.maxInt(u16));

                tmp.hashes[hash_i] = curr_mod.hash;
                if (hash_to_i.getOrPutAssumeCapacity(tmp.hashes[hash_i]).found_existing) return error.DuplicateEntry;
                _ = unused.swapRemove(i);
                hash_i += 1;
            }
        } else { // we already know we're in a failing case just determine if circular dep or invalid hash
            // put all items into the hashmap so we know all the valid hashes
            for (unused.items) |i| if (hash_to_i.getOrPutAssumeCapacity(mods[i].hash).found_existing) return error.DuplicateEntry;

            for (unused.items) |i|
                for (mods[i].deps.?) |dep_hash|
                    if (!hash_to_i.contains(dep_hash)) return error.InvalidDepHash;
            return error.CircularDependency;
        }
        return tmp;
    }
};

/// returns the nth triangular number (n=1 -> 0), with no regard for big numbers :)
/// don't plug in 0,
/// 1 2 3 4  5  6  7
/// 0 1 3 6 10 15 21
fn tri_num(n: u16) u32 {
    return (n - 1) * n / 2;
}

test "error.CircularDependency" {
    const data = [_]Data{
        Data{ .hash = 1010, .deps = null, .dirname = "" },
        Data{ .hash = 82911919, .deps = &.{4893849834}, .dirname = "" },
        Data{ .hash = 8, .deps = &.{ 1010, 82911919 }, .dirname = "" },
        Data{ .hash = 4893849834, .deps = &.{ 1010, 8 }, .dirname = "" },
    };
    const ally = std.testing.allocator;
    try std.testing.expectError(error.CircularDependency, ModDAG.create(ally, ally, &data));
}

test "error.NoMods" {
    const data: [0]Data = .{};
    const ally = std.testing.allocator;
    try std.testing.expectError(error.NoMods, ModDAG.create(ally, ally, &data));
}

test "error.NoRootNode" {
    //this error should be caught by circular dependencies, but I feel this is a useful subcase
    const data = [_]Data{
        Data{ .hash = 439787834, .deps = &.{ 981029111, 1111 }, .dirname = "" },
        Data{ .hash = 981029111, .deps = &.{1111}, .dirname = "" },
        Data{ .hash = 1111, .deps = &.{111122223}, .dirname = "" },
        Data{ .hash = 388949854, .deps = &.{111122223}, .dirname = "" },
        Data{ .hash = 111122223, .deps = &.{1111}, .dirname = "" },
        Data{ .hash = 769201948, .deps = &.{388949854}, .dirname = "" },
    };
    const ally = std.testing.allocator;
    try std.testing.expectError(error.NoRootNode, ModDAG.create(ally, ally, &data));
}

test "error.DuplicateEntry" {
    const data = [_]Data{
        Data{ .hash = 439787834, .deps = &.{ 981029111, 1111 }, .dirname = "" },
        Data{ .hash = 981029111, .deps = &.{1111}, .dirname = "" },
        Data{ .hash = 1111, .deps = &.{111122223}, .dirname = "" },
        Data{ .hash = 388949854, .deps = &.{111122223}, .dirname = "" },
        Data{ .hash = 111122223, .deps = null, .dirname = "" },
        Data{ .hash = 769201948, .deps = &.{388949854}, .dirname = "" },
        Data{ .hash = 769201948, .deps = &.{388949854}, .dirname = "" },
    };
    const ally = std.testing.allocator;
    try std.testing.expectError(error.DuplicateEntry, ModDAG.create(ally, ally, &data));
}
