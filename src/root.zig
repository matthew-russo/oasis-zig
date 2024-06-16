const std = @import("std");

pub const byte_buffer = @import("byte_buffer.zig");
pub const ring_buffer = @import("ring_buffer.zig");

/// a panicking function for stubbing out general todos
pub fn todo(msg: []const u8) noreturn {
    std.debug.panic("[TODO] not yet implemented: {s}", .{msg});
}

/// a panicking function for stubbing out error handling
pub fn errorHandlingPlaceholder(msg: []const u8) noreturn {
    std.debug.panic("[TODO] handle error: {s}", .{msg});
}

test {
    std.testing.refAllDecls(@This());
}
