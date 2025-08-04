const closure = @import("closure.zig");
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

    const Promises = comptime blk: {
        var types: [config.entity_types.len]type = undefined;
        for (&types, config.entity_types) |*PromiseList, Entity| {
            PromiseList.* = std.ArrayList(Promise(Entity));
        }
        break :blk std.meta.Tuple(&types);
    };

    return struct {
        components: ComponentStorage,
        creation_queue: ComponentStorage,
        systems: std.meta.Tuple(config.systems),
        entities_globally: EntityStorage,
        promises: Promises,

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
            inline for (&result.promises, config.entity_types) |*promise, Entity| {
                promise.* = std.ArrayList(Promise(Entity)).init(allocator);
            }
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

        pub fn promise_add(self: *Self, comptime Entity: type, entity: anytype) *Promise(Entity) {
            const list_index = comptime for (0.., EntityStorage.requirements) |i, requirement| {
                if (requirement.type == Entity) break i;
            } else @compileError(@typeName(Entity) ++ " is not listed in world's entity types");
            // TODO! check that entity fits Entity
            self.plan_add(entity);
            const list = &self.entities_globally.lists[list_index];
            self.promises[list_index].append(Promise(Entity) { .ref = .{
                .list = list,
                .index = list.items.len - 1,
            }}) catch unreachable;
            const promise_slice = self.promises[list_index].items;
            return &promise_slice[promise_slice.len - 1];
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

            inline for (&self.promises) |*promise_list| {
                for (promise_list.items) |*promise| {
                    promise.resolve();
                }

                promise_list.clearRetainingCapacity();
            }
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

pub fn Promise(comptime T: type) type {
    return struct {
        const Callback = closure.New(&.{Ref(T)}, void);
        ref: Ref(T),
        callback: ?Callback = null,
        const Self = @This();
        pub fn then(self: *Self, callback: Callback) void {
            if (self.callback != null) @panic(".then on promise that already has been .then-ed");
            self.callback = callback;
        }

        pub fn resolve(self: *Self) void {
            if (self.callback) |*callback| {
                callback.invoke(.{self.ref});
                callback.deinit();
            }
            self.callback = null;
        }
    };
}

/// Reference for a value stored in ArrayList
pub fn Ref(comptime T: type) type {
    return struct {
        list: *std.ArrayList(T),
        index: usize,

        const Self = @This();

        pub fn get(self: Self) *T {
            return &self.list.items[self.index];
        }
    };
}
