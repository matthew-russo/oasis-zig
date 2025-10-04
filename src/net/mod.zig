const builtin = @import("builtin");
const std = @import("std");

const collections = @import("../collections/mod.zig");
const tcp_server = @import("tcp_server.zig");

pub const TcpServer = switch (builtin.os.tag) {
    .macos => tcp_server.KqueueTcpServer,
    .linux => tcp_server.EpollTcpServer,
    else => void,
};

const TestTcpHandler = struct {
    const Self = @This();

    pub fn poll(
        self: *Self,
        read_buffer: *collections.byte_buffer.ByteBuffer,
        write_buffer: *collections.byte_buffer.ByteBuffer,
    ) void {
        _ = self;
        while (!read_buffer.isEmpty()) {
            var buf: [4096]u8 = undefined;
            const amount_read = read_buffer.read(&buf) catch unreachable;
            _ = write_buffer.append(buf[0..amount_read]) catch unreachable;
        }
    }
};

test "expect to be able to construct and destruct a TcpServer" {
    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = std.net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8080);
    var server = TcpServer.init(std.testing.allocator, addr, handler);
    defer server.deinit();
}

test "expect to be able to spawn a TcpServer" {
    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = std.net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8081);
    var server = TcpServer.init(std.testing.allocator, addr, handler);
    defer server.deinit();

    try server.serve();
}

test "expect to be able to join a spawned TcpServer" {
    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = std.net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8082);
    var server = TcpServer.init(std.testing.allocator, addr, handler);
    defer server.deinit();

    try server.serve();
    server.join();
}

test "expect to be able to send and receive data from a spawned TcpServer" {
    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = std.net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8083);
    var server = TcpServer.init(std.testing.allocator, addr, handler);
    defer server.join();
    defer server.deinit();

    try server.serve();

    const conn = try std.net.tcpConnectToAddress(addr);
    defer conn.close();

    const msg = "hello world";
    _ = try conn.write(msg);
    var buf: [32]u8 = undefined;
    const resp_size = try conn.read(buf[0..]);
    try std.testing.expectEqualSlices(u8, msg, buf[0..resp_size]);
}
