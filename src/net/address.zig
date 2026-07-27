const std = @import("std");
const posix = std.posix;

/// Minimal replacement for the `std.net.Address` type that Zig 0.16 removed
/// when it migrated the high-level `net` APIs onto the `std.Io` interface.
///
/// It only covers the IPv4 surface that the TCP server relies on: producing a
/// raw `sockaddr` to hand to `bind`/`accept`/`connect` and reporting its length.
pub const Address = extern union {
    any: posix.sockaddr,
    in: posix.sockaddr.in,

    /// Build an IPv4 address from raw octets and a host-order port.
    pub fn initIp4(addr: [4]u8, port: u16) Address {
        // Zero-initialize so this stays portable across platforms whose
        // `sockaddr.in` layouts differ (e.g. the BSD `len` field on macOS).
        var sa: posix.sockaddr.in = std.mem.zeroes(posix.sockaddr.in);
        if (@hasField(posix.sockaddr.in, "len")) {
            sa.len = @sizeOf(posix.sockaddr.in);
        }
        sa.family = posix.AF.INET;
        sa.port = std.mem.nativeToBig(u16, port);
        sa.addr = @bitCast(addr);
        return .{ .in = sa };
    }

    pub fn getOsSockLen(self: Address) posix.socklen_t {
        _ = self;
        return @sizeOf(posix.sockaddr.in);
    }
};
