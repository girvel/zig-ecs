const std = @import("std");

pub fn BuildWorld(only_system: anytype) type {
    const Argument = @typeInfo(@TypeOf(only_system)).Fn.params[0].type orelse unreachable;
    const Component = struct {name: [:0]const u8, type: type};
    const argument_fields = @typeInfo(Argument).Struct.fields;
    const required_components: [argument_fields.len]Component = blk: {
        var result: [argument_fields.len]Component = undefined;
        for (&result, argument_fields) |*component, field| {
            component.* = .{
                .name = field.name,
                .type = @typeInfo(field.type).Pointer.child,
                // TODO compile error if not a pointer
            };
        }
        break :blk result;
    };

    const storage_fields = blk: {
        var result: [required_components.len]std.builtin.Type.StructField = undefined;
        for (&result, required_components) |*field, component| {
            const List = std.ArrayList(component.type);
            field.* = .{
                .name = component.name,
                .type = List,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(List),
            };
        }
        break :blk result;
    };

    const Storage = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = &storage_fields,
        .decls = &.{},
        .is_tuple = false,
    }});

    return struct {
        // TODO world contains components, systems contain entities
        storage: Storage,
        entities: std.ArrayList(Argument),

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            result.entities = std.ArrayList(Argument).init(allocator);
            inline for (required_components) |component| {
                @field(result.storage, component.name)
                    = std.ArrayList(component.type).init(allocator);
            }
            return result;
        }

        pub fn add(self: *Self, entity: anytype) void {
            const t = @TypeOf(entity);

            inline for (required_components) |component| {
                if (!@hasField(t, component.name)) break;
                if (@TypeOf(@field(entity, component.name)) != component.type) {
                    @compileError(
                        "entity's ." ++ component.name ++
                        " should be of type " ++ @typeName(component.type)
                    );
                }
            } else {
                var subject: Argument = undefined;
                inline for (required_components) |component| {
                    @field(self.storage, component.name).append(@field(entity, component.name))
                        catch unreachable;
                    const items = @field(self.storage, component.name).items;
                    @field(subject, component.name) = &items[items.len - 1];
                }
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
