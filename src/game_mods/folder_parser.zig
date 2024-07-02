const std = @import("std");
const util = @import("./util.zig");

pub const MetaData = struct {
    /// name of the mod (taken from directory name)
    name: []const u8,
    /// some string to designate version (optional)
    modversion: []const u8,
    /// author of the mod (optional)
    author: []const u8,
    /// description of the mod (optional)
    desc: []const u8,
    /// base64 encoded hash of the contents of the dir (computed in hashModFolder)
    hash: u64,
    /// array of hashes of its dependents
    deps: ?[]const u64,

    /// Remember to call deinit
    pub fn init(allocator: std.mem.Allocator, modmeta: MetaJSONFormat_0, mod: []const u8) !@This() {
        return ret: {
            var tmp: @This() = undefined;
            tmp.name = try allocator.dupe(u8, mod);
            errdefer allocator.free(tmp.name);
            tmp.modversion = try allocator.dupe(u8, modmeta.modversion orelse "No version");
            errdefer allocator.free(tmp.modversion);
            tmp.author = try allocator.dupe(u8, modmeta.author orelse "No author");
            errdefer allocator.free(tmp.author);
            tmp.desc = try allocator.dupe(u8, modmeta.desc orelse "No description");
            errdefer allocator.free(tmp.desc);
            tmp.hash = try util.decodeBase64ToU64(modmeta.hash);

            tmp.deps = if(modmeta.deps) |val| blk: {
                const tmp1 = try allocator.alloc(u64, val.len);
                errdefer allocator.free(tmp1);

                for(tmp1, val) |*dst, src| dst.* = try util.decodeBase64ToU64(src);
                break :blk tmp1;
            } else null;
            break :ret tmp;
        };
    }

    pub fn deinit(self: MetaData, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.modversion);
        allocator.free(self.author);
        allocator.free(self.desc);
        allocator.free(self.deps orelse return);
    }
};

/// the format for what modmeta.json should hold
pub const MetaJSONFormat_0 = struct {
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

pub fn readModDir(allocator: std.mem.Allocator, all_mods_dir: std.fs.Dir, mod: []const u8 ) !MetaData {
    var mod_dir = try all_mods_dir.openDir(mod, .{ .iterate = true });
    defer mod_dir.close();
    const mod_meta_json = try readModMetaJSON(allocator, mod_dir);
    defer mod_meta_json.deinit();

    if(!isCorrectHash(allocator, mod_dir, mod_meta_json.value.hash)) return error.WrongHash;

    return MetaData.init(allocator, mod_meta_json.value, mod);
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

pub const skip_hash_files = .{"modmeta.json", "thumb.bmp"};
/// Computes the hash of a directory, ignoring files in skip_hash_files
/// Doesn't check for file names / other metadata, only the contents
pub fn hashModFolder(allocator: std.mem.Allocator, dir: std.fs.Dir) !u64 {
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var curr_hash: u64 = 0;
    blk: while(try walker.next()) |entry| {
        inline for(skip_hash_files) |path| {
            if (std.mem.eql(u8, entry.path, path)) continue :blk;
        }
        const contents = try dir.readFileAlloc(allocator, entry.path, std.math.maxInt(usize));
        defer allocator.free(contents);
        curr_hash ^= std.hash.CityHash64.hash(contents);
    }
    return curr_hash;
}

// run with zig test ./src/game_mods/folder_parser.zig with cwd as the top dir
// TODO: integrate with zig build test or smth
test readModDir {
    // TODO: maybe generate the test folder dynamically / this seems ugly / don't rely on cwd
    var example_mod_dir = try std.fs.cwd().openDir("./src/testing/example_all_mods", .{});
    defer example_mod_dir.close();
    const out = try readModDir(std.testing.allocator, example_mod_dir, "example_mod");
    defer out.deinit(std.testing.allocator);
    const expected: MetaData = .{
        .name = "example_mod",
        .modversion = "No version",
        .author = "No author",
        .desc = "No description",
        .hash = 679187453357837628,
        .deps = null,
    };
    try std.testing.expectEqualDeep(out, expected);
}