const entity_storage = @import("entity_storage.zig");
const toolkit = @import("../toolkit.zig");
const common = @import("common.zig");
const std = @import("std");

pub const WorldConfig = struct {
    systems: []const type,
    entity_types: []const type,
};

pub fn World(comptime config: WorldConfig) type {
    // TODO! extract ComponentStorage
    const ComponentStorage, const all_components = comptime blk: {
        var storage_fields: []const toolkit.Field = &.{};
        var all_components: []const common.Component = &.{};
        for (config.systems) |system| {
            for (system.EntityStorage.requirements) |requirement| {
                for (requirement.components) |component| {
                    for (storage_fields) |field| {
                        if (std.mem.eql(u8, field.name, component.name)) break;
                    } else {
                        storage_fields = storage_fields ++ .{toolkit.Field{
                            .name = component.name,
                            .type = std.ArrayList(component.type),
                        }};

                        all_components = all_components ++ .{common.Component{
                            .name = component.name,
                            .type = component.type,
                        }};
                    }
                }
            }
        }

        break :blk .{
            toolkit.Struct(@constCast(storage_fields)),
            all_components
        };
    };

    const EntityStorage = entity_storage.New(config.entity_types);

    return struct {
        components: ComponentStorage,
        creation_queue: ComponentStorage,
        systems: std.meta.Tuple(config.systems),
        entities_globally: EntityStorage,

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            inline for (@typeInfo(ComponentStorage).@"struct".fields) |field| {
                @field(result.components, field.name) = field.type.init(allocator);
                @field(result.creation_queue, field.name) = field.type.init(allocator);
            }
            inline for (0.., config.systems) |i, system| {
                result.systems[i] = system.init(allocator);
            }
            result.entities_globally = EntityStorage.init(allocator);
            return result;
        }

        pub fn plan_add(self: *Self, entity: anytype) void {
            const T = @TypeOf(entity);

            inline for (all_components) |component| {
                if (!@hasField(T, component.name)) continue;

                const component_value = @field(entity, component.name);
                if (@TypeOf(component_value) != component.type) {
                    @compileError(
                        "entity's ." ++ component.name ++
                        " should be of type " ++ @typeName(component.type) ++
                        ", got " ++ @typeName(@TypeOf(component_value)) ++ " instead"
                    );
                }

                @field(self.creation_queue, component.name)
                    .append(component_value) catch unreachable;
            }

            inline for (&self.systems) |*system| {
                system.plan_add(entity, &self.components, &self.creation_queue);
            }

            self.entities_globally.plan_add(entity, &self.components, &self.creation_queue);

            // TODO! error if some fields were not stored?
            //       or only if no fields were stored?
        }

        pub fn flush_add(self: *Self) void {
            inline for (all_components) |component| {
                var component_list = &@field(self.components, component.name);
                var creation_queue = &@field(self.creation_queue, component.name);
                const old_ptr = component_list.items.ptr;
                component_list.appendSlice(creation_queue.items)
                    catch unreachable;
                const new_ptr = component_list.items.ptr;

                if (new_ptr != old_ptr and component_list.items.len > 1) {
                    const old_ptr_isize: isize = @bitCast(@intFromPtr(old_ptr));
                    const new_ptr_isize: isize = @bitCast(@intFromPtr(new_ptr));
                    const delta = new_ptr_isize - old_ptr_isize;
                    std.debug.print("shift_pointers {s} {}\n", .{component.name, delta});
                    inline for (&self.systems) |*system| {
                        system.shift_pointers(component.name, delta);
                    }
                    self.entities_globally.shift_pointers(component.name, delta);
                }
                
                creation_queue.clearRetainingCapacity();
            }

            inline for (&self.systems) |*system| {
                system.flush_add();
            }

            self.entities_globally.flush_add();
        }

        pub fn update(self: *Self) void {
            inline for (&self.systems) |*system| {
                system.update();
            }
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("Systems:\n", .{});
            inline for (self.systems) |system| {
                try writer.print("{}", .{system});
            }
            try writer.print("Components:\n", .{});
            inline for (all_components) |component| {
                try writer.print("  {s}: {}+{}\n", .{
                    component.name,
                    @field(self.components, component.name).items.len,
                    @field(self.creation_queue, component.name).items.len,
                });
            }
            try writer.print("Entities globally:\n{}", .{self.entities_globally});
        }
    };
}
