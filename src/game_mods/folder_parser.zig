const std = @import("std");
const util = @import("./util.zig");

/// the format for what modmeta.json should hold
pub const metaJSONFormat_0 = struct {
    /// name of the mod (optional)
    name: []const u8 = "MyMod",
    /// some string to designate version (optional)
    modversion: []const u8 = "NoVersion",
    /// author of the mod (optional)
    author: []const u8 = "No author",
    /// description of the mod (optional)
    desc: []const u8 = "No description provided",
    /// base64 encoded hash of the contents of the dir (computed in hashModFolder)
    hash: []const u8,
    /// array of hashes of its dependents
    deps: []const []const u8 = &.{&.{}},
};

pub fn readModDir(allocator: std.mem.Allocator, dir: std.fs.Dir) !void {
    const mod_meta_json = try readModMetaJSON(allocator, dir);
    defer mod_meta_json.deinit();

    const hash_buf = try hashModFolderBase64(allocator, dir);
    if(!std.mem.eql(u8, &hash_buf, mod_meta_json.value.hash)) return error.WrongHash;
}

pub fn readModMetaJSON(allocator: std.mem.Allocator, dir: std.fs.Dir) !std.json.Parsed(metaJSONFormat_0) {
    var mod_meta_json = try util.readJSONFile(std.json.Value, allocator, dir, "./modmeta.json");
    defer mod_meta_json.deinit();

    return parseModMetaValue(allocator, &mod_meta_json.value);
}

fn parseModMetaValue(allocator: std.mem.Allocator, src: *std.json.Value) !std.json.Parsed(metaJSONFormat_0) {
    return if (src.object.fetchSwapRemove("ver")) |pair| switch (pair.value) {
        .integer => |val| if (val != 0) error.UnsupportedModVersion else std.json.parseFromValue(metaJSONFormat_0, allocator, src.*, .{ .ignore_unknown_fields = true }),
        else => error.InvalidModMetaJSON,
    } else error.InvalidModMetaJSON;
}

const base64_out_size = std.base64.url_safe_no_pad.Encoder.calcSize(@sizeOf(u64));
/// Puts the hash for use in hash field of modmeta.json into outbuffer
pub fn hashModFolderBase64(allocator: std.mem.Allocator, dir: std.fs.Dir) ![base64_out_size]u8 {
    //throw away because out_buffer is perfect size
    var hash_buf: [base64_out_size]u8 = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(hash_buf[0..], &@as([@sizeOf(u64)]u8, @bitCast(try hashModFolder(allocator, dir))));
    return hash_buf;
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
    var example_mod_dir = try std.fs.cwd().openDir("./src/testing/example_mod", .{.iterate = true});
    defer example_mod_dir.close();
    try readModDir(std.testing.allocator, example_mod_dir);
}