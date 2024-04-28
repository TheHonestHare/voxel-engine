const std = @import("std");
const mach = @import("mach");
const Camera = @import("./camera.zig");
const core = mach.core;
const math = mach.math;

const log = std.log.scoped(.camera_controller);

pub fn init() void {
    core.setCursorMode(.disabled);
    return;
}

pub const Movement = struct {
    fowards: bool = false,
    back: bool = false,
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
};

velocity: f32 = 5,
position: math.Vec3 = math.vec3(0, 0, 5),
pitch: f32 = 0.0,
yaw: f32 = 0.0,

// TODO: optimize this code
pub fn move(self: *@This(), movement: Movement, mouse_delta: core.Position, camera: *Camera) void {
    const res = core.size();
    if (res.height == 0 or res.width == 0) return;

    const res_x: f32 = @floatFromInt(res.width);
    const res_y: f32 = @floatFromInt(res.height);
    self.yaw = self.yaw - @as(f32, @floatCast(mouse_delta.x)) / res_x;
    // we flip mouse position to be relative to bottom left
    self.pitch = math.clamp(self.pitch - @as(f32, @floatCast(mouse_delta.y)) / res_y, -math.pi / 2.0, math.pi / 2.0);

    const par: f32 = (@as(f32, @floatFromInt(@intFromBool(movement.fowards))) - @as(f32, @floatFromInt(@intFromBool(movement.back)))) * self.velocity * core.delta_time;
    const per: f32 = (@as(f32, @floatFromInt(@intFromBool(movement.right))) - @as(f32, @floatFromInt(@intFromBool(movement.left)))) * self.velocity * core.delta_time;
    const ver: f32 = (@as(f32, @floatFromInt(@intFromBool(movement.up))) - @as(f32, @floatFromInt(@intFromBool(movement.down)))) * self.velocity * core.delta_time;

    const par_z_comp = -par * @cos(self.yaw);
    const par_x_comp = -par * @sin(self.yaw);
    const per_z_comp = -per * @cos(self.yaw - math.pi / 2.0);
    const per_x_comp = -per * @sin(self.yaw - math.pi / 2.0);

    const pos_delta = math.vec3(par_x_comp + per_x_comp, ver, par_z_comp + per_z_comp);
    self.position = self.position.add(&pos_delta);

    camera.lookat(self.position, self.pitch, self.yaw, 0.0);
}
