const builtin = @import("builtin");

pub const async_tcp_server = switch (builtin.os.tag) {
    .macos => @import("kqueue_tcp_server.zig"),
    else => void,
};
