const std = @import("std");
const mach = @import("mach");
const core = mach.core;

var prev: core.Position = undefined;
var is_first: bool = true;

pub fn mouse_delta() core.Position {
    const mouse_pos = core.mousePosition();
    if (is_first) {
        is_first = std.meta.eql(prev, mouse_pos);
        prev = core.mousePosition();
        return .{ .x = 0, .y = 0 };
    }
    const pos = core.mousePosition();
    const temp: core.Position = .{ .x = pos.x - prev.x, .y = pos.y - prev.y };
    prev = pos;
    return temp;
}
