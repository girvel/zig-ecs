const entity_storage = @import("entity_storage.zig");
const common = @import("common.zig");
const toolkit = @import("../toolkit.zig");
const std = @import("std");

pub const Threading = union(enum) {
    none,
    batch_based: struct {
        argument_i: usize,
        batch_size: usize,
    },
};

// TODO! make this type internal only
pub fn System(comptime system_fn: anytype, threading: Threading) type {
    return struct {
        pub const EntityStorage = entity_storage.New(&param_types: {
            const params = @typeInfo(@TypeOf(system_fn)).@"fn".params;
            var result: [params.len]type = undefined;
            for (&result, params) |*Target, param| {
                Target.* = param.type.?;
            }
            const result_const = result;
            break :param_types result_const;
        });

        targets: EntityStorage,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            var result: Self = undefined;
            result.targets = EntityStorage.init(allocator);
            result.allocator = allocator;
            return result;
        }

        pub fn plan_add(
            self: *Self, entity: anytype, component_storage: anytype, creation_queue: anytype
        ) void {
            self.targets.plan_add(entity, component_storage, creation_queue);
        }

        pub fn flush_add(self: *Self) void {
            self.targets.flush_add();
        }

        pub fn shift_pointers(
            self: *Self, comptime dangling_component: [:0]const u8, delta: isize
        ) void {
            self.targets.shift_pointers(dangling_component, delta);
        }

        pub fn update(self: *Self) void {
            //const cpu_n = std.Thread.getCpuCount() catch unreachable;
            switch (threading) {
                .none => {
                    update_system(system_fn, &self.targets);
                },

                .batch_based => |threading_config| {
                    _ = threading_config;
                    unreachable;
                    // TODO! revive batch-based using new .cartesian

                    // var pool: std.Thread.Pool = undefined;
                    // pool.init(.{.allocator = self.allocator}) catch unreachable;
                    // defer pool.deinit();

                    // const batches_n = std.math.divCeil(
                    //     usize,
                    //     self.targets.lists[threading_config.argument_i].items.len,
                    //     threading_config.batch_size,
                    // ) catch unreachable;

                    // for (0..batches_n) |batch_i| {
                    //     var to_iterate: TupleOfSlices = undefined;
                    //     var active_lengths = self.targets.flushed_lengths;
                    //     inline for (0..self.targets.lists.len) |argument_i| {
                    //         if (argument_i == threading_config.argument_i) {
                    //             const slice = self.targets.lists[argument_i].items;
                    //             to_iterate[argument_i] = slice[
                    //                 threading_config.batch_size * batch_i / cpu_n..
                    //                 @min(
                    //                     threading_config.batch_size * (batch_i + 1) / cpu_n,
                    //                     self.targets.flushed_lengths[argument_i] - 1,
                    //                 )
                    //             ];
                    //             active_lengths[argument_i] = to_iterate[argument_i].len;
                    //         } else {
                    //             to_iterate[argument_i] = self.targets.lists[argument_i].items;
                    //         }
                    //     }

                    //     pool.spawn(update_system, .{
                    //         system_fn,
                    //         to_iterate,
                    //         active_lengths,
                    //     }) catch unreachable;
                    // }
                },
            }
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("- Targets:\n{}\n", .{self.targets});
        }
    };
}

fn update_system(system_fn: anytype, targets: anytype) void {
    var iterator = targets.cartesian();
    while (iterator.next()) |entry| {
        @call(.auto, system_fn, entry);
    }
}

