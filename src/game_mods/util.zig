const std = @import("std");

/// reads a .json file
/// you must .deinit() the return value
/// sub_path must have all the platform specific guarantees of std.fs.openFile
/// ignores additional fields to allow other programs to store metadata (eg a package hash)
pub fn readJSONFile(comptime OutType: type, allocator: std.mem.Allocator, dir: std.fs.Dir, sub_path: []const u8) !std.json.Parsed(OutType) {
    // TODO: choose an actually reasonable max file size
    // TODO: is this the best way to parse from file or should we read first w/ allocate then parse?
    const meta_json = try dir.openFile(sub_path, .{ .mode = .read_only });
    defer meta_json.close();
    var json_reader = std.json.reader(allocator, meta_json.reader());
    defer json_reader.deinit();
    return std.json.parseFromTokenSource(std.json.Value, allocator, &json_reader, .{ .ignore_unknown_fields = true });
}
