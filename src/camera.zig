const std = @import("std");
const mach = @import("mach");
const config = @import("config");
const gpu = mach.gpu;
const math = mach.math;
const core = mach.core;
const This = @This();
const log = std.log.scoped(.camera);

// TODO: defaulting to undefined is bad, use an init function
// TODO: get rid of descriptor variable or find better way of validating
buff: *gpu.Buffer = undefined,
bindgroup: *gpu.BindGroup = undefined,
/// distance from screen, use set_fov change this
screen_dist: f32 = 0.7,

uniform: extern struct {
    position: math.Vec3, // camera position
    //_pad: u32,
    plane_X: math.Vec3, // vec from screen origin to right w.r.t orientation, normalized
    //_pad1: u32,
    plane_Y: math.Vec3, // vec from screen origin to top of screen w.r.t. orientation, normalized
    //_pad2: u32,
    lookat: math.Vec3, // vector from eye to screen origin, scaled by screen_dist
    //_pad3: u32,
} = undefined,

pub fn init_bindgroup(self: *This) *gpu.BindGroupLayout {
    self.buff = blk: {
        const descriptor: gpu.Buffer.Descriptor = .{
            .usage = .{
                .copy_dst = true,
                .uniform = true,
            },
            .label = if (config.validate) "camera buffer" else null,
            .size = @sizeOf(@TypeOf(self.uniform)),
        };
        // TODO add validation
        break :blk core.device.createBuffer(&descriptor);
    };

    const camera_bindgroup_layout = blk: {
        const descriptor = gpu.BindGroupLayout.Descriptor.init(.{
            .entries = &.{gpu.BindGroupLayout.Entry.buffer(
                0,
                .{ .compute = true },
                .uniform,
                false,
                @sizeOf(@TypeOf(self.uniform)),
            )},
        });
        // TODO add validation
        break :blk core.device.createBindGroupLayout(&descriptor);
    };

    self.bindgroup = blk: {
        const descriptor = gpu.BindGroup.Descriptor.init(.{
            .entries = &[_]gpu.BindGroup.Entry{gpu.BindGroup.Entry.buffer(
                0, 
                self.buff, 
                0, 
                @sizeOf(@TypeOf(self.uniform))
            )},
            .layout = camera_bindgroup_layout,
        });
        // TODO add validation
        break :blk core.device.createBindGroup(&descriptor);
    };

    return camera_bindgroup_layout;
}
/// initial orientation is pointing in -z axis
/// +yaw rotates camera counterclockwise
/// +pitch rotates camera upwards
pub fn lookat(self: *This, position: math.Vec3, pitch: f32, yaw: f32, roll: f32) void {
    // TODO: Optimize this function
    self.uniform.position = position;

    const look_initial = math.vec4(0, 0, -1, 1);
    const x_initial = math.vec4(1, 0, 0, 1);
    const y_initial = math.vec4(0, 1, 0, 1);

    const roll_mat = math.Mat4x4.rotateZ(roll);
    const x_rolled = roll_mat.mulVec(&x_initial);
    const y_rolled = roll_mat.mulVec(&y_initial);

    const pitch_mat = math.Mat4x4.rotateX(pitch);
    const look_pitched = pitch_mat.mulVec(&look_initial);
    const x_pitched = pitch_mat.mulVec(&x_rolled);
    const y_pitched = pitch_mat.mulVec(&y_rolled);

    const yaw_mat = math.Mat4x4.rotateY(yaw);
    const look_yawed = yaw_mat.mulVec(&look_pitched).mulScalar(self.screen_dist);
    const x_yawed = yaw_mat.mulVec(&x_pitched).normalize(0.00001);
    const y_yawed = yaw_mat.mulVec(&y_pitched).normalize(0.00001);

    self.uniform.lookat = math.vec3(look_yawed.x(), look_yawed.y(), look_yawed.z());
    self.uniform.plane_X = math.vec3(x_yawed.x(), x_yawed.y(), x_yawed.z());
    self.uniform.plane_Y = math.vec3(y_yawed.x(), y_yawed.y(), y_yawed.z());
}

pub fn set_fov(self: *This, fov: f32) void {
    self.screen_dist = 1.0 / @tan(fov / 2);
    log.info("fov set to {d}", .{self.screen_dist});
}

pub fn deinit(self: *This) void {
    self.buff.destroy();
    self.bindgroup.release();
}
