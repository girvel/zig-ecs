pub const Component = struct {name: [:0]const u8, type: type};
pub const Requirement = struct {type: type, components: []const Component};
