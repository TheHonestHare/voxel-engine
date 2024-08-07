const std = @import("std");
const util = @import("./util.zig");

/// multiple nulls shouldn't be issue since null pointer optimization
pub const MetaData = struct {
    /// name given to mod
    modname: ?[]const u8,
    /// some string to designate version (optional)
    modversion: ?[]const u8,
    /// author of the mod (optional)
    author: ?[]const u8,
    /// description of the mod (optional)
    desc: ?[]const u8,

    /// copies each string into the base allocator
    pub fn init(allocator: std.mem.Allocator, modname: ?[]const u8, modversion: ?[]const u8, author: ?[]const u8, desc: ?[]const u8) !@This() {
        var tmp: @This() = undefined;

        tmp.modname = if (modname) |val| try allocator.dupe(u8, val) else null;
        errdefer if (tmp.modname) |val| allocator.free(val);

        tmp.modversion = if (modversion) |val| try allocator.dupe(u8, val) else null;
        errdefer if (tmp.modversion) |val| allocator.free(val);

        tmp.author = if (author) |val| try allocator.dupe(u8, val) else null;
        errdefer if (tmp.author) |val| allocator.free(val);

        tmp.desc = if (desc) |val| try allocator.dupe(u8, val) else null;
        errdefer if (tmp.desc) |val| allocator.free(val);

        return tmp;
    }
    // TODO: should this REALLY be using comptime like this to be lazy?
    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        inline for (@typeInfo(@This()).Struct.fields) |field| if (@field(self, field.name)) |val| allocator.free(val);
    }
};

pub const Data = struct {
    /// name of the base directory for the mod
    dirname: []const u8,
    /// base64 encoded hash of the contents of the dir (computed in hashModFolder)
    hash: u64,
    /// array of hashes of its dependents. length of 0 isn't allowed, and init() converts 0 length slices to null
    deps: ?[]const u64,

    /// all arguments are duplicated so that return is owned by caller
    pub fn init(allocator: std.mem.Allocator, dirname: []const u8, hash: util.HashBase64, deps: ?[]const util.HashBase64) !@This() {
        var tmp: @This() = undefined;

        tmp.dirname = try allocator.dupe(u8, dirname);
        errdefer allocator.free(tmp.dirname);

        tmp.hash = try util.decodeBase64ToU64(hash);

        tmp.deps = if (deps) |val| blk: {
            if (val.len == 0) break :blk null;
            const tmp1 = try allocator.alloc(u64, val.len);
            errdefer allocator.free(tmp1);

            for (tmp1, val) |*dst, src| dst.* = try util.decodeBase64ToU64(src);
            break :blk tmp1;
        } else null;

        return tmp;
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.dirname);
        allocator.free(self.deps orelse return);
    }
};
// TODO: fuzz test implementation for errors and leaks
// TODO: make the fields inline for use with MultiArrayList, don't create mods all at once. integrate with zig-aio
pub const Mod = struct {
    // TODO: should these really be const??
    data: Data,
    meta: MetaData,

    /// Remember to call deinit
    pub fn init(allocator: std.mem.Allocator, modmeta: MetaJSONFormat_0, mod: []const u8) !@This() {
        var tmp: @This() = undefined;
        tmp.data = try Data.init(allocator, mod, modmeta.hash, modmeta.deps);
        errdefer tmp.data.deinit(allocator);

        tmp.meta = try MetaData.init(allocator, modmeta.name, modmeta.modversion, modmeta.author, modmeta.desc);
        errdefer tmp.meta.deinit(allocator);
        return tmp;
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.meta.deinit(allocator);
    }
};

/// the format for what modmeta.json should hold
pub const MetaJSONFormat_0 = struct {
    /// name given to mod (any string)
    name: ?[]const u8 = null,
    /// some string to designate version (optional)
    modversion: ?[]const u8 = null,
    /// author of the mod (optional)
    author: ?[]const u8 = null,
    /// description of the mod (optional)
    desc: ?[]const u8 = null,
    /// base64 encoded hash of the contents of the dir (computed in hashModFolder)
    hash: util.HashBase64,
    /// array of hashes of its dependents
    deps: ?[]const util.HashBase64 = null,
};

pub fn readModDir(allocator: std.mem.Allocator, all_mods_dir: std.fs.Dir, mod: []const u8) !Mod {
    var mod_dir = try all_mods_dir.openDir(mod, .{ .iterate = true });
    defer mod_dir.close();
    const mod_meta_json = try readModMetaJSON(allocator, mod_dir);
    defer mod_meta_json.deinit();

    if (!isCorrectHash(allocator, mod_dir, mod_meta_json.value.hash)) return error.WrongHash;

    return Mod.init(allocator, mod_meta_json.value, mod);
    //we don't have to check hash lengths because std.json does that while trying to fit the array into util.HashBase64
}

pub fn isCorrectHash(allocator: std.mem.Allocator, dir: std.fs.Dir, str: util.HashBase64) bool {
    const hash_buf = util.encodeU64ToBase64(hashModFolder(allocator, dir) catch return false);
    return std.mem.eql(u8, &hash_buf, &str);
}

pub fn readModMetaJSON(allocator: std.mem.Allocator, dir: std.fs.Dir) !std.json.Parsed(MetaJSONFormat_0) {
    var mod_meta_json = try util.readJSONFile(std.json.Value, allocator, dir, "./modmeta.json");
    defer mod_meta_json.deinit();

    return parseModMetaValue(allocator, &mod_meta_json.value);
}

fn parseModMetaValue(allocator: std.mem.Allocator, src: *std.json.Value) !std.json.Parsed(MetaJSONFormat_0) {
    return if (src.object.fetchSwapRemove("ver")) |pair| switch (pair.value) {
        .integer => |val| if (val != 0) error.UnsupportedModVersion else std.json.parseFromValue(MetaJSONFormat_0, allocator, src.*, .{ .ignore_unknown_fields = true }),
        else => error.InvalidModMetaJSON,
    } else error.InvalidModMetaJSON;
}

pub const skip_hash_files = .{ "modmeta.json", "thumb.bmp" };
// TODO: only hash "main.wasm" so stuff like shader hot reloading can work (maybe make full hash optional?)
/// Computes the hash of a directory, ignoring files in skip_hash_files
/// Doesn't check for file names / other metadata, only the contents
/// Will not return 0 as a value, so collections can use 0 as an empty element
pub fn hashModFolder(allocator: std.mem.Allocator, dir: std.fs.Dir) !u64 {
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var curr_hash: u64 = 0;
    blk: while (try walker.next()) |entry| {
        inline for (skip_hash_files) |path| {
            if (std.mem.eql(u8, entry.path, path)) continue :blk;
        }
        const contents = try dir.readFileAlloc(allocator, entry.path, std.math.maxInt(usize));
        defer allocator.free(contents);
        curr_hash ^= std.hash.CityHash64.hash(contents);
    }
    // reserve 0 as special value (if this actually causes a problem I will blame it on Russia)
    return if (curr_hash == 0) 1 else curr_hash;
}

// run with zig test ./src/game_mods/folder_parser.zig with cwd as the top dir
// TODO: integrate with zig build test or smth
test readModDir {
    var example_mod_dir = try std.fs.cwd().openDir("example_save_dir/all_available_mods", .{});
    defer example_mod_dir.close();
    const out = try readModDir(std.testing.allocator, example_mod_dir, "example_mod");
    defer out.deinit(std.testing.allocator);
    const expected: Mod = .{
        .data = .{
            .dirname = "example_mod",
            .hash = 679187453357837628,
            .deps = null,
        },
        .meta = .{
            .modname = null,
            .modversion = null,
            .author = null,
            .desc = null,
        },
    };
    try std.testing.expectEqualDeep(expected, out);
}
