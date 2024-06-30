const std = @import("std");
const mach = @import("mach");
const config = @import("config");
const groups = @import("./bindgroups.zig");

const core = mach.core;
const gpu = mach.gpu;
const math = mach.math;

/// THIS WILL LIKELY BREAK EVERYTHING IF NOT 4
pub const brickmap_size = 8;

const size_x = 512 / brickmap_size;
const size_z = 512 / brickmap_size;
const size_y = 128 / brickmap_size;
pub const HeaderLayout = extern struct {
    size_x: u32,
    size_y: u32,
    size_z: u32,
    _pad: u32 = undefined,
};
/// The layout of the bitmasks used to determine if block is air or not
/// Each bitmap can be treated as 1 giant 8*8*8 = 512 bit integer in little endian
/// The LSB (bitsmask & 1 << 0) is the smallest in x, y, and z
/// First 8 bits are when z = 0, x = 0-7, y = 0
/// Second 8 bits are when z = 1, x = 0-7, y = 0 etc
/// Because WGSL only supports u32, we use that
pub const BitMapLayout = extern struct {
    bitmasks: [size_x * size_y * size_z][brickmap_size * brickmap_size * brickmap_size / 32]u32,
};
header_buff: *gpu.Buffer,
bitmask_buff: *gpu.Buffer,
bindgroup: *gpu.BindGroup,
bindgroup_layout: *gpu.BindGroupLayout,

// TODO: add validation
pub fn init(self: *@This()) void {
    var header_buff = core.device.createBuffer(&.{
        .usage = .{
            .uniform = true,
        },
        .size = @sizeOf(HeaderLayout),
        .mapped_at_creation = .true,
    });
    // TODO: handle null properly
    const data_buff = &header_buff.getMappedRange(HeaderLayout, 0, 1).?[0];
    data_buff.* = .{ .size_x = size_x, .size_y = size_y, .size_z = size_z };
    header_buff.unmap();

    const bitmask_buff = core.device.createBuffer(&.{
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .size = @sizeOf(BitMapLayout),
        .mapped_at_creation = .true,
    });
    const bit_buff = &bitmask_buff.getMappedRange(BitMapLayout, 0, 1).?[0];
    // @memset(&bit_buff.bitmasks, .{0x10001000, 0x10001000});
    bit_buff.bitmasks[0][0] = 0x00FE0018;
    bit_buff.bitmasks[0][3] = 0x34007C01;
    //@memset(bit_buff.bitmasks[0][1..], 0x00000010);
    @memset(bit_buff.bitmasks[1..], bit_buff.bitmasks[0]);
    bitmask_buff.unmap();

    const bindgroup_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{ .entries = &.{
        gpu.BindGroupLayout.Entry.buffer(
            groups.group_2.header.binding,
            .{ .compute = true },
            .uniform,
            false,
            @sizeOf(groups.group_2.header.layout),
        ),
        gpu.BindGroupLayout.Entry.buffer(
            groups.group_2.bitmaps.binding,
            .{ .compute = true },
            .read_only_storage,
            false,
            @sizeOf(groups.group_2.bitmaps.layout),
        ),
    } }));

    const bindgroup = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = bindgroup_layout, .entries = &.{ 
    gpu.BindGroup.Entry.buffer(
        groups.group_2.header.binding,
        header_buff,
        0,
        @sizeOf(HeaderLayout),
    ), gpu.BindGroup.Entry.buffer(
        groups.group_2.bitmaps.binding,
        bitmask_buff,
        0,
        @sizeOf(BitMapLayout),
    ) } }));

    self.* = .{ .header_buff = header_buff, .bitmask_buff = bitmask_buff, .bindgroup_layout = bindgroup_layout, .bindgroup = bindgroup };
}

pub fn deinit(self: *@This()) void {
    self.header_buff.destroy();
    self.bitmask_buff.destroy();
    self.bindgroup.release();
    self.bindgroup_layout.release();
    self.* = undefined;
}
