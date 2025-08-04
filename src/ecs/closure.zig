const std = @import("std");

pub fn New(comptime arg_types: []const type, comptime Return: type) type {
    const Args = std.meta.Tuple(arg_types);

    return struct {
        fn_pointer: *const fn(*anyopaque, Args) Return,
        payload: *anyopaque,
        allocator: std.mem.Allocator,
        deallocate: *const fn(std.mem.Allocator, *anyopaque) void,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, payload: anytype) !Self {
            const Payload = @TypeOf(payload);

            var result: Self = undefined;
            result.fn_pointer = (struct {
                fn call(local_payload: *anyopaque, args: Args) Return {
                    const payload_typed: *Payload = @ptrCast(@alignCast(local_payload));
                    const all_args = .{payload_typed} ++ args;
                    return @call(.auto, Payload.invoke, all_args);
                }
            }).call;

            const ptr = try allocator.create(Payload);
            ptr.* = payload;
            result.payload = ptr;

            result.allocator = allocator;
            result.deallocate = (struct {
                fn call(local_allocator: std.mem.Allocator, local_payload: *anyopaque) void {
                    const payload_typed: *Payload = @ptrCast(@alignCast(local_payload));
                    local_allocator.destroy(payload_typed);
                }
            }).call;

            return result;
        }

        pub fn deinit(self: Self) void {
            self.deallocate(self.allocator, self.payload);
        }

        pub fn invoke(self: *Self, args: Args) Return {
            return self.fn_pointer(self.payload, args);
        }
    };
}

fn analyze(comptime Implementation: type) type {
    const invoke_signature = @typeInfo(@TypeOf(Implementation.invoke)).@"fn";
    var arg_types: [invoke_signature.params.len - 1]type = undefined;
    for (&arg_types, 1..) |*Arg, i| {
        Arg.* = invoke_signature.params[i].type.?;
    }
    return New(&arg_types, invoke_signature.return_type.?);
}

pub fn init(
    allocator: std.mem.Allocator, implementation: anytype,
) !analyze(@TypeOf(implementation)) {
    return analyze(@TypeOf(implementation)).init(allocator, implementation);
}

test {
    const allocator = std.testing.allocator;

    const Base = struct {
        a: i32,
        pub fn invoke(self: *@This(), b: i32, c: i32) i32 {
            return b * b - 2 * self.a * c;
        }
    };
    const RequiredClosure = New(&.{i32, i32}, i32);
    
    var result: [10]RequiredClosure = undefined;
    for (&result, 0..) |*closure, i| {
        closure.* = try init(allocator, Base {
            .a = @intCast(i),
        });
    }
    defer for (result) |closure| {
        closure.deinit();
    };

    for (&result, 0..) |*closure, i| {
        const i_i32: i32 = @intCast(i);
        try std.testing.expectEqual(-2 * i_i32, closure.invoke(.{0, 1}));
    }
}
