const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    std.debug.print("Hello, world!\n", .{});
    rl.initWindow(100, 20, "Zig ECS test");
    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        rl.drawText("Hi raylib", 0, 0, 20, .black);
    }
}
