const std = @import("std");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);
const ecs = @import("ecs.zig");


const Positioned = struct {
    position: *i32_2,
};

const right = i32_2.from_array([_]i32{1, 0});

fn display_y(entity: Positioned) void {
    std.debug.print("pos = {}\n", .{entity.position});
    entity.position.add_mut(right);
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = ecs.BuildWorld(display_y).init(allocator);

    world.add(.{
        .position = i32_2.from_array([_]i32{3, 4}),
        .depth = 3,
    });

    world.add(.{
        .position = i32_2.from_array([_]i32{3, 5}),
        .name = "Kitty",
    });

    world.update();
    world.update();
    world.update();
}
