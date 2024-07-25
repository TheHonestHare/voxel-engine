const std = @import("std");
const config = @import("config");
// TODO: determine if allocators should be stored, or just accessed through `.allocator()` methods
// TODO: are these safe to use cross threaded

/// allocations that are safe to be reset at the end of each game tick
pub var TickAllocator: std.mem.Allocator = undefined;
pub var TickArena: std.heap.ArenaAllocator = undefined;

/// allocations that are safe to be reset at the end of each frame render
pub var RFrameAllocator: std.mem.Allocator = undefined;
pub var RFrameArena: std.heap.ArenaAllocator = undefined;

/// general purpose allocations that should last for the whole duration of the program
pub var LongAllocator: std.mem.Allocator = undefined;
// TODO: change config struct based on config.dev?
var LongGPA: if(config.dev) std.heap.GeneralPurposeAllocator(.{}) else void = if(config.dev) .{} else {};


pub fn init() void {
    LongAllocator = if(config.dev) LongGPA.allocator() else std.heap.c_allocator;

    // TODO: what allocator should we use?
    RFrameArena = std.heap.ArenaAllocator.init(if(config.dev) LongAllocator else std.heap.PageAllocator);
    RFrameAllocator = RFrameArena.allocator();

    TickArena = std.heap.ArenaAllocator.init(if(config.dev) LongAllocator else std.heap.PageAllocator);
    TickAllocator = TickArena.allocator();
}

/// Call this function after all others to ensure no memory leaks
pub fn deinit() noreturn {
    if(config.clean_exit) {
        RFrameArena.deinit();
        TickArena.deinit();
        _ = LongGPA.deinit();
    }
    std.process.exit(0);
}