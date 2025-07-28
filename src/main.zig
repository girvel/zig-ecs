const std = @import("std");
const rl = @import("raylib");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);
const ecs = @import("ecs.zig");

// TODO sprite or text
const Drawable = struct {
    position: *i32_2,
    sprite: *rl.Texture2D,
};

fn draw(target: Drawable) void {
    const pos = target.position.*.items;
    rl.drawTexture(target.sprite.*, pos[0], pos[1], .white);
}

fn control() void {
    if (rl.isKeyPressed(.w)) {
        std.debug.print("forward!\n", .{});
    }
}

pub fn main() !void {
    const window_size = i32_2.from_array(.{100, 100});
    rl.initWindow(window_size.items[0], window_size.items[1], "Zig ECS test");
    defer rl.closeWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = ecs.World(&.{
        ecs.System(draw, .none),
        ecs.System(control, .none),
    }).init(allocator);

    const mannequin = try rl.loadTexture("assets/mannequin.png");
    const moose_dude = try rl.loadTexture("assets/moose_dude.png");

    world.add(.{
        .position = i32_2.from_array(.{0, 0}),
        .sprite = moose_dude,
    });

    world.add(.{
        .position = i32_2.from_array(.{16, 0}),
        .sprite = mannequin,
    });

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        world.update();
    }
}
