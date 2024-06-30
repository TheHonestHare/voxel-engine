const std = @import("std");
const mach = @import("mach");
const CameraController = @import("./camera_controller.zig");
const config = @import("config");
const render = @import("./render.zig");

const log = std.log.scoped(.events);

pub fn handle_events(movement: *CameraController.Movement, core: *mach.Core.Mod) void {
    var iter = mach.core.pollEvents();
    while (iter.next()) |e| {
        switch (e) {
            .close => break,
            .key_press => |key| if (input_press(movement, key)) break,
            .key_release => |key| if (input_release(movement, key)) break,
            else => {},
        }
    } else return;
    core.schedule(.exit);
    return;
}

fn input_press(movement: *CameraController.Movement, key: mach.core.KeyEvent) bool {
    switch (key.key) {
        .escape => return true,
        .k => if (config.dev) {
            render.deinit();
            render.init() catch return true;
            log.info("rendering reloaded", .{});
        } else {},
        .w => movement.fowards = true,
        .a => movement.left = true,
        .s => movement.back = true,
        .d => movement.right = true,
        .left_shift => movement.down = true,
        .space => movement.up = true,
        else => {},
    }
    return false;
}

fn input_release(movement: *CameraController.Movement, key: mach.core.KeyEvent) bool {
    switch (key.key) {
        .w => movement.fowards = false,
        .a => movement.left = false,
        .s => movement.back = false,
        .d => movement.right = false,
        .left_shift => movement.down = false,
        .space => movement.up = false,
        else => {},
    }
    return false;
}
