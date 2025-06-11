const std = @import("std");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);
const ecs = @import("ecs.zig");

// TODO managing stuff like strings?
// TODO const references in traits?


const Inert = struct {
    position: *i32_2,
    velocity: *i32_2,
};

const Constants = struct {
    g: *i32_2,
};

fn only_system(entity: Inert, constants: Constants) void {
    std.debug.print("p = {}, v = {}\n", .{entity.position, entity.velocity});
    entity.velocity.add_mut(constants.g.*);
    entity.position.add_mut(entity.velocity.*);
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = ecs.BuildWorld(only_system).init(allocator);

    world.add(.{
        .position = i32_2.from_array(.{0, 0}),
        .velocity = i32_2.from_array(.{1, 0}),
        .mass = @as(i32, 8),
        .depth = 3,
    });

    world.add(.{
        .position = i32_2.from_array(.{0, 0}),
        .velocity = i32_2.from_array(.{1, 1}),
        .mass = @as(i32, 3),
        .name = "Kitty",
    });

    world.add(.{
        .mass = 2,
    });

    world.add(.{
        .g = i32_2.from_array(.{0, 10}),
    });

    world.update();
    world.update();
    world.update();
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
