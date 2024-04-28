const std = @import("std");
const mach = @import("mach");
const config = @import("config");
const events = @import("./event.zig");
const render = @import("./render.zig");
const mouse = @import("./mouse.zig");
const CameraController = @import("./camera_controller.zig");
const core = mach.core;

const initial_title = "voxel renderer";
pub const std_options: std.Options = .{ .log_scope_levels = &[_]std.log.ScopeLevel{
    .{ .scope = .mach, .level = .debug },
} };
pub const App = @This();

title_timer: if (config.dev) core.Timer else void,
timer: core.Timer,
camera_controller: CameraController = undefined,
movement: CameraController.Movement = .{},

pub fn init(app: *App) !void {
    try core.init(.{
        .title = initial_title,
        .is_app = false,
        .size = .{ .height = 600, .width = 800 },
        .display_mode = .windowed,
    });
    app.* = .{ .timer = try core.Timer.start(), .title_timer = if (config.dev) try core.Timer.start() else {} };
    try render.init();
    CameraController.init();
    app.camera_controller = CameraController{};
}

pub fn update(app: *App) !bool {
    if (events.handle_events(&app.movement)) return true;
    app.camera_controller.move(app.movement, mouse.mouse_delta(), &render.camera);
    render.update(app);
    if (config.dev) try display_fps_on_title(app);
    return false;
}

pub fn deinit(app: *App) void {
    _ = app; // autofix
    core.deinit();
}

fn display_fps_on_title(app: *App) !void {
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle(initial_title ++ " [FPS {d}]", .{core.frameRate()});
    }
}
