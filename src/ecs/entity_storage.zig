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
                    // TODO! handle type mismatch?
                    // TODO! handle optional fields
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

        pub fn cartesian(self: *Self) Cartesian(Self) {
            return .{
                .storage = self,
            };
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype
        ) !void {
            _ = fmt;
            _ = options;
            inline for (requirements, self.flushed_lengths, self.lists) |trait, len, list| {
                try writer.print("    - {}: {}/{}\n", .{trait.type, len, list.items.len});
            }
        }
    };
}

fn Cartesian(comptime EntityStorage: type) type {
    const len = EntityStorage.requirements.len;
    const IteratorReturn = blk: {
        var fs: [len]type = undefined;
        for (&fs, EntityStorage.requirements) |*f, requirement| {
            f.* = requirement.type;
        }
        break :blk std.meta.Tuple(&fs);
    };
    
    return struct {
        storage: *EntityStorage,
        indices: [len]usize = [_]usize{0} ** len,
        finished: bool = false,

        pub fn next(self: *@This()) ?IteratorReturn {
            if (self.finished) return null;

            var result: IteratorReturn = undefined;
            inline for (&result, self.indices, self.storage.lists) |*field, i, list| {
                field.* = list.items[i];
            }

            inline for (&self.indices, self.storage.flushed_lengths) |*i, flushed_len| {
                i.* += 1;
                if (i.* < flushed_len) break;
                i.* = 0;
            } else {
                self.finished = true;
            }

            return result;
        }
    };
}

// test {
//     const slice1 = ([_]i32{1, 2, 3})[0..];
//     const slice2 = ([_]f64{3.14, 2.72})[0..];
// 
//     const result = [_]struct {i32, f64} {
//         .{1, 3.14},
//         .{2, 3.14},
//         .{3, 3.14},
//         .{1, 2.72},
//         .{2, 2.72},
//         .{3, 2.72},
//     };
//     
//     const lengths = [_]usize{3, 2};
// 
//     var it = cartesian(.{slice1, slice2}, lengths);
//     var i: usize = 0;
//     while (it.next()) |entry| {
//         try std.testing.expect(entry[0] == result[i][0]);
//         try std.testing.expect(entry[1] == result[i][1]);
//         i += 1;
//     }
// }
