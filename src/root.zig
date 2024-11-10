const std = @import("std");

pub const collections = @import("collections/mod.zig");
pub const debug_formatter = @import("debug_formatter.zig");
pub const interaction = @import("interaction/mod.zig");
pub const net = @import("net/mod.zig");
pub const os = @import("os/mod.zig");
pub const time = @import("time.zig");

/// a panicking function for stubbing out general todos
pub fn todo(msg: []const u8) noreturn {
    std.debug.panic("[TODO] not yet implemented: {s}", .{msg});
}

/// a panicking function for stubbing out error handling
pub fn errorHandlingPlaceholder(msg: []const u8) noreturn {
    std.debug.panic("[TODO] handle error: {s}", .{msg});
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
