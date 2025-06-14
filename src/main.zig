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
    std.debug.print("g = {}\n", .{constants.g.*});
    entity.velocity.add_mut(constants.g.*);
    entity.position.add_mut(entity.velocity.*);
}


const ENTITIES_N = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = ecs.BuildWorld(only_system, null).init(allocator);

    for (0..ENTITIES_N) |i| {
        const  x = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
        const  y = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
        const vx = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
        const vy = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
        world.add(.{
            .position = i32_2.from_array(.{i, i}),
            .velocity = i32_2.from_array(.{i, i}),
        });
    }

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
