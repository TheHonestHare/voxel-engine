const mach = @import("mach");
const _camera = @import("./camera.zig");
const _world = @import("./gpu_world.zig");

// TODO: initing bindgroups should all occur here
// TODO: don't destroy bindgroup layouts they seem important maybe
// TODO: a layout field makes absolutely 0 sense, should be a function that returns the type instead
// TODO: make a runtime interface so users can create their own bindgroups
pub const Group = struct { binding: u32, layout: type };
/// camera group
pub const group_0 = struct {
    pub const camera: Group = .{ .binding = 0, .layout = _camera.BindGroup };
};
/// screen group
pub const group_1 = struct {
    pub const screen: Group = .{ .binding = 0, .layout = mach.core.gpu.Texture };
};

pub const group_2 = struct {
    pub const header: Group = .{ .binding = 0, .layout = _world.HeaderLayout };
    pub const bitmaps: Group = .{ .binding = 1, .layout = _world.BitMapLayout };
};
