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
