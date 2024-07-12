const std = @import("std");
const coro = @import("coro");

scheduler: coro.Scheduler,
pool: coro.ThreadPool,

pub fn init(self: *@This(), ally: std.mem.Allocator) !void {
    self.scheduler = try coro.Scheduler.init(ally, .{});
    errdefer self.scheduler.deinit();
    self.pool = try coro.ThreadPool.init(ally, .{});
}

pub fn deinit(self: *@This(), ally: std.mem.Allocator) void {
    self.scheduler.deinit();
    self.pool.deinit();
    _ = ally; // autofix
}
