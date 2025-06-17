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

const up_ish = i32_2.from_array(.{12, -44});
const down_ish = i32_2.from_array(.{-44, 89});

fn only_system(entity: Inert, constants: Constants) void {
    var p = entity.position;
    var v = entity.velocity;

    inline for (0..100) |_| {
        v.add_mut(if (p.items[1] > 0) down_ish else up_ish);
    }

    v.add_mut(constants.g.*);
    p.add_mut(v.*);
}


const ENTITIES_N = 1_000_000;
const TICKS = 10;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    std.debug.print("{} entities, {} ticks\n", .{ENTITIES_N, TICKS});

    inline for ([_]ecs.Threading {
        .none,
        .{.batch_based = .{.batch_size = 1024, .argument_i = 0}},
    }) |threading| {
        var world = ecs.BuildWorld(only_system, threading).init(allocator);

        // TODO handle dangling pointers bug
        world.components.position.ensureTotalCapacity(ENTITIES_N) catch unreachable;
        world.components.velocity.ensureTotalCapacity(ENTITIES_N) catch unreachable;

        for (0..ENTITIES_N) |_| {
            const  x = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
            const  y = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
            const vx = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
            const vy = std.crypto.random.intRangeAtMost(i32, -1000, 1000);
            world.add(.{
                .position = i32_2.from_array(.{x, y}),
                .velocity = i32_2.from_array(.{vx, vy}),
            });
        }

        world.add(.{
            .g = i32_2.from_array(.{0, 10}),
        });

        var timer = std.time.Timer.start() catch unreachable;
        const start = timer.lap();

        for (0..TICKS) |_| {
            world.update();
        }

        const end = timer.read();
        std.debug.print("{s}: {d:.2} FPS\n", .{
            if (threading == .none) "nothread" else "batch   ",
            1e9 * TICKS / @as(f64, @floatFromInt(end - start)),
        });
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
