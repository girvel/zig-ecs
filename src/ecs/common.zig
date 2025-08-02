pub const Component = struct {name: [:0]const u8, type: type};
pub const Trait = struct {type: type, components: []const Component};
