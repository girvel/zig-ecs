const std = @import("std");
const toolkit = @import("toolkit.zig");
const StructField = std.builtin.Type.StructField;

const Component = struct {name: [:0]const u8, type: type};
const Trait = struct {type: type, components: []const Component};

pub fn BuildWorld(comptime only_system: anytype) type {
    const traits = blk: {
        const params = @typeInfo(@TypeOf(only_system)).Fn.params;
        var result: [params.len]Trait = undefined;
        for (&result, params) |*trait, param| {
            trait.type = param.type orelse unreachable;
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

    const cs_fields = blk: {
        comptime var size = 0;
        for (traits) |trait| {
            for (trait.components) |_| {
                size += 1;
            }
        }

        var result: [size]StructField = undefined;
        var i = 0;
        
        for (traits) |trait| {
            for (trait.components) |component| {
                const List = std.ArrayList(component.type);
                result[i] = .{  // TODO check for collisions
                    .name = component.name,
                    .type = List,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(List),
                };
                i += 1;
            }
        }

        break :blk result;
    };

    const ComponentStorage = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = &cs_fields,
        .decls = &.{},
        .is_tuple = false,
    }});

    const es_fields = blk: {
        comptime var result: [traits.len]StructField = undefined;
        
        for (0.., &result, traits) |i, *field, trait| {
            const List = std.ArrayList(trait.type);
            field.* = .{  // TODO check for collisions
                .name = std.fmt.comptimePrint("{}", .{i}),
                .type = List,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(List),
            };
        }

        break :blk result;
    };

    const EntityStorage = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = &es_fields,
        .decls = &.{},
        .is_tuple = true,
    }});

    return struct {
        // TODO world contains components, systems contain entities
        components: ComponentStorage,
        entities: EntityStorage,

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            inline for (0.., traits) |i, trait| {
                result.entities[i] = std.ArrayList(trait.type).init(allocator);
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
                    var subject: trait.type = undefined;
                    inline for (trait.components) |component| {
                        @field(self.components, component.name)
                            .append(@field(entity, component.name)) catch unreachable;
                        const items = @field(self.components, component.name).items;
                        @field(subject, component.name) = &items[items.len - 1];
                    }
                    self.entities[i].append(subject) catch unreachable;
                }
            }
        }

        pub fn update(self: *Self) void {
            const TupleOfSlices = blk: {
                const fields = fields: {
                    comptime var fields: [es_fields.len]StructField = undefined;
                    inline for (0.., &fields, es_fields) |i, *field, es_field| {
                        const T = ListToSlice(es_field.type);  // TODO zip
                        field.* = .{
                            .name = std.fmt.comptimePrint("{}", .{i}),
                            .type = T,
                            .default_value = null,
                            .is_comptime = false,
                            .alignment = @alignOf(T),
                        };
                    }
                    break :fields fields;
                };
                
                break :blk @Type(.{.Struct = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = true,
                }});
            };

            var to_iterate: TupleOfSlices = undefined;
            inline for (0..self.entities.len) |i| {
                to_iterate[i] = self.entities[i].items;
            }

            var iterator = toolkit.cartesian(to_iterate);
            
            while (iterator.next()) |entry| {
                @call(.auto, only_system, entry);
            }
        }
    };
}

fn ListToSlice(comptime List: type) type {
    return for (@typeInfo(List).Struct.fields) |f| {
        if (std.mem.eql(u8, f.name, "items")) break f.type;
    } else unreachable;
}
