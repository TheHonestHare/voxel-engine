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
// TODO: determine if using a slice is more efficient than storing in place in MetaJSONFormat_0
pub const HashBase64 = [base64_of_u64_size]u8;
pub fn encodeU64ToBase64(n: u64) HashBase64 {
    var hash_buf: HashBase64 = undefined;
    // just assume everythings little endian bc mach doesn't even work on big I think
    _ = std.base64.url_safe_no_pad.Encoder.encode(hash_buf[0..], &@as([@sizeOf(u64)]u8, @bitCast(n)));
    return hash_buf;
}

/// the last 2 bits of str must be 0, as these are padding it to 66 bits (base64 == 6 bits per byte)
pub fn decodeBase64ToU64(str: HashBase64) !u64 {
    comptime std.debug.assert(std.base64.url_safe_no_pad.Decoder.calcSizeUpperBound(str.len) catch unreachable == @sizeOf(u64));
    var out: u64 = undefined;
    // just assume everythings little endian bc mach doesn't even work on big I think
    try std.base64.url_safe_no_pad.Decoder.decode(std.mem.sliceAsBytes((&out)[0..1]), &str);
    return out;
}

/// returns if the base64 hash provided will actually fit into a u64
/// TODO: make sure I'm not just lying about that
pub fn isValidBase64Hash(str: []const u8) bool {
    if (str.len != base64_of_u64_size) return false;
    return str[base64_of_u64_size - 1] & 0x03 == 0;
}

test "base64 test" {
    const x = 2389438;
    const there_and_back = try decodeBase64ToU64(encodeU64ToBase64(x));
    try std.testing.expectEqual(x, there_and_back);
}

test decodeBase64ToU64 {
    try std.testing.expect(!isValidBase64Hash("")); // wrong length so won't even compile when inputted
    try std.testing.expect(!isValidBase64Hash("99999999999")); // last 2 bits are 01
    try std.testing.expect(isValidBase64Hash("99999999998")); // last 2 bits are 00

    try std.testing.expectError(error.InvalidPadding, decodeBase64ToU64("99999999999".*));
    try std.testing.expectEqual(std.mem.bigToNative(u64, 0b11110111_11011111_01111101_11110111_11011111_01111101_11110111_11011111), decodeBase64ToU64("99999999998".*));
}
