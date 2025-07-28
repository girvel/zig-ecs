const std = @import("std");
const rl = @import("raylib");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);

pub fn main() !void {
    const window_size = i32_2.from_array(.{100, 100});
    rl.initWindow(window_size.items[0], window_size.items[1], "Zig ECS test");
    defer rl.closeWindow();

    const mannequin = try rl.loadTexture("assets/mannequin.png");

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        rl.drawTexture(mannequin, 0, 0, .white);
    }
}
