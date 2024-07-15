const std = @import("std");
const config = @import("config");

// TODO: remove this allocator and deal with the appdata subfolder directory not existing/not being correct format
/// doesn't return an error bc all errors are panics!!!!
pub fn changeCWDToSave(allocator: std.mem.Allocator) void {
    if(config.save_folder) |dirname| {
        var buff: [std.fs.max_path_bytes]u8 = undefined;
        const self_exe_dir_path = std.fs.selfExeDirPath(&buff) catch |e| std.debug.panic("couldn't get self exe path: {}", .{e});
        const abs_dirname = std.fs.path.join(allocator, &.{self_exe_dir_path, dirname}) catch std.debug.panic("OOM", .{});
        defer allocator.free(abs_dirname);
        std.process.changeCurDir(abs_dirname) catch |e| changeDirErrorPanic(e);
    } else if(config.game_dir_name) |dirname| {
        const save_dir = std.fs.getAppDataDir(allocator, dirname) catch |e| switch (e) {
            error.OutOfMemory => std.debug.panic("Got OOM how did this even happen this allocator shouldn't even be here", .{}),
            error.AppDataDirUnavailable => std.debug.panic("Appdata directory not found for some reason", .{}),
        };
        defer allocator.free(save_dir);
        std.process.changeCurDir(save_dir) catch |e| changeDirErrorPanic(e);
    } else @compileError("Either -Dsave_folder=\"\" (for debugging) or -Dgame_dir_name=\"\" (for release) must be specified when building");
}

inline fn changeDirErrorPanic(err: std.posix.ChangeCurDirError) noreturn {
    std.debug.panic("Failed to change the current directory to the custom save folder: {}", .{err});
}