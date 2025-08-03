const std = @import("std");
const StructField = std.builtin.Type.StructField;

fn Cartesian(comptime slice_types: type) type {
    const slice_tuple_fields = @typeInfo(slice_types).@"struct".fields;
    const len = slice_tuple_fields.len;
    const IteratorReturn = blk: {
        var fs: [len]type = undefined;
        for (&fs, slice_tuple_fields) |*f, field| {
            f.* = @typeInfo(field.type).pointer.child;
            switch (@typeInfo(f.*)) {
                .array => |Array| {
                    f.* = Array.child;
                },
                else => {},
            }
        }
        break :blk std.meta.Tuple(&fs);
    };
    
    return struct {
        slices: slice_types,
        lengths: [len]usize,
        indices: [len]usize,
        finished: bool = false,

        pub fn next(self: *@This()) ?IteratorReturn {
            if (self.finished) return null;

            var result: IteratorReturn = undefined;
            inline for (&result, self.indices, self.slices) |*field, i, slice| {
                field.* = slice[i];
            }

            inline for (&self.indices, self.lengths) |*i, slice_len| {
                i.* += 1;
                if (i.* < slice_len) break;
                i.* = 0;
            } else {
                self.finished = true;
            }

            return result;
        }
    };
}

pub fn cartesian(slices: anytype, lengths: [slices.len]usize) Cartesian(@TypeOf(slices)) {
    return .{
        .slices = slices,
        .lengths = lengths,
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
                .default_value_ptr = null,
                .is_comptime = false,
            };
        }
        break :blk result;
    };

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &result_fields,
        .decls = &.{},
        .is_tuple = false,
    }});
}

pub fn Promise(comptime T: type) type {
    return struct {
        callback: ?fn (T) void = null,
        const Self = @This();
        pub fn then(self: *Self, callback: fn (T) void) void {
            if (self.callback != null) @panic(".then on promise that already has been .then-ed");
            self.callback = callback;
        }

        pub fn resolve(self: Self, value: T) void {
            if (self.callback == null) return;
            self.callback(value);
        }
    };
}
