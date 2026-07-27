const std = @import("std");

pub fn nanosSinceEpoch(io: std.Io) u64 {
    const ts = std.Io.Timestamp.now(io, .real);
    const nanosUnsigned: u128 = @intCast(ts.nanoseconds);
    return @truncate(nanosUnsigned);
}

pub fn microsSinceEpoch(io: std.Io) u64 {
    return nanosSinceEpoch(io) / 1000;
}

pub fn millisSinceEpoch(io: std.Io) u64 {
    return microsSinceEpoch(io) / 1000;
}

test "can get nanos since epoch" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const ns1 = nanosSinceEpoch(io);
    const ns2 = nanosSinceEpoch(io);
    const ns3 = nanosSinceEpoch(io);
    try std.testing.expect(ns2 >= ns1);
    try std.testing.expect(ns3 >= ns2);
}
