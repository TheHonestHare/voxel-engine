const std = @import("std");
const mach = @import("mach");
const config = @import("config");

pub const name = .texture_registry;
pub const Mod = mach.Mod(@This());

pub const AtlasIndex = u16;

pub const RGBA8_Unorm = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const TextureData = [8][8]RGBA8_Unorm;

pub const systems = .{
    .init = .{ .hander = init },
    .update_gpu = .{ .handler = updateGPUTextureAtlas },
    .reset = .{ .handler = reset },
};

// TODO: namespace should be in its own module
pub const components = .{ .is_block_type = .{ .type = void }, .namespace = .{ .type = mach.EntityID }, .atlas_i = .{ .type = AtlasIndex }, .not_on_gpu = .{ .type = void }, .texture_data = .{ .type = *TextureData } };

const atlas_tex_width = 2048;
const tex_width = 8;
// TODO: don't default to the literal max texture size
const atlas_tex_height = 2048;
const tex_height = 8;

texture_atlas: *mach.gpu.Texture,
free_tex_i: AtlasIndex,
has_new_tex: bool,

pub fn init(registry: *Mod) !void {
    // TODO: add mips, don't default to the literal max texture size thats dumb
    const desc: mach.gpu.Texture.Descriptor = .{
        .dimension = .dimension_2d,
        .format = .rgba8_unorm,
        .label = if (config.validate) "Texture atlas" else null,
        .usage = .{
            .copy_dst = true,
        },
        .size = .{ .height = atlas_tex_height, .width = atlas_tex_width },
    };
    // asserts that a u16 can uniquely identify an element in the texture atlas
    comptime std.debug.assert(desc.size.width * desc.size.height / 8 / 8 == std.math.maxInt(AtlasIndex) + 1);
    registry.init(.{
        .texture_atlas = mach.core.device.createTexture(&desc),
        .free_tex_i = 0,
        .has_new_tex = false,
    });
}

// TODO: should this dupe TextureData instead of requiring certain allocators to be used
/// must be allocated with allys.TickAllocator, do not use RFrameAllocator
pub fn registerBlockFaceTexture(registry: *Mod, entities: *mach.Entities.Mod, data: *TextureData, namespace: mach.EntityID) mach.EntityID {
    const tex_ent = try entities.new();
    try registry.set(tex_ent, .is_block_tex, {});
    try registry.set(tex_ent, .not_on_gpu, {});
    try registry.set(tex_ent, .texture_data, data);
    try registry.set(tex_ent, .namespace, namespace);
    registry.state().has_new_tex = true;
    return tex_ent;
}

pub fn updateGPUTextureAtlas(registry: *Mod, entities: *mach.Entities.Mod) !void {
    if (!registry.state().has_new_tex) return;
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .not_on_gpu = Mod.read(.not_on_gpu),
        .texture_data = Mod.read(.texture_data),
    });
    while (q.next()) |c| {
        for (c.ids, c.texture_data) |ent, texture| {
            const tex_i: AtlasIndex = registry.state().free_tex_i;
            const dest: mach.gpu.ImageCopyTexture = .{
                .mip_level = 0, // TODO: mips
                .origin = .{
                    .x = tex_i * tex_width % atlas_tex_width,
                    .y = tex_i * tex_width / atlas_tex_width * tex_height,
                },
                .texture = registry.state().texture_atlas,
            };
            const data_layout: mach.gpu.Texture.DataLayout = comptime .{
                .offset = 0,
                .bytes_per_row = tex_width * @sizeOf(RGBA8_Unorm),
                .rows_per_image = tex_height,
            };
            const write_size: mach.gpu.Extent3D = comptime .{
                .width = tex_width,
                .height = tex_height,
            };
            mach.core.queue.writeTexture(&dest, &data_layout, &write_size, texture);
            try registry.set(ent, .atlas_i, tex_i);
            try registry.remove(ent, .not_on_gpu);
            try registry.remove(ent, .texture_data); // all data will be freed at end of game tick
            registry.state().free_tex_i += 1;
        }
    }
    registry.state().has_new_tex = false;
}
/// resets, no need to call init after this
pub fn reset(registry: *Mod, entities: *mach.Entities.Mod) !void {
    var q = try entities.query(.{
        .ids = mach.Entities.Mod.read(.id),
        .is_block_tex = Mod.read(.is_block_tex),
    });
    while (q.next()) |c| {
        for (c.ids) |id| {
            entities.remove(id);
        }
    }
    registry.state().has_new_tex = false;
    registry.state().free_tex_i = 0;
}
