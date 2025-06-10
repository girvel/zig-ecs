const std = @import("std");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);

const Positioned = struct {
    position: *i32_2,
};

fn display_y(entity: Positioned) void {
    std.debug.print("pos = {}\n", .{entity.position});
}

fn BuildWorld(only_system: anytype) type {
    const system_info = @typeInfo(@TypeOf(only_system));
    const Argument: type = system_info.Fn.params[0].type orelse unreachable;
    const argument_only_field: std.builtin.Type.StructField
        = @typeInfo(Argument).Struct.fields[0];
    const field_name = argument_only_field.name;
    const FieldType = @typeInfo(argument_only_field.type).Pointer.child;

    return struct {
        // TODO bad field naming
        // TODO world contains components, systems contain entities
        ys: std.ArrayList(FieldType),
        display_y_subjects: std.ArrayList(Argument),

        const Self = @This();
        fn add(self: *Self, entity: anytype) void {
            const t = @TypeOf(entity);
            if (@hasField(t, field_name)) {
                if (@TypeOf(@field(entity, field_name)) != FieldType) {
                    @compileError(
                        "entity's ." ++ field_name ++
                        " should be of type " ++ @typeName(FieldType)
                    );
                }

                self.ys.append(@field(entity, field_name)) catch unreachable;
                var subject: Argument = undefined;
                @field(subject, field_name) = &self.ys.items[self.ys.items.len - 1];
                self.display_y_subjects.append(subject) catch unreachable;
            }
        }

        fn update(self: *Self) void {
            for (self.display_y_subjects.items) |e| {
                @call(.auto, only_system, .{e});
            }
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // TODO .init
    var world = BuildWorld(display_y) {
        .ys = std.ArrayList(i32_2).init(allocator),
        .display_y_subjects = std.ArrayList(Positioned).init(allocator),
    };

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
}
