const std = @import("std");
const toolkit = @import("toolkit.zig");
const StructField = std.builtin.Type.StructField;

// TERMS:
// Trait is a type of a system argument
// Component is a field of the trait
//
// fn system_function(arg1 Trait1, arg2 Trait2, ...) void {}
// const Trait1 = struct {
//     component1: *Component1,
//     component2: *Component2,
//     ...
//  };

const Component = struct {
    name: [:0]const u8, 
    type: type,
};

const Trait = struct {
    storage_type: type,
    out_type: type,
    components: []const Component,
};

pub const Threading = union(enum) {
    none,
    batch_based: struct {
        argument_i: usize,
        batch_size: usize,
    },
};

pub fn BuildWorld(comptime only_system: anytype, threading: Threading) type {
    const traits = blk: {
        const params = @typeInfo(@TypeOf(only_system)).Fn.params;
        var result: [params.len]Trait = undefined;

        for (&result, params) |*trait, param| {
            trait.out_type = param.type orelse unreachable;
            trait.storage_type = st: {
                const source_fields = @typeInfo(trait.out_type).Struct.fields;
                comptime var ibe: [source_fields.len]toolkit.Field = undefined;
                for (&ibe, source_fields) |*field, source| {
                    field.* = .{
                        .name = source.name,
                        .type = usize,
                    };
                }
                break :st ibe;
            };

            const components = components: {
                const argument_fields = @typeInfo(trait.type).Struct.fields;
                var components: [argument_fields.len]Component = undefined;
                for (&components, argument_fields) |*component, field| {
                    component.* = .{
                        .name = field.name,
                        .type = @typeInfo(field.type).Pointer.child,
                        // TODO compile error if not a pointer
                    };
                }
                break :components components;
            };
            trait.components = &components;
        }
        break :blk result;
    };

    const ComponentStorage = blk: {
        comptime var size = 0;
        for (traits) |trait| {
            for (trait.components) |_| {
                size += 1;
            }
        }

        var result: [size]toolkit.Field = undefined;
        var i = 0;
        
        for (traits) |trait| {
            for (trait.components) |component| {
                result[i] = .{  // TODO check for collisions
                    .name = component.name,
                    .type = std.ArrayList(component.type),
                };
                i += 1;
            }
        }

        break :blk toolkit.Struct(&result);
    };

    const es_types = blk: {
        comptime var result: [traits.len]type = undefined;
        for (&result, traits) |*r, t| {
            r.* = std.ArrayList(t.storage_type);
        }
        break :blk result;
    };

    const EntityStorage = std.meta.Tuple(&es_types);

    return struct {
        // TODO world contains components, systems contain entities
        components: ComponentStorage,
        entities: EntityStorage,
        allocator: std.mem.Allocator,

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            result.allocator = allocator;
            inline for (0.., traits) |i, trait| {
                result.entities[i] = std.ArrayList(trait.storage_type).init(allocator);
                inline for (trait.components) |component| {  // TODO use all_components
                    @field(result.components, component.name)
                        = std.ArrayList(component.type).init(allocator);
                }
            }
            return result;
        }

        pub fn add(self: *Self, entity: anytype) void {
            const t = @TypeOf(entity);

            inline for (0.., traits) |i, trait| {
                inline for (trait.components) |component| {
                    if (!@hasField(t, component.name)) break;
                    if (@TypeOf(@field(entity, component.name)) != component.type) {
                        @compileError(
                            "entity's ." ++ component.name ++
                            " should be of type " ++ @typeName(component.type)
                        );
                    }
                } else {
                    var subject: trait.storage_type = undefined;
                    inline for (trait.components) |component| {
                        @field(self.components, component.name)
                            .append(@field(entity, component.name)) catch unreachable;
                        const items = @field(self.components, component.name).items;
                        @field(subject, component.name) = items.len - 1;
                    }
                    self.entities[i].append(subject) catch unreachable;
                }
            }
        }

        pub fn update(self: *Self) void {
            const TupleOfSlices = comptime blk: {
                var result: [es_types.len]type = undefined;
                for (&result, es_types) |*r, s| {
                    r.* = ListToSlice(s);
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
                    Self.update_system(only_system, to_iterate);
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

                        pool.spawn(Self.update_system, .{
                            only_system,
                            to_iterate,
                        }) catch unreachable;
                    }
                },
            }
        }

        fn update_system(system: anytype, entity_collections: anytype) void {
            var iterator = toolkit.cartesian(entity_collections);
            while (iterator.next()) |entry| {
                const args_types = Args: {
                    comptime var fields: [traits.len]type = undefined;
                    for (&fields, traits) |*field, trait| {
                        field.* = trait.out_type;
                    }
                    break :Args fields;
                };

                const args = args: {
                    comptime var args: std.meta.Tuple(args_types) = undefined;
                    inline for (traits, 0..) |trait, i| {
                        comptime var arg: args_types[i] = undefined;
                        inline for (trait.)
                        args[i] = arg;  // TODO shorten
                    }
                    break :args args;
                };

                @call(.auto, system, args);
            }
        }
    };
}

fn ListToSlice(comptime List: type) type {
    return for (@typeInfo(List).Struct.fields) |f| {
        if (std.mem.eql(u8, f.name, "items")) break f.type;
    } else unreachable;
}
