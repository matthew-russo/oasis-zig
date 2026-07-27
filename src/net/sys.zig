const std = @import("std");
const c = std.c;
const posix = std.posix;

/// Thin wrappers over the libc socket/fd syscalls.
///
/// Zig 0.16 removed the ergonomic `std.posix.socket`/`bind`/`accept`/... helpers
/// (networking migrated onto the `std.Io` interface). These reimplement the small
/// slice of behavior the TCP server depended on directly against the raw `std.c`
/// bindings, preserving the old error-union call sites.

pub const ReadError = error{ WouldBlock, ReadFailed };
pub const AcceptError = error{ WouldBlock, AcceptFailed };

pub fn socket(domain: u32, sock_type: u32, protocol: u32) error{SocketFailed}!posix.socket_t {
    const rc = c.socket(@intCast(domain), @intCast(sock_type), @intCast(protocol));
    if (rc == -1) return error.SocketFailed;
    return @intCast(rc);
}

pub fn bind(fd: posix.socket_t, addr: *const posix.sockaddr, len: posix.socklen_t) error{BindFailed}!void {
    if (c.bind(fd, addr, len) == -1) return error.BindFailed;
}

pub fn listen(fd: posix.socket_t, backlog: u31) error{ListenFailed}!void {
    if (c.listen(fd, @intCast(backlog)) == -1) return error.ListenFailed;
}

pub fn getsockname(fd: posix.socket_t, addr: *posix.sockaddr, len: *posix.socklen_t) error{GetSockNameFailed}!void {
    if (c.getsockname(fd, addr, len) == -1) return error.GetSockNameFailed;
}

pub fn connect(fd: posix.socket_t, addr: *const posix.sockaddr, len: posix.socklen_t) error{ConnectFailed}!void {
    if (c.connect(fd, addr, len) == -1) return error.ConnectFailed;
}

/// Accept a connection, returning a non-blocking, close-on-exec socket to match
/// the flags the old `std.posix.accept(..., SOCK.CLOEXEC | SOCK.NONBLOCK)` set.
/// BSD `accept` takes no flags argument, so they are applied via `fcntl`.
pub fn accept(fd: posix.socket_t, addr: *posix.sockaddr, len: *posix.socklen_t) AcceptError!posix.socket_t {
    const rc = c.accept(fd, addr, len);
    if (rc == -1) {
        return switch (posix.errno(rc)) {
            .AGAIN => error.WouldBlock,
            else => error.AcceptFailed,
        };
    }
    const new_fd: posix.socket_t = @intCast(rc);
    setCloexecNonblock(new_fd) catch return error.AcceptFailed;
    return new_fd;
}

pub fn read(fd: posix.socket_t, buf: []u8) ReadError!usize {
    const rc = c.read(fd, buf.ptr, buf.len);
    if (rc == -1) {
        return switch (posix.errno(rc)) {
            .AGAIN => error.WouldBlock,
            else => error.ReadFailed,
        };
    }
    return @intCast(rc);
}

pub fn write(fd: posix.socket_t, buf: []const u8) error{WriteFailed}!usize {
    const rc = c.write(fd, buf.ptr, buf.len);
    if (rc == -1) return error.WriteFailed;
    return @intCast(rc);
}

pub fn close(fd: posix.socket_t) void {
    _ = c.close(fd);
}

/// Set both `O_NONBLOCK` (file status) and `FD_CLOEXEC` (descriptor flag) on `fd`.
pub fn setCloexecNonblock(fd: posix.socket_t) error{FcntlFailed}!void {
    const nonblock: c_int = @bitCast(@as(u32, @bitCast(c.O{ .NONBLOCK = true })));
    const flags = c.fcntl(fd, c.F.GETFL, @as(c_int, 0));
    if (flags == -1) return error.FcntlFailed;
    if (c.fcntl(fd, c.F.SETFL, flags | nonblock) == -1) return error.FcntlFailed;
    if (c.fcntl(fd, c.F.SETFD, @as(c_int, c.FD_CLOEXEC)) == -1) return error.FcntlFailed;
}
