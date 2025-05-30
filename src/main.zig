const std = @import("std");

fn inspect(object: anytype) void {
    const T = @TypeOf(object);
    const fields = @typeInfo(T).Struct.fields;

    inline for (fields) |field| {
        std.debug.print("{s}: {} = {any}\n", .{
            field.name,
            field.type,
            @field(object, field.name),
        });
    }

    std.debug.print("\n", .{});
}

pub fn main() !void {
    inspect(.{.hello = "world"});
    inspect(.{.x = 1, .y = 2, .name = "dummy"});
}
