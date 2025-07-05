const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;

const collections = @import("../collections/mod.zig");

const epoll = switch (builtin.os.tag) {
    .linux => @import("../os/epoll.zig"),
    else => void,
};

const kqueue = switch (builtin.os.tag) {
    .macos => @import("../os/kqueue.zig"),
    else => void,
};

pub const TcpConnectionHandler = struct {
    const Self = @This();

    ptr: *anyopaque,

    pollFn: *const fn (
        *anyopaque,
        *collections.byte_buffer.ByteBuffer,
        *collections.byte_buffer.ByteBuffer,
    ) void,

    pub fn init(ptr: anytype) Self {
        const Ptr = @TypeOf(ptr);
        const ptr_info = @typeInfo(Ptr);

        if (ptr_info != .pointer) @compileError("ptr must be a pointer");
        if (ptr_info.pointer.size != .one) @compileError("ptr must be a single item pointer");

        const gen = struct {
            pub fn pollImpl(
                pointer: *anyopaque,
                read_buffer: *collections.byte_buffer.ByteBuffer,
                write_buffer: *collections.byte_buffer.ByteBuffer,
            ) void {
                const self: Ptr = @ptrCast(@alignCast(pointer));
                @call(
                    .always_inline,
                    ptr_info.pointer.child.poll,
                    .{ self, read_buffer, write_buffer },
                );
            }
        };

        return .{
            .ptr = ptr,
            .pollFn = gen.pollImpl,
        };
    }

    pub fn poll(
        self: *Self,
        read_buffer: *collections.byte_buffer.ByteBuffer,
        write_buffer: *collections.byte_buffer.ByteBuffer,
    ) void {
        self.pollFn(self.ptr, read_buffer, write_buffer);
    }
};

pub const TcpConnection = struct {
    const Self = @This();

    read_buffer: collections.byte_buffer.ByteBuffer,
    write_buffer: collections.byte_buffer.ByteBuffer,

    handler: TcpConnectionHandler,

    pub fn init(allocator: std.mem.Allocator, handler: TcpConnectionHandler) Self {
        return Self{
            .read_buffer = collections.byte_buffer.ByteBuffer.init(allocator),
            .write_buffer = collections.byte_buffer.ByteBuffer.init(allocator),
            .handler = handler,
        };
    }

    pub fn deinit(self: *Self) void {
        self.read_buffer.deinit();
        self.write_buffer.deinit();
    }

    pub fn poll(self: *Self) void {
        self.handler.poll(&self.read_buffer, &self.write_buffer);
    }
};

pub const TcpServerContext = struct {
    allocator: Allocator,

    handler: TcpConnectionHandler,

    // The address that the TcpServer is bound to
    address: std.net.Address,

    // The current active connections, keyed by their file descriptor
    conns: std.AutoHashMap(usize, TcpConnection),
};

pub const KqueueTcpServer = struct {
    const Self = @This();

    allocator: Allocator,

    kqueue: kqueue.KqueuePoller,

    ctx: *TcpServerContext,

    pub fn init(allocator: Allocator, address: std.net.Address, handler: TcpConnectionHandler) Self {
        const ctx = allocator.create(TcpServerContext) catch unreachable;
        ctx.* = TcpServerContext{
            .allocator = allocator,
            .handler = handler,
            .address = address,
            .conns = std.AutoHashMap(usize, TcpConnection).init(allocator),
        };
        return Self{
            .allocator = allocator,
            .kqueue = kqueue.KqueuePoller.init(allocator),
            .ctx = ctx,
        };
    }

    pub fn deinit(self: *Self) void {
        self.join();

        var value_iter = self.ctx.conns.valueIterator();
        while (value_iter.next()) |conn| {
            conn.deinit();
        }

        self.ctx.conns.deinit();
        self.allocator.destroy(self.ctx);
        self.kqueue.deinit();
    }

    pub fn serve(self: *Self) !void {
        const sock_flags: u32 = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK;
        const sockfd: std.posix.socket_t = try std.posix.socket(std.os.linux.AF.INET, sock_flags, std.posix.IPPROTO.TCP);

        const max_conns: u31 = 128;

        var socklen: std.posix.socklen_t = self.ctx.address.getOsSockLen();
        try std.posix.bind(sockfd, &self.ctx.address.any, socklen);
        try std.posix.listen(sockfd, max_conns);
        try std.posix.getsockname(sockfd, &self.ctx.address.any, &socklen);

        const pair = kqueue.KqueuePair{
            .ident = @intCast(sockfd),
            .filter = std.posix.system.EVFILT.READ,
        };
        const handler = kqueue.KqueueHandler.init(self.ctx, Self.handleAcceptSocket);
        self.kqueue.addHandler(pair, 0, handler);

        self.kqueue.spawn();
    }

    pub fn join(self: *Self) void {
        self.kqueue.join();
    }

    fn handleAcceptSocket(
        poller: *kqueue.KqueuePollerHandle,
        kevent: std.posix.Kevent,
        context: ?*anyopaque,
    ) void {
        const maybe_ctx: ?*TcpServerContext = @ptrCast(@alignCast(context));
        if (maybe_ctx) |ctx| {
            // std.debug.print("\n[Server] new connection!", .{});
            // a new conn is waiting to be accepted
            var accepted_addr: std.net.Address = undefined;
            var addr_len = ctx.address.getOsSockLen();
            if (std.posix.accept(@intCast(kevent.ident), &accepted_addr.any, &addr_len, std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK)) |new_conn_sock| {
                const conn = TcpConnection.init(ctx.allocator, ctx.handler);

                const read_pair = kqueue.KqueuePair{
                    .ident = @intCast(new_conn_sock),
                    .filter = std.posix.system.EVFILT.READ,
                };
                const read_handler = kqueue.KqueueHandler.init(ctx, Self.handleReadableDataSocket);
                poller.addHandler(read_pair, 0, read_handler);

                const write_pair = kqueue.KqueuePair{
                    .ident = @intCast(new_conn_sock),
                    .filter = std.posix.system.EVFILT.WRITE,
                };
                const write_handler = kqueue.KqueueHandler.init(ctx, Self.handleWritableDataSocket);
                poller.addHandler(write_pair, 0, write_handler);

                ctx.conns.put(@intCast(new_conn_sock), conn) catch unreachable;
            } else |err| switch (err) {
                error.WouldBlock => {
                    std.debug.panic("[Server] kqueue said socket was ready but os is saying it would block", .{});
                },
                else => unreachable,
            }
        } else {
            std.debug.panic("\n[Server::handleAcceptSocket] context was null", .{});
        }
    }

    fn handleReadableDataSocket(
        _: *kqueue.KqueuePollerHandle,
        kevent: std.posix.Kevent,
        context: ?*anyopaque,
    ) void {
        const maybe_ctx: ?*const TcpServerContext = @ptrCast(@alignCast(context));
        if (maybe_ctx) |ctx| {
            var read_buf: [4096]u8 = undefined;

            // std.debug.print("\n[Server::handleReadableDataSocket] existing conn ready!", .{});
            // an existing conn has some data available
            if (ctx.conns.getPtr(kevent.ident)) |conn| {
                if (kevent.flags == std.c.EV.EOF) {
                    std.posix.close(@intCast(kevent.ident));
                    return;
                }

                // std.debug.print("\n[Server::handleReadableDataSocket] existing conn ready for reads!. EofFlag set: {any}", .{kevent.flags == std.c.EV.EOF});
                var amount_read: usize = 0;

                while (amount_read < kevent.data) {
                    if (std.posix.read(@intCast(kevent.ident), read_buf[0..])) |bytes_read| {
                        amount_read += bytes_read;
                        _ = conn.read_buffer.append(read_buf[0..amount_read]) catch unreachable;
                    } else |err| {
                        if (err == std.posix.ReadError.WouldBlock) {
                            std.debug.panic("\n[Server::handleReadableDataSocket] sockfd({any}) return EAGAIN", .{kevent.ident});
                        } else {
                            std.debug.panic("\n[Server::handleReadableDataSocket] sockfd({any}) returned unexpected err: {any}", .{ kevent.ident, err });
                        }
                    }
                }

                if (amount_read == 0) {
                    std.posix.close(@intCast(kevent.ident));
                    // TODO [matthew-russo 08-23-24] does this need to be removed from the kqueue?
                    return;
                }

                conn.poll();

                while (conn.write_buffer.getSlice(std.math.maxInt(usize))) |slice| {
                    // std.debug.print("[Server::handleReadableDataSocket] writing bytes out: {any}", .{slice});
                    _ = std.posix.write(@intCast(kevent.ident), slice) catch unreachable;
                }
            }
        } else {
            std.debug.panic("\n[Server::handleReadableDataSocket] context was null", .{});
        }
    }

    fn handleWritableDataSocket(
        _: *kqueue.KqueuePollerHandle,
        kevent: std.posix.Kevent,
        context: ?*anyopaque,
    ) void {
        const maybe_ctx: ?*const TcpServerContext = @ptrCast(@alignCast(context));
        if (maybe_ctx) |ctx| {
            // std.debug.print("\n[Server::handleWritableDataSocket] existing conn ready!", .{});
            // an existing conn has some data available
            if (ctx.conns.getPtr(kevent.ident)) |conn| {
                // std.debug.print("\n[Server::handleWritableDataSocket] existing conn ready for writes!", .{});
                if (conn.write_buffer.isEmpty()) {} else {
                    // std.debug.print("\n[Server::handleWritableDataSocket] conn got evfilt_write readiness but has nothing to write", .{});
                }
            }
        } else {
            std.debug.panic("\n[Server::handleWritableDataSocket] context was null", .{});
        }
    }
};

pub const EpollTcpServer = struct {
    const Self = @This();

    allocator: Allocator,

    epoller: epoll.Epoller,

    ctx: *TcpServerContext,

    pub fn init(allocator: Allocator, address: std.net.Address, handler: TcpConnectionHandler) Self {
        const ctx = allocator.create(TcpServerContext) catch unreachable;
        ctx.* = TcpServerContext{
            .allocator = allocator,
            .handler = handler,
            .address = address,
            .conns = std.AutoHashMap(usize, TcpConnection).init(allocator),
        };
        return Self{
            .allocator = allocator,
            .epoller = epoll.Epoller.init(allocator),
            .ctx = ctx,
        };
    }

    pub fn deinit(self: *Self) void {
        self.join();

        var value_iter = self.ctx.conns.valueIterator();
        while (value_iter.next()) |conn| {
            conn.deinit();
        }

        self.ctx.conns.deinit();
        self.allocator.destroy(self.ctx);
        self.epoller.deinit();
    }

    pub fn serve(self: *Self) !void {
        const sock_flags: u32 = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK;
        const sockfd: std.posix.socket_t = try std.posix.socket(std.os.linux.AF.INET, sock_flags, std.posix.IPPROTO.TCP);

        const max_conns: u31 = 128;

        var socklen: std.posix.socklen_t = self.ctx.address.getOsSockLen();
        try std.posix.bind(sockfd, &self.ctx.address.any, socklen);
        try std.posix.listen(sockfd, max_conns);
        try std.posix.getsockname(sockfd, &self.ctx.address.any, &socklen);

        const handler = epoll.EpollHandler.init(self.ctx, Self.handleAcceptSocket);
        try self.epoller.addHandler(sockfd, std.os.linux.EPOLL.IN, handler);

        self.epoller.spawn();
    }

    pub fn join(self: *Self) void {
        self.epoller.join();
    }

    fn handleAcceptSocket(
        epoller: *epoll.EpollerHandle,
        event: std.os.linux.epoll_event,
        context: ?*anyopaque,
    ) void {
        const maybe_ctx: ?*TcpServerContext = @ptrCast(@alignCast(context));
        if (maybe_ctx) |ctx| {
            // std.debug.print("\n[Server] new connection!", .{});
            // a new conn is waiting to be accepted
            var accepted_addr: std.net.Address = undefined;
            var addr_len = ctx.address.getOsSockLen();
            if (std.posix.accept(event.data.fd, &accepted_addr.any, &addr_len, std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK)) |new_conn_sock| {
                const conn = TcpConnection.init(ctx.allocator, ctx.handler);

                const read_handler = epoll.EpollHandler.init(ctx, Self.handleReadableDataSocket);
                epoller.addHandler(new_conn_sock, std.os.linux.EPOLL.IN, read_handler) catch unreachable;

                const write_handler = epoll.EpollHandler.init(ctx, Self.handleWritableDataSocket);
                epoller.addHandler(new_conn_sock, std.os.linux.EPOLL.OUT, write_handler) catch unreachable;

                ctx.conns.put(@intCast(new_conn_sock), conn) catch unreachable;
            } else |err| switch (err) {
                error.WouldBlock => {
                    std.debug.panic("[Server] kqueue said socket was ready but os is saying it would block", .{});
                },
                else => unreachable,
            }
        } else {
            std.debug.panic("\n[Server::handleAcceptSocket] context was null", .{});
        }
    }

    fn handleReadableDataSocket(
        _: *epoll.EpollerHandle,
        event: std.os.linux.epoll_event,
        context: ?*anyopaque,
    ) void {
        const maybe_ctx: ?*const TcpServerContext = @ptrCast(@alignCast(context));
        if (maybe_ctx) |ctx| {
            var read_buf: [4096]u8 = undefined;

            // std.debug.print("\n[Server::handleReadableDataSocket] existing conn ready!", .{});
            // an existing conn has some data available
            if (ctx.conns.getPtr(@intCast(event.data.fd))) |conn| {
                // std.debug.print("\n[Server::handleReadableDataSocket] existing conn ready for reads!", .{});
                var amount_read: usize = 0;

                while (true) {
                    if (std.posix.read(@intCast(event.data.fd), read_buf[0..])) |bytes_read| {
                        if (bytes_read == 0) {
                            break;
                        }
                        amount_read += bytes_read;
                        _ = conn.read_buffer.append(read_buf[0..amount_read]) catch unreachable;
                    } else |err| {
                        if (err == std.posix.ReadError.WouldBlock) {
                            std.debug.panic("\n[Server::handleReadableDataSocket] sockfd({any}) return EAGAIN", .{event.data.fd});
                        } else {
                            std.debug.panic("\n[Server::handleReadableDataSocket] sockfd({any}) returned unexpected err: {any}", .{ event.data.fd, err });
                        }
                    }
                }

                if (amount_read == 0) {
                    // read() returning 0 is EOF
                    std.posix.close(@intCast(event.data.fd));
                    // TODO [matthew-russo 08-23-24] does this need to be removed from epoll?
                    return;
                }

                conn.poll();

                while (conn.write_buffer.getSlice(std.math.maxInt(usize))) |slice| {
                    // std.debug.print("[Server::handleReadableDataSocket] writing bytes out: {any}", .{slice});
                    _ = std.posix.write(@intCast(event.data.fd), slice) catch unreachable;
                }
            }
        } else {
            std.debug.panic("\n[Server::handleReadableDataSocket] context was null", .{});
        }
    }

    fn handleWritableDataSocket(
        _: *epoll.EpollerHandle,
        event: std.os.linux.epoll_event,
        context: ?*anyopaque,
    ) void {
        const maybe_ctx: ?*const TcpServerContext = @ptrCast(@alignCast(context));
        if (maybe_ctx) |ctx| {
            // std.debug.print("\n[Server::handleWritableDataSocket] existing conn ready!", .{});
            // an existing conn has some data available
            if (ctx.conns.getPtr(@intCast(event.data.fd))) |conn| {
                // std.debug.print("\n[Server::handleWritableDataSocket] existing conn ready for writes!", .{});
                if (conn.write_buffer.isEmpty()) {} else {
                    // std.debug.print("\n[Server::handleWritableDataSocket] conn got evfilt_write readiness but has nothing to write", .{});
                }
            }
        } else {
            std.debug.panic("\n[Server::handleWritableDataSocket] context was null", .{});
        }
    }
};
