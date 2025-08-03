const std = @import("std");
const StructField = std.builtin.Type.StructField;

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

// Reference for a value stored in ArrayList
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
