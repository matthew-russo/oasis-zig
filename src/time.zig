const std = @import("std");

pub fn nanosSinceEpoch() u64 {
    // posix systems return a timespec, convert it to a u64
    const now_instant = std.time.Instant.now() catch unreachable;
    const timespec = now_instant.timestamp;
    const secs_as_u64: u64 = @intCast(timespec.sec);
    const nsecs_as_u64: u64 = @intCast(timespec.nsec);
    const secs_as_ns = secs_as_u64 * std.time.ns_per_s;
    const now = secs_as_ns + nsecs_as_u64;
    return now;
}

pub fn microsSinceEpoch() u64 {
    return nanosSinceEpoch() / 1000;
}

pub fn millisSinceEpoch() u64 {
    return microsSinceEpoch() / 1000;
}

test "can get nanos since epoch" {
    const ns1 = nanosSinceEpoch();
    const ns2 = nanosSinceEpoch();
    const ns3 = nanosSinceEpoch();
    try std.testing.expect(ns2 >= ns1);
    try std.testing.expect(ns3 >= ns2);
}
