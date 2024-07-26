const std = @import("std");
const mach = @import("mach");
const textures = @import("block_texture_registry.zig");
const config = @import("config");

pub const name = .block_registry;
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .update_gpu = .{ .handler = updateGPURegistry },
    .reset = .{ .handler = reset },
};
// TODO: benchmark this, is ECS over just using an ArrayList of the unsent blocks worth it?
pub const components = .{
    .is_block_type = .{ .type = void },
    .namespace = .{ .type = mach.EntityID },
    // FIXME: this only allows a max of maxInt(u16) possible blocks
    .gpu_i = .{ .type = u16 },
    .is_solid = .{ .type = void },
    // entity ID of a texture
    .uniform_faces = .{ .type = mach.EntityID },
    .faces = .{ .type = [6]mach.EntityID },
    .rotate_faces = .{ .type = void },
    .not_on_gpu = .{ .type = void },
};

pub const SolidBufferElem = extern struct {
    faces: [6]u16,
    comptime {
        std.debug.assert(@sizeOf(SolidBufferElem) == 6);
    }
};
comptime {
    const buffer: [2]SolidBufferElem = undefined;
    const offset1 = @intFromPtr(&buffer);
    const offset2 = @intFromPtr(&(buffer[1]));
    std.debug.assert(offset2 - offset1 == @sizeOf(SolidBufferElem));
}
/// for now will store uniform blocks with other blocks for ease, in future maybe improve the system?
solid_block_buf: *mach.gpu.Buffer,
free_buf_i: u16,
has_new_block: bool,

pub fn init(registry: *Mod) !void {
    const desc: mach.gpu.Buffer.Descriptor = .{
        .label = if (config.validate) "Block registry" else null,
        .size = @sizeOf(SolidBufferElem) * std.math.maxInt(u16),
        .usage = .{
            .storage = true,
            .copy_dst = true,
        },
    };
    registry.init(.{
        // TODO: allocate this buffer in first call to updateGPURegistry, with a buffer ~the number of initial blocks
        .solid_block_buf = mach.core.device.createBuffer(&desc),
        .free_buf_i = 0,
        .has_new_block = false,
    });
}

/// registers a block that is fully solid and all textures are the same
pub fn registerSolidUniformBlock(registry: *Mod, entities: *mach.Entities.Mod, namespace: mach.EntityID, texture: mach.EntityID, should_rotate: bool) !mach.EntityID {
    if (should_rotate) @panic("TODO: implement random block face rotations");
    const new_block = try entities.new();
    try registry.set(new_block, .is_block_type, {});
    try registry.set(new_block, .namespace, namespace);
    try registry.set(new_block, .is_solid, {});
    try registry.set(new_block, .uniform_faces, texture);
    try registry.set(new_block, .not_on_gpu, {});
    registry.state().has_new_block = true;
    return new_block;
}

pub fn updateGPURegistry(registry: *Mod, entities: *mach.Entities.Mod, texture_reg: *textures.Mod) !void {
    // TODO: allocate the block registry buffer here so we know how big the buffer HAS to be
    if (!registry.state().has_new_block) return;
    const queue = mach.core.queue;
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .not_on_gpu = Mod.read(.not_on_gpu),
        .is_solid = Mod.read(.is_solid),
    });
    while (q.next()) |c| {
        for (c.ids) |ent| {
            if (try registry.get(ent, .uniform_faces)) |tex_ent| {
                const i: u16 = registry.state().free_buf_i;
                queue.writeBuffer(registry.state().solid_block_buf, i * @sizeOf(SolidBufferElem), &[_]u16{try texture_reg.get(tex_ent, .atlas_i) orelse textureNotYetOnGPUError()} ** 6);
            } else @panic("TODO: implement");
            registry.state().free_buf_i += 1;
        }
    }
    registry.state().has_new_block = false;
}

fn textureNotYetOnGPUError() noreturn {
    @panic("TODO: implement proper error handling for this");
}

/// resets, no need to call init after this
pub fn reset(registry: *Mod, entities: *mach.Entities.Mod) !void {
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .is_block_type = Mod.read(.is_block_type),
    });
    while (q.next()) |c| {
        for (c.ids) |id| {
            entities.remove(id);
        }
    }
    registry.state().has_new_block = false;
    registry.state().free_tex_i = 0;
}
