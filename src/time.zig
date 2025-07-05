const std = @import("std");

pub fn nanosSinceEpoch() u64 {
    const nanosUnsigned: u128 = @intCast(std.time.nanoTimestamp());
    return @truncate(nanosUnsigned);
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
