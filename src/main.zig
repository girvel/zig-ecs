const std = @import("std");
const rl = @import("raylib");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);
const ecs = @import("ecs.zig");

// TODO sprite or text
const Drawable = struct {
    position: *const i32_2,
    sprite: *const rl.Texture2D,
};

fn draw(target: Drawable) void {
    const pos = target.position.*.items;
    rl.drawTexture(target.sprite.*, pos[0], pos[1], .white);
}

const PlayerFlag = struct {};
const Controllable = struct {
    player_flag: *const PlayerFlag,
    position: *i32_2,
};

const keymap = [_]std.meta.Tuple(&.{rl.KeyboardKey, i32_2}){
    .{.w, i32_2.from(.{0, -16})},
    .{.a, i32_2.from(.{-16, 0})},
    .{.s, i32_2.from(.{0, 16})},
    .{.d, i32_2.from(.{16, 0})},
};

fn control(target: Controllable) void {
    for (keymap) |mapping| {
        const key, const offset = mapping;
        if (rl.isKeyPressed(key)) {
            target.position.add_mut(offset);
        }
    }
}

pub fn main() !void {
    const window_size = i32_2.from(.{640, 480});
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
        .position = i32_2.from(.{0, 0}),
        .sprite = moose_dude,
    });

    world.add(.{
        .position = i32_2.from(.{16, 0}),
        .sprite = mannequin,
        .player_flag = PlayerFlag{},
    });

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        world.update();
    }
}
