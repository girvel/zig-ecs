const std = @import("std");
const testing = std.testing;

// TODO handle ElementType changes s. a. in magnitude (int -> float), normalization (definitely
// int -> float), division (often int -> float)

pub fn Vector(comptime ElementType: type, comptime length: usize) type {
    return struct {
        items: @Vector(length, ElementType),

        const Self = @This();

        /// takes ownership
        pub fn from(items: [length]ElementType) Self {
            return Self { .items = items };
        }

        pub fn filled_with(value: ElementType) Self {
            return Self.from([_]ElementType{value} ** length);
        }

        pub inline fn add_mut(self: *Self, other: Self) void {
            self.items += other.items;
        }

        pub inline fn add(self: Self, other: Self) Self {
            var result = self;
            result.add_mut(other);
            return result;
        }

        pub inline fn sqr_magnitude(self: Self) ElementType {
            var sum: ElementType = 0;
            for (self.items) |e| {
                sum += e * e;
            }
            return sum;
        }

        // pub fn mul_mut(self: *Self, other: ElementType) void {
        //     for (&self.items) |*a| {
        //         a.* *= other;
        //     }
        // }

        // pub fn mul(self: Self, other: ElementType) Self {
        //     var result = self;
        //     result.mul_mut(other);
        //     return result;
        // }

        pub fn swizzle(self: Self, comptime literal: []const u8) Vector(ElementType, literal.len) {
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

            var result: Vector(ElementType, literal.len) = undefined;
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
    const v = Vector(i32, 3).from([_]i32{1, 2, 3});

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
    const v = Vector(i32, 3).from([_]i32{1, 2, 3});
    const u = v.swizzle("zxy");
    try testing.expect(u.items[0] == 3);
    try testing.expect(u.items[1] == 1);
    try testing.expect(u.items[2] == 2);

    const zero_sized = v.swizzle("");
    try testing.expect(zero_sized.items.len == 0);
}
