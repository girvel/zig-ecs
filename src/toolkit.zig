const std = @import("std");
const StructField = std.builtin.Type.StructField;

fn Cartesian(comptime slice_types: type) type {
    const slice_tuple_fields = @typeInfo(slice_types).Struct.fields;
    const len = slice_tuple_fields.len;
    const IteratorReturn = blk: {
        const fields = fields: {
            var fs: [len]StructField = undefined;
            for (slice_tuple_fields, 0..) |field, i| {
                var T = @typeInfo(field.type).Pointer.child;
                switch (@typeInfo(T)) {
                    .Array => |Array| {
                        T = Array.child;
                    },
                    else => {},
                }
                fs[i] = .{
                    .name = std.fmt.comptimePrint("{}", .{i}),
                    .type = T,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(T),
                };
            }
            break :fields fs;
        };

        break :blk @Type(.{ .Struct = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        }});
    };
    
    return struct {
        slices: slice_types,
        indices: [len]usize,
        finished: bool = false,

        pub fn next(self: *@This()) ?IteratorReturn {
            if (self.finished) return null;

            var result: IteratorReturn = undefined;
            inline for (&result, self.indices, self.slices) |*field, i, slice| {
                field.* = slice[i];
            }

            inline for (&self.indices, self.slices) |*i, slice| {
                i.* += 1;
                if (i.* < slice.len) break;
                i.* = 0;
            } else {
                self.finished = true;
            }

            return result;
        }
    };
}

pub fn cartesian(slices: anytype) Cartesian(@TypeOf(slices)) {
    return .{
        .slices = slices,
        .indices = [_]usize {0} ** slices.len,
    };
}

test {
    const slice1 = ([_]i32{1, 2, 3})[0..];
    const slice2 = ([_]f64{3.14, 2.72})[0..];

    const result = [_]struct {i32, f64} {
        .{1, 3.14},
        .{2, 3.14},
        .{3, 3.14},
        .{1, 2.72},
        .{2, 2.72},
        .{3, 2.72},
    };

    var it = cartesian(.{slice1, slice2});
    var i: usize = 0;
    while (it.next()) |entry| {
        try std.testing.expect(entry[0] == result[i][0]);
        try std.testing.expect(entry[1] == result[i][1]);
        i += 1;
    }
}

pub const Field = struct {name: [:0]const u8, type: type};

pub fn Struct(fields: []Field) type {
    const result_fields = blk: {
        var result: [fields.len]StructField = undefined;
        for (&result, fields) |*r, f| {
            r.* = .{
                .name = f.name,
                .type = f.type,
                .alignment = @alignOf(f.type),
                .default_value = null,
                .is_comptime = false,
            };
        }
        break :blk result;
    };

    return @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = &result_fields,
        .decls = &.{},
        .is_tuple = false,
    }});
}
