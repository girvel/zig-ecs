const std = @import("std");

const ContainsY = struct {
    y: *i32,
};

fn display_y(entity: ContainsY) void {
    std.debug.print("y = {}\n", .{entity.y.*});
}

const World = struct {
    ys: std.ArrayList(i32),
    display_y_subjects: std.ArrayList(ContainsY),

    fn add(self: *World, entity: anytype) void {
        const t = @TypeOf(entity);
        if (@hasField(t, "y")) {
            if (@TypeOf(@field(entity, "y")) != i32) {
                @compileError("entity's .y should be of type i32");
            }

            self.ys.append(@field(entity, "y")) catch unreachable;
            self.display_y_subjects.append(ContainsY {
                .y = &self.ys.items[self.ys.items.len - 1],
            }) catch unreachable;
        }
    }

    fn update(self: *World) void {
        for (self.display_y_subjects.items) |e| {
            display_y(e);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = World {
        .ys = std.ArrayList(i32).init(allocator),
        .display_y_subjects = std.ArrayList(ContainsY).init(allocator),
    };

    world.add(.{
        .y = @as(i32, 32),
        .x = 0,
    });

    world.add(.{
        .y = @as(i32, 16),
        .name = "Kitty",
    });

    world.update();
    world.update();
}
