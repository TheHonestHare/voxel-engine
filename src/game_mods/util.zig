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

pub const base64_of_u64_size = std.base64.url_safe_no_pad.Encoder.calcSize(@sizeOf(u64));
pub fn encodeU64ToBase64(n: u64) [base64_of_u64_size]u8 {
    var hash_buf: [base64_of_u64_size]u8 = undefined;
    // just assume everythings little endian bc mach doesn't even work on big I think
    _ = std.base64.url_safe_no_pad.Encoder.encode(hash_buf[0..], &@as([@sizeOf(u64)]u8, @bitCast(n)));
    return hash_buf;
}

pub fn decodeBase64ToU64(str: [base64_of_u64_size]u8) !u64 {
    comptime std.debug.assert(std.base64.url_safe_no_pad.Decoder.calcSizeUpperBound(str.len) catch unreachable == @sizeOf(u64));
    var out: u64 = undefined;
    // just assume everythings little endian bc mach doesn't even work on big I think
    try std.base64.url_safe_no_pad.Decoder.decode(std.mem.sliceAsBytes((&out)[0..1]), &str);
    return out;
}

test "base64 test" {
    const x = 2389438;
    const there_and_back = try decodeBase64ToU64(encodeU64ToBase64(x));
    try std.testing.expectEqual(x, there_and_back);
}