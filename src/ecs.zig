const std = @import("std");
const toolkit = @import("toolkit.zig");
const StructField = std.builtin.Type.StructField;

const Component = struct {name: [:0]const u8, type: type};
const Trait = struct {type: type, components: []const Component};

pub const Threading = union(enum) {
    none,
    batch_based: struct {
        argument_i: usize,
        batch_size: usize,
    },
};

pub fn System(comptime system_fn: anytype, threading: Threading) type {
    const traits_ = blk: {
        const params = @typeInfo(@TypeOf(system_fn)).@"fn".params;
        var result: [params.len]Trait = undefined;
        for (&result, params) |*trait, param| {
            trait.type = param.type orelse unreachable;
            const components = components: {
                const argument_fields = @typeInfo(trait.type).@"struct".fields;
                var components: [argument_fields.len]Component = undefined;
                for (&components, argument_fields) |*component, field| {
                    component.* = .{
                        .name = field.name,
                        .type = @typeInfo(field.type).pointer.child,
                        // TODO compile error if not a pointer
                    };
                }
                break :components components;
            };
            trait.components = &components;
        }
        break :blk result;
    };

    const es_types = blk: {
        comptime var result: [traits_.len]type = undefined;
        for (&result, traits_) |*r, t| {
            r.* = std.ArrayList(t.type);
        }
        break :blk result;
    };

    const EntityStorage = std.meta.Tuple(&es_types);

    return struct {
        entities: EntityStorage,
        active_lengths: [traits.len]usize,
        allocator: std.mem.Allocator,
        const traits = traits_;
        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            result.allocator = allocator;
            inline for (0.., traits) |i, trait| {
                result.entities[i] = std.ArrayList(trait.type).init(allocator);
                result.active_lengths[i] = 0;
            }
            return result;
        }

        fn plan_add(
            self: *Self, entity: anytype, component_storage: anytype, creation_queue: anytype
        ) void {
            inline for (0.., traits) |i, trait| {
                inline for (trait.components) |component| {
                    if (!@hasField(@TypeOf(entity), component.name)) break;
                } else {
                    var subject: trait.type = undefined;
                    inline for (trait.components) |component| {
                        const storage_slice = @field(component_storage, component.name).items;
                        const queue = @field(creation_queue, component.name).items;
                        @field(subject, component.name)
                            = &storage_slice.ptr[storage_slice.len + queue.len - 1];
                    }
                    self.entities[i].append(subject) catch unreachable;
                }
            }
        }

        fn flush_add(self: *Self) void {
            inline for (&self.active_lengths, self.entities) |*len, list| {
                len.* = list.items.len;
            }
        }

        pub fn update(self: *Self) void {
            const TupleOfSlices = comptime blk: {
                var result: [es_types.len]type = undefined;
                for (&result, es_types) |*r, s| {
                    r.* = s.Slice;
                }
                break :blk std.meta.Tuple(&result);
            };

            const cpu_n = std.Thread.getCpuCount() catch unreachable;
            switch (threading) {
                .none => {
                    var to_iterate: TupleOfSlices = undefined;
                    inline for (0..self.entities.len) |i| {
                        to_iterate[i] = self.entities[i].items;
                    }
                    update_system(system_fn, to_iterate, self.active_lengths);
                },

                .batch_based => |threading_config| {
                    var pool: std.Thread.Pool = undefined;
                    pool.init(.{.allocator = self.allocator}) catch unreachable;
                    defer pool.deinit();

                    const batches_n = std.math.divCeil(
                        usize,
                        self.entities[threading_config.argument_i].items.len,
                        threading_config.batch_size,
                    ) catch unreachable;

                    for (0..batches_n) |batch_i| {
                        var to_iterate: TupleOfSlices = undefined;
                        var active_lengths = self.active_lengths;
                        inline for (0..self.entities.len) |argument_i| {
                            if (argument_i == threading_config.argument_i) {
                                const slice = self.entities[argument_i].items;
                                to_iterate[argument_i] = slice[
                                    threading_config.batch_size * batch_i / cpu_n..
                                    @min(
                                        threading_config.batch_size * (batch_i + 1) / cpu_n,
                                        self.active_lengths[argument_i] - 1,
                                    )
                                ];
                                active_lengths[argument_i] = to_iterate[argument_i].len;
                            } else {
                                to_iterate[argument_i] = self.entities[argument_i].items;
                            }
                        }

                        pool.spawn(update_system, .{
                            system_fn,
                            to_iterate,
                            active_lengths,
                        }) catch unreachable;
                    }
                },
            }
        }

        fn shift_pointers(
            self: *Self, comptime dangling_component: [:0]const u8, delta: isize
        ) void {
            inline for (traits, 0..) |trait, i| {
                inline for (trait.components) |component| {
                    const is_component_found = comptime std.mem.eql(
                        u8, component.name, dangling_component
                    );
                    if (!is_component_found) continue;
                    for (self.entities[i].items) |*e| {
                        const old_address: isize = @bitCast(@intFromPtr(
                            @field(e, component.name)
                        ));
                        const new_address: isize = old_address + delta;
                        const new_address_usize: usize = @bitCast(new_address);
                        @field(e, component.name) = @ptrFromInt(new_address_usize);
                    }
                    break;
                }
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
            try writer.print("- Entity collections:\n", .{});
            inline for (Self.traits, self.active_lengths, self.entities) |trait, len, list| {
                try writer.print("  - {}: {}/{}\n", .{trait.type, len, list.items.len});
            }
        }
    };
}

pub fn World(comptime systems: []const type) type {
    const ComponentStorage, const all_components = comptime blk: {
        var storage_fields: []const toolkit.Field = &.{};
        var all_components: []const Component = &.{};
        for (systems) |system| {
            for (system.traits) |trait| {
                for (trait.components) |component| {
                    for (storage_fields) |field| {
                        if (std.mem.eql(u8, field.name, component.name)) break;
                    } else {
                        storage_fields = storage_fields ++ .{toolkit.Field{
                            .name = component.name,
                            .type = std.ArrayList(component.type),
                        }};

                        all_components = all_components ++ .{Component{
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

    return struct {
        components: ComponentStorage,
        creation_queue: ComponentStorage,
        systems: std.meta.Tuple(systems),

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            inline for (@typeInfo(ComponentStorage).@"struct".fields) |field| {
                @field(result.components, field.name) = field.type.init(allocator);
                @field(result.creation_queue, field.name) = field.type.init(allocator);
            }
            inline for (0.., systems) |i, system| {
                result.systems[i] = system.init(allocator);
            }
            return result;
        }

        pub fn _add(self: *anyopaque, entity: anytype) void {
            var self_world: Self = @ptrCast(self);
            self_world.add(entity);
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
                }
                
                creation_queue.clearRetainingCapacity();
            }

            inline for (&self.systems) |*system| {
                system.flush_add();
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
                try writer.print("  {s}: {}\n", .{
                    component.name,
                    @field(self.components, component.name).items.len
                });
            }
        }
    };
}

fn update_system(
    system: anytype, entity_collections: anytype, lengths: [entity_collections.len]usize,
) void {
    var iterator = toolkit.cartesian(entity_collections, lengths);
    while (iterator.next()) |entry| {
        @call(.auto, system, entry);
    }
}
