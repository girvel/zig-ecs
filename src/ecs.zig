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

        fn realign_pointers(
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

pub fn World(comptime systems: []const type) type {
    const ComponentStorage = comptime blk: {
        var size = 0;
        for (systems) |system| {
            for (system.traits) |trait| {
                for (trait.components) |_| {
                    size += 1;
                }
            }
        }

        var result: [size]toolkit.Field = undefined;
        var i = 0;
        
        for (systems) |system| {
            for (system.traits) |trait| {
                for (trait.components) |component| {
                    result[i] = .{  // TODO check for collisions
                        .name = component.name,
                        .type = std.ArrayList(component.type),
                    };
                    i += 1;
                }
            }
        }

        break :blk toolkit.Struct(&result);
    };

    return struct {
        // TODO world contains components, systems contain entities
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

        pub fn add(self: *Self, entity: anytype) void {
            const t = @TypeOf(entity);

            inline for (@typeInfo(ComponentStorage).@"struct".fields) |component_field| {
                const base_type = @typeInfo(component_field.type.Slice).@"pointer".child;
                if (!@hasField(t, component_field.name)) continue;

                const component_value = @field(entity, component_field.name);
                if (@TypeOf(component_value) != base_type) {
                    @compileError(
                        "entity's ." ++ component_field.name ++
                        " should be of type " ++ @typeName(base_type)
                    );
                }

                var component_list = &@field(self.components, component_field.name);
                const old_ptr = component_list.items.ptr;
                component_list.append(component_value) catch unreachable;
                const new_ptr = component_list.items.ptr;

                if (new_ptr != old_ptr and component_list.items.len > 1) {
                    const old_ptr_isize: isize = @intCast(@intFromPtr(old_ptr));
                    const new_ptr_isize: isize = @intCast(@intFromPtr(new_ptr));
                    inline for (&self.systems) |*system| {
                        system.realign_pointers(
                            component_field.name, new_ptr_isize - old_ptr_isize
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
