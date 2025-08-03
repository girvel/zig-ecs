const std = @import("std");
const rl = @import("raylib");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);
const ecs = @import("ecs.zig");
const toolkit = @import("toolkit.zig");

const Entity = struct {
    position: *i32_2,
    sprite: **rl.Texture2D,
    player_flag: *PlayerFlag,
};

const World = ecs.World(.{
    .systems = &.{
        ecs.System(flush_creation_queue, .none),
        ecs.System(begin_drawing, .none),
        ecs.System(draw, .none),
        ecs.System(end_drawing, .none),
        ecs.System(control, .none),
        ecs.System(test_creation, .none),
        ecs.System(debug, .none),
    },
    .entity_types = &.{Entity},
});

var world: World = undefined;

fn flush_creation_queue() void {
    world.flush_add();
}

fn begin_drawing() void {
    rl.beginDrawing();
    rl.clearBackground(.white);
}

// TODO sprite or text
const Drawable = struct {
    position: *i32_2,
    sprite: **rl.Texture2D,
};

fn draw(target: Drawable) void {
    const pos = target.position.*.items;
    rl.drawTexture(target.sprite.*.*, pos[0], pos[1], .white);
}

fn end_drawing() void {
    rl.endDrawing();
}

const PlayerFlag = struct {};
const Controllable = struct {
    player_flag: *PlayerFlag,
    position: *i32_2,
};

const keymap = [_]std.meta.Tuple(&.{rl.KeyboardKey, i32_2}) {
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

const TextureStorage = struct {
    mannequin: rl.Texture2D,
    moose_dude: rl.Texture2D,
};

var texture_storage: TextureStorage = undefined;

fn test_creation(target: Controllable) void {
    _ = target;
    if (rl.isKeyPressed(.f)) {
        world.plan_add(.{
            .position = i32_2.from(.{128, 256}),
            .sprite = &texture_storage.mannequin,
            .player_flag = PlayerFlag {},
        });
    }
}

var original_player_character: toolkit.Ref(Entity) = undefined;

fn debug() void {
    if (rl.isKeyPressed(.h)) {
        std.debug.print("{}\n", .{world});
    }

    if (rl.isKeyPressed(.backspace)) {
        original_player_character.get().sprite.* = &texture_storage.mannequin;
    }
}

pub fn main() !void {
    const window_size = i32_2.from(.{640, 480});
    rl.initWindow(window_size.items[0], window_size.items[1], "Zig ECS test");
    defer rl.closeWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    world = World.init(allocator);

    texture_storage = .{
        .moose_dude = try rl.loadTexture("assets/moose_dude.png"),
        .mannequin = try rl.loadTexture("assets/mannequin.png"),
    };

    world.plan_add(.{
        .position = i32_2.from(.{0, 0}),
        .sprite = &texture_storage.mannequin,
    });

    world.plan_add(.{
        .position = i32_2.from(.{16, 0}),
        .sprite = &texture_storage.moose_dude,
        .player_flag = PlayerFlag{},
    });

    original_player_character = blk: {
        const list = &world.entities_globally.lists[0];
        break :blk toolkit.Ref(Entity) {
            .list = list,
            .index = list.items.len - 1,
        };
    };

    world.plan_add(.{
        .texture_storage = texture_storage,
    });

    while (!rl.windowShouldClose()) {
        world.update();
        std.Thread.sleep(10_000_000);
    }
}
