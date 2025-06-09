const std = @import("std");

const ContainsY = struct {
    y: *i32,
};

fn display_y(entity: ContainsY) void {
    std.debug.print("y = {}\n", .{entity.y.*});
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
