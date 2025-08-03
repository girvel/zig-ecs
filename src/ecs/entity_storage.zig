const common = @import("common.zig");
const std = @import("std");

pub fn New(comptime entity_types: []const type) type {
    const EntityLists = comptime blk: {
        var types: [entity_types.len]type = undefined;
        for (&types, entity_types) |*List, Entity| {
            List.* = std.ArrayList(Entity);
        }
        break :blk std.meta.Tuple(&types);
    };

    return struct {
        lists: EntityLists,
        flushed_lengths: [entity_types.len]usize,

        pub const requirements = blk: {
            var result: [entity_types.len]common.Requirement = undefined;
            for (&result, entity_types) |*requirement, Entity| {
                const fields = @typeInfo(Entity).@"struct".fields;
                var components: [fields.len]common.Component = undefined;
                for (&components, fields) |*component, field| {
                    component.* = .{
                        // TODO error -> @compileError if not a pointer
                        .type = @typeInfo(field.type).@"pointer".child,
                        .name = field.name,
                    };
                }
                const components_const = components;
                requirement.* = .{
                    .components = &components_const,
                    .type = Entity,
                };
            }
            break :blk result;
        };

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            inline for (0.., entity_types) |i, Entity| {
                result.lists[i] = std.ArrayList(Entity).init(allocator);
                result.flushed_lengths[i] = 0;
            }
            return result;
        }

        pub fn plan_add(
            self: *Self, entity: anytype, component_storage: anytype, creation_queue: anytype
        ) void {
            inline for (0.., requirements) |i, requirement| {
                inline for (requirement.components) |component| {
                    if (!@hasField(@TypeOf(entity), component.name)) break;
                } else {
                    var subject: requirement.type = undefined;
                    inline for (requirement.components) |component| {
                        const storage_slice = @field(component_storage, component.name).items;
                        const queue = @field(creation_queue, component.name).items;
                        @field(subject, component.name)
                            = &storage_slice.ptr[storage_slice.len + queue.len - 1];
                    }
                    self.lists[i].append(subject) catch unreachable;
                }
            }
        }

        pub fn flush_add(self: *Self) void {
            inline for (&self.flushed_lengths, self.lists) |*len, list| {
                len.* = list.items.len;
            }
        }

        pub fn shift_pointers(
            self: *Self, comptime dangling_component: [:0]const u8, delta: isize
        ) void {
            inline for (requirements, 0..) |requirement, i| {
                inline for (requirement.components) |component| {
                    const is_component_found = comptime std.mem.eql(
                        u8, component.name, dangling_component
                    );
                    if (!is_component_found) continue;

                    for (self.lists[i].items) |*e| {
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
            try writer.print("    - EntityStorage:\n", .{});
            inline for (requirements, self.flushed_lengths, self.lists) |trait, len, list| {
                try writer.print("      - {}: {}/{}\n", .{trait.type, len, list.items.len});
            }
        }
    };
}
