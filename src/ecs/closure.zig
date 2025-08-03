const std = @import("std");

pub fn Closure(comptime Argument: type, comptime Return: type) type {
    // @Type(.{ .@"fn" = .{
    //     .calling_convention = .auto,
    //     .is_generic = false,
    //     .is_var_args = false,
    //     .return_type = Return,
    //     .params = 
    // }});
    return struct {
        fn_pointer: *const fn(*anyopaque, Argument) Return,
        payload: *anyopaque,
        allocator: std.mem.Allocator,
        deallocate: *const fn(std.mem.Allocator, *anyopaque) void,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, payload: anytype) !Self {
            const Payload = @TypeOf(payload);

            var result: Self = undefined;
            result.fn_pointer = (struct {
                fn call(local_payload: *anyopaque, argument: Argument) Return {
                    const payload_typed: *Payload = @ptrCast(@alignCast(local_payload));
                    return Payload.invoke(payload_typed, argument);
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

        pub fn invoke(self: *Self, argument: Argument) Return {
            return self.fn_pointer(self.payload, argument);
        }
    };
}

test {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const Base = struct {
        a: i32,
        b: i32,
        pub fn invoke(self: *@This(), c: i32) i32 {
            return self.b * self.b - 2 * self.a * c;
        }
    };
    const RequiredClosure = Closure(i32, i32);
    
    var result: [10]RequiredClosure = undefined;
    for (&result, 0..) |*closure, i| {
        closure.* = try RequiredClosure.init(allocator, Base {
            .a = @intCast(i),
            .b = 0,
        });
    }
    defer for (result) |closure| {
        closure.deinit();
    };

    for (&result, 0..) |*closure, i| {
        const i_i32: i32 = @intCast(i);
        try std.testing.expectEqual(-2 * i_i32, closure.invoke(1));
    }
}
