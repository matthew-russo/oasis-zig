const builtin = @import("builtin");
const std = @import("std");

const collections = @import("../collections/mod.zig");
const tcp_server = @import("tcp_server.zig");
const sys = @import("sys.zig");
const Address = @import("address.zig").Address;

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
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8080);
    var server = TcpServer.init(std.testing.allocator, threaded.io(), addr, handler);
    defer server.deinit();
}

test "expect to be able to spawn a TcpServer" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8081);
    var server = TcpServer.init(std.testing.allocator, threaded.io(), addr, handler);
    defer server.deinit();

    try server.serve();
}

test "expect to be able to join a spawned TcpServer" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8082);
    var server = TcpServer.init(std.testing.allocator, threaded.io(), addr, handler);
    defer server.deinit();

    try server.serve();
    server.join();
}

test "expect to be able to send and receive data from a spawned TcpServer" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    const handlerImpl = try std.testing.allocator.create(TestTcpHandler);
    handlerImpl.* = TestTcpHandler{};

    const handler = tcp_server.TcpConnectionHandler.init(handlerImpl);

    const addr = Address.initIp4([_]u8{ 0, 0, 0, 0 }, 8083);
    var server = TcpServer.init(std.testing.allocator, threaded.io(), addr, handler);
    defer server.join();
    defer server.deinit();

    try server.serve();

    const conn_fd = try sys.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
    defer sys.close(conn_fd);
    try sys.connect(conn_fd, &addr.any, addr.getOsSockLen());

    const msg = "hello world";
    _ = try sys.write(conn_fd, msg);
    var buf: [32]u8 = undefined;
    const resp_size = try sys.read(conn_fd, buf[0..]);
    try std.testing.expectEqualSlices(u8, msg, buf[0..resp_size]);
}
