const std = @import("std");
const mach = @import("mach");
const config = @import("config");
const events = @import("./event.zig");
const render = @import("./render.zig");
const mouse = @import("./mouse.zig");
const CameraController = @import("./camera_controller.zig");

// Mach module stuff
pub const name = .app;
pub const Mod = mach.Mod(@This());
pub const systems = .{
    .init = .{ .handler = init },
    .after_init = .{ .handler = after_init },
    .deinit = .{ .handler = deinit },
    .tick = .{ .handler = update },
};

const initial_title = "voxel renderer";
pub const std_options: std.Options = .{ .log_scope_levels = &[_]std.log.ScopeLevel{
    .{ .scope = .mach, .level = .debug },
} };

title_timer: if (config.dev) mach.Timer else void,
timer: mach.Timer,
camera_controller: CameraController = undefined,
movement: CameraController.Movement = .{},

pub fn init(game: *Mod, core: *mach.Core.Mod) !void {
    try core.set(core.state().main_window, .width, 800);
    try core.set(core.state().main_window, .height, 600);
    core.schedule(.init);
    game.schedule(.after_init);
}

pub fn after_init(game: *Mod, core: *mach.Core.Mod) !void {
    game.init(.{
        .timer = try mach.Timer.start(),
        .title_timer = if (config.dev) (try mach.Timer.start()) else .{},
    });

    // TODO: add back normal title when not in dev
    try render.init();
    CameraController.init();
    game.state().camera_controller = .{};
    core.schedule(.start);
}

pub fn update(game: *Mod, core: *mach.Core.Mod) !void {
    events.handle_events(&game.state().movement, core);
    game.state().camera_controller.move(game.state().movement, mouse.mouse_delta(), &render.camera);
    render.update(game, core);
    if (config.dev) try display_stats_on_title(game, core);
}

pub fn deinit(game: *Mod, core: *mach.Core.Mod) void {
    _ = game; // autofix
    render.deinit();
    core.schedule(.deinit);
}

fn display_stats_on_title(game: *Mod, core: *mach.Core.Mod) !void {
    if (game.state().title_timer.read() >= 1.0) {
        game.state().title_timer.reset();
        try mach.Core.printTitle(core, core.state().main_window, initial_title ++ " [FPS {d} Input {d}hz]", .{
            mach.core.frameRate(),
            mach.core.inputRate(),
        });
    }
    core.schedule(.update);
}
