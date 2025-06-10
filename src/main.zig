const std = @import("std");
const vector = @import("vector.zig");
const i32_2 = vector.Vector(i32, 2);

const Positioned = struct {
    position: *i32_2,
};

const right = i32_2.from_array([_]i32{1, 0});

fn display_y(entity: Positioned) void {
    std.debug.print("pos = {}\n", .{entity.position});
    entity.position.add_mut(right);
}

fn BuildWorld(only_system: anytype) type {
    const system_info = @typeInfo(@TypeOf(only_system));
    const Argument: type = system_info.Fn.params[0].type orelse unreachable;
    const argument_only_field: std.builtin.Type.StructField
        = @typeInfo(Argument).Struct.fields[0];
    const field_name = argument_only_field.name;

    // TODO compile error if not a pointer
    const FieldType = @typeInfo(argument_only_field.type).Pointer.child;

    return struct {
        // TODO world contains components, systems contain entities
        components: std.ArrayList(FieldType),
        entities: std.ArrayList(Argument),

        const Self = @This();
        fn init(allocator: std.mem.Allocator) Self {
            return Self {
                .components = std.ArrayList(FieldType).init(allocator),
                .entities = std.ArrayList(Argument).init(allocator),
            };
        }

        fn add(self: *Self, entity: anytype) void {
            const t = @TypeOf(entity);
            if (@hasField(t, field_name)) {
                if (@TypeOf(@field(entity, field_name)) != FieldType) {
                    @compileError(
                        "entity's ." ++ field_name ++
                        " should be of type " ++ @typeName(FieldType)
                    );
                }

                self.components.append(@field(entity, field_name)) catch unreachable;
                var subject: Argument = undefined;
                @field(subject, field_name) = &self.components.items[self.components.items.len - 1];
                self.entities.append(subject) catch unreachable;
            }
        }

        fn update(self: *Self) void {
            for (self.entities.items) |e| {
                @call(.auto, only_system, .{e});
            }
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = BuildWorld(display_y).init(allocator);

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
