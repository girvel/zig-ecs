const std = @import("std");

pub fn BuildWorld(only_system: anytype) type {
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
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self {
                .components = std.ArrayList(FieldType).init(allocator),
                .entities = std.ArrayList(Argument).init(allocator),
            };
        }

        pub fn add(self: *Self, entity: anytype) void {
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

        pub fn update(self: *Self) void {
            for (self.entities.items) |e| {
                @call(.auto, only_system, .{e});
            }
        }
    };
}
