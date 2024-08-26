const builtin = @import("builtin");

pub const epoll = switch (builtin.os.tag) {
    .linux => @import("epoll.zig"),
    else => void,
};

pub const kqueue = switch (builtin.os.tag) {
    .macos => @import("kqueue.zig"),
    else => void,
};
