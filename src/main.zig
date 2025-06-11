const std = @import("std");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);
const ecs = @import("ecs.zig");

// TODO managing stuff like strings?


const Inert = struct {
    position: *i32_2,
    velocity: *i32_2,
};

fn display_y(entity: Inert) void {
    std.debug.print("p = {}, v = {}\n", .{entity.position, entity.velocity});
    entity.position.add_mut(entity.velocity.*);
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = ecs.BuildWorld(display_y).init(allocator);

    world.add(.{
        .position = i32_2.from_array(.{3, 4}),
        .velocity = i32_2.from_array(.{-1, 0}),
        .mass = @as(i32, 8),
        .depth = 3,
    });

    world.add(.{
        .position = i32_2.from_array(.{3, 5}),
        .velocity = i32_2.from_array(.{1, 1}),
        .mass = @as(i32, 3),
        .name = "Kitty",
    });

    world.add(.{
        .mass = 2,
    });

    world.update();
    world.update();
    world.update();
}
