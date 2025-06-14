const std = @import("std");
const testing = std.testing;

pub fn Vector(comptime element_type: type, comptime length: usize) type {
    return struct {
        items: [length]element_type,

        const Self = @This();

        pub fn from_array(items: [length]element_type) Self {
            return Self { .items = items };
        }

        pub fn filled_with(value: element_type) Self {
            return Self {
                .items = [_]element_type{value} ** length,
            };
        }

        pub fn add_mut(self: *Self, other: Self) void {
            std.debug.print("{} + {}\n", .{self, other});
            for (&self.items, other.items) |*a, b| {
                a.* += b;
            }
        }

        pub fn add(self: Self, other: Self) Self {
            var result = self;
            result.add_mut(other);
            return result;
        }

        pub fn swizzle(self: Self, comptime literal: []const u8) Vector(element_type, literal.len) {
            const indices = comptime blk: {
                var result: [literal.len]usize = undefined;
                if (literal.len == 0) break :blk result;

                const base = if (literal[0] > 'x') "xyzw" else "rgba";
                for (&result, literal) |*index, char| {
                    index.* = std.mem.indexOfScalar(u8, base, char) orelse @compileError(
                        "Swizzle character '" ++ &[_]u8{char} ++ "' is not in base \""
                        ++ base ++ "\""
                    );
                }
                break :blk result;
            };

            var result = Vector(element_type, literal.len) {
                .items = undefined,
            };

            for (0..literal.len) |i| {
                result.items[i] = self.items[indices[i]];
            }
            return result;
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("(", .{});
            inline for (0.., self.items) |i, item| {
                try writer.print(
                    (if (i > 0) ", " else "") ++ "{}",
                    .{item},
                );
            }
            try writer.print(")", .{});
        }
    };
}

test "initialization" {
    const v = Vector(i32, 3).from_array([_]i32{1, 2, 3});

    try testing.expect(v.items[0] == 1);
    try testing.expect(v.items[1] == 2);
    try testing.expect(v.items[2] == 3);
}

test "zero vector" {
    const v = Vector(i32, 5).filled_with(0);

    for (v.items) |e| {
        try testing.expect(e == 0);
    }
}

test "addition" {
    var v = Vector(i32, 3) {
        .items = [_]i32{1, 2, 3},
    };

    const u = Vector(i32, 3) {
        .items = [_]i32{3, 2, 3},
    };

    v.add_mut(u);

    try testing.expect(v.items[0] == 4);
    try testing.expect(v.items[1] == 4);
    try testing.expect(v.items[2] == 6);
}

test "addition (without mutation)" {
    const v = Vector(i32, 3) {
        .items = [_]i32{1, 2, 3},
    };

    const u = Vector(i32, 3) {
        .items = [_]i32{3, 2, 3},
    };

    const result = v.add(u);

    try testing.expect(result.items[0] == 4);
    try testing.expect(result.items[1] == 4);
    try testing.expect(result.items[2] == 6);
}

test "swizzling" {
    const v = Vector(i32, 3).from_array([_]i32{1, 2, 3});
    const u = v.swizzle("zxy");
    try testing.expect(u.items[0] == 3);
    try testing.expect(u.items[1] == 1);
    try testing.expect(u.items[2] == 2);

    const zero_sized = v.swizzle("");
    try testing.expect(zero_sized.items.len == 0);
}
