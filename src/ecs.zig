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
        allocator: std.mem.Allocator,
        const traits = traits_;
        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            result.allocator = allocator;
            inline for (0.., traits) |i, trait| {
                result.entities[i] = std.ArrayList(trait.type).init(allocator);
            }
            return result;
        }

        fn add(self: *Self, entity: anytype, component_storage: anytype) void {
            inline for (0.., traits) |i, trait| {
                inline for (trait.components) |component| {
                    if (!@hasField(@TypeOf(entity), component.name)) break;
                } else {
                    var subject: trait.type = undefined;
                    inline for (trait.components) |component| {
                        const items = @field(component_storage, component.name).items;
                        @field(subject, component.name) = &items[items.len - 1];
                    }
                    self.entities[i].append(subject) catch unreachable;
                }
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
                    update_system(system_fn, to_iterate);
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
                        inline for (0..self.entities.len) |argument_i| {
                            if (argument_i == threading_config.argument_i) {
                                const slice = self.entities[argument_i].items;
                                to_iterate[argument_i] = slice[
                                    threading_config.batch_size * batch_i / cpu_n..
                                    @min(
                                        threading_config.batch_size * (batch_i + 1) / cpu_n,
                                        slice.len - 1,
                                    )
                                ];
                            } else {
                                to_iterate[argument_i] = self.entities[argument_i].items;
                            }
                        }

                        pool.spawn(update_system, .{
                            system_fn,
                            to_iterate,
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
                    if (std.mem.eql(u8, component.name, dangling_component)) {
                        for (self.entities[i].items) |*e| {
                            const old_address: isize = @intCast(@intFromPtr(
                                @field(e, component.name)
                            ));
                            const new_address: isize = old_address + delta;
                            const new_address_usize: usize = @intCast(new_address);
                            @field(e, component.name) = @ptrFromInt(new_address_usize);
                        }
                    }
                    break;
                }
            }
        }
    };
}

pub const Avatar = struct {
    _world: *anyopaque,
    _add: *const fn (*anyopaque, anytype) void,
    const Self = @This();
    pub fn add(self: Self, entity: anytype) void {
        self._add(self._world, entity);
    }
};

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

    // const Entity = comptime blk: {
    //     var result: []const toolkit.Field = &.{};
    //     for (all_components) |component| {
    //         result = result ++ .{toolkit.Field{
    //             .name = component.name,
    //             .type = ?*component.type,
    //         }};
    //     }
    //     break :blk toolkit.Struct(@constCast(result));
    // };

    // const Genesis = struct {
    //     creation_queue: std.ArrayList(Entity),
    // };

    // const GenesisSystem = (struct {
    //     fn genesis_fn(genesis: Genesis) void {
    //         for (genesis.creation_queue.items) |e| {
    //             
    //         }
    //     }
    // }{}).genesis_fn;

    return struct {
        components: ComponentStorage,
        systems: std.meta.Tuple(systems),

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            inline for (@typeInfo(ComponentStorage).@"struct".fields) |field| {
                @field(result.components, field.name) = field.type.init(allocator);
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

        pub fn add(self: *Self, entity: anytype) void {
            const t = @TypeOf(entity);

            inline for (all_components) |component| {
                if (!@hasField(t, component.name)) continue;

                const component_value = @field(entity, component.name);
                if (@TypeOf(component_value) != component.type) {
                    @compileError(
                        "entity's ." ++ component.name ++
                        " should be of type " ++ @typeName(component.type)
                    );
                }

                var component_list = &@field(self.components, component.name);
                const old_ptr = component_list.items.ptr;
                component_list.append(component_value) catch unreachable;
                const new_ptr = component_list.items.ptr;

                if (new_ptr != old_ptr and component_list.items.len > 1) {
                    const old_ptr_isize: isize = @intCast(@intFromPtr(old_ptr));
                    const new_ptr_isize: isize = @intCast(@intFromPtr(new_ptr));
                    inline for (&self.systems) |*system| {
                        system.shift_pointers(
                            component.name, new_ptr_isize - old_ptr_isize
                        );
                    }
                }
            }

            inline for (&self.systems) |*system| {
                system.add(entity, self.components);
            }
        }

        pub fn update(self: *Self) void {
            inline for (&self.systems) |*system| {
                system.update();
            }
        }
    };
}

fn update_system(system: anytype, entity_collections: anytype) void {
    var iterator = toolkit.cartesian(entity_collections);
    while (iterator.next()) |entry| {
        @call(.auto, system, entry);
    }
}
