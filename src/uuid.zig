const std = @import("std");
const time = @import("./time.zig");

const UuidParseError = error{
    InvalidLength,
    InvalidFormat,
    InvalidHexChar,
};

/// Universally Unique IDentifiers
///
/// https://datatracker.ietf.org/doc/html/rfc9562
pub const Uuid = struct {
    const Self = @This();

    // bits 0 - 48
    const TIMESTAMP_MASK: u64 = 0x0000_FFFF_FFFF_FFFF;

    lsb: u64,
    msb: u64,

    //  0                   1                   2                   3
    //  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                            rand_a                             |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |            rand_a             |  ver  |       rand_a          |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |var|                        rand_b                             |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                            rand_b                             |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    pub fn v4() Self {
        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
            break :blk seed;
        });
        const rand = prng.random();

        var msb: u64 = rand.int(u64);
        var lsb: u64 = rand.int(u64);

        // Set version to 4 (bits 48-51 of UUID = bits 16-19 of msb)
        msb = (msb & 0xFFFF_0FFF_FFFF_FFFF) | 0x0000_4000_0000_0000;

        // Set variant to 10 (bits 64-65 of UUID = bits 0-1 of lsb)
        lsb = (lsb & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000;

        return Self{ .lsb = lsb, .msb = msb };
    }

    //  0                   1                   2                   3
    //  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                           unix_ts_ms                          |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |          unix_ts_ms           |  ver  |       rand_a          |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |var|                        rand_b                             |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                            rand_b                             |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    pub fn v7() Self {
        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
            break :blk seed;
        });
        const rand = prng.random();

        const timestamp_ms = time.millisSinceEpoch();

        // Hi contains: timestamp (48 bits) + version (4 bits) + rand_a (12 bits)
        const msb: u64 = (@as(u64, timestamp_ms) << 16) | 0x7000 | (rand.int(u64) & 0x0FFF);

        // Lo contains: variant (2 bits) + rand_b (62 bits)
        const lsb: u64 = 0x8000_0000_0000_0000 | (rand.int(u64) & 0x3FFF_FFFF_FFFF_FFFF);

        return Self{ .lsb = lsb, .msb = msb };
    }

    /// The formal definition of the UUID string representation is provided by the follsbwing ABNF [RFC5234]:
    /// UUID     = 4hexOctet "-"
    ///            2hexOctet "-"
    ///            2hexOctet "-"
    ///            2hexOctet "-"
    ///            6hexOctet
    /// hexOctet = HEXDIG HEXDIG
    /// DIGIT    = %x30-39
    /// HEXDIG   = DIGIT / "A" / "B" / "C" / "D" / "E" / "F"
    ///
    /// ex: f81d4fae-7dec-11d0-a765-00a0c91e6bf6
    pub fn toString(self: Self) [36]u8 {
        const hex = "0123456789abcdef";
        const bytes = [16]u8{
            @truncate((self.msb >> 56)),
            @truncate((self.msb >> 48)),
            @truncate((self.msb >> 40)),
            @truncate((self.msb >> 32)),
            @truncate((self.msb >> 24)),
            @truncate((self.msb >> 16)),
            @truncate((self.msb >> 8)),
            @truncate(self.msb),
            @truncate((self.lsb >> 56)),
            @truncate((self.lsb >> 48)),
            @truncate((self.lsb >> 40)),
            @truncate((self.lsb >> 32)),
            @truncate((self.lsb >> 24)),
            @truncate((self.lsb >> 16)),
            @truncate((self.lsb >> 8)),
            @truncate(self.lsb),
        };

        var result: [36]u8 = undefined;
        var i: usize = 0;
        var j: usize = 0;

        const dash_pos = [_]usize{ 8, 13, 18, 23 };

        while (i < 36) {
            if (std.mem.indexOfScalar(usize, &dash_pos, i)) |_| {
                result[i] = '-';
                i += 1;
                continue;
            }

            const byte = bytes[j];
            result[i] = hex[(byte >> 4) & 0xF];
            result[i + 1] = hex[byte & 0xF];
            i += 2;
            j += 1;
        }

        return result;
    }

    pub fn fromString(str: []const u8) UuidParseError!Self {
        if (str.len != 36) return UuidParseError.InvalidLength;
        if (str[8] != '-' or str[13] != '-' or str[18] != '-' or str[23] != '-') {
            return UuidParseError.InvalidFormat;
        }

        var bytes: [16]u8 = undefined;
        var i: usize = 0;
        var j: usize = 0;
        while (i < str.len) {
            if (str[i] == '-') {
                i += 1;
                continue;
            }
            const hi = try hexCharToNibble(str[i]);
            const lo = try hexCharToNibble(str[i + 1]);
            bytes[j] = (@as(u8, hi) << 4) | @as(u8, lo);
            i += 2;
            j += 1;
        }

        const msb = (@as(u64, bytes[0]) << 56) |
            (@as(u64, bytes[1]) << 48) |
            (@as(u64, bytes[2]) << 40) |
            (@as(u64, bytes[3]) << 32) |
            (@as(u64, bytes[4]) << 24) |
            (@as(u64, bytes[5]) << 16) |
            (@as(u64, bytes[6]) << 8) |
            (@as(u64, bytes[7]));

        const lsb = (@as(u64, bytes[8]) << 56) |
            (@as(u64, bytes[9]) << 48) |
            (@as(u64, bytes[10]) << 40) |
            (@as(u64, bytes[11]) << 32) |
            (@as(u64, bytes[12]) << 24) |
            (@as(u64, bytes[13]) << 16) |
            (@as(u64, bytes[14]) << 8) |
            (@as(u64, bytes[15]));

        return Self{ .msb = msb, .lsb = lsb };
    }

    pub fn parse(allocator: std.mem.Allocator, msg_reader: *std.io.FixedBufferStream([]const u8).Reader) !Self {
        _ = allocator;
        const msb = try msg_reader.readInt(u64, std.builtin.Endian.big);
        const lsb = try msg_reader.readInt(u64, std.builtin.Endian.big);
        return Self{
            .msb = msb,
            .lsb = lsb,
        };
    }

    pub fn size(self: *const Self) i32 {
        _ = self;
        return 16;
    }

    pub fn write(self: Self, writer: *std.net.Stream.Writer) !void {
        try writer.writeInt(u64, self.msb, std.builtin.Endian.big);
        try writer.writeInt(u64, self.lsb, std.builtin.Endian.big);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{self.toString()});
    }

    pub fn deinit(self: *const Self) void {
        _ = self;
    }
};

fn hexCharToNibble(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @as(u4, @intCast(c - '0')),
        'a'...'f' => @as(u4, @intCast(c - 'a' + 10)),
        'A'...'F' => @as(u4, @intCast(c - 'A' + 10)),
        else => error.InvalidHexChar,
    };
}

test "v4" {
    const uuid = Uuid.v4();
    const uuid_str = uuid.toString();
    const roundtripped_uuid = try Uuid.fromString(&uuid_str);
    const roundtripped_uuid_str = roundtripped_uuid.toString();
    try std.testing.expectEqual(uuid.lsb, roundtripped_uuid.lsb);
    try std.testing.expectEqual(uuid.msb, roundtripped_uuid.msb);
    try std.testing.expectEqualStrings(&uuid_str, &roundtripped_uuid_str);
}

test "v7" {
    const uuid = Uuid.v7();
    const uuid_str = uuid.toString();
    const roundtripped_uuid = try Uuid.fromString(&uuid_str);
    const roundtripped_uuid_str = roundtripped_uuid.toString();
    try std.testing.expectEqual(uuid.lsb, roundtripped_uuid.lsb);
    try std.testing.expectEqual(uuid.msb, roundtripped_uuid.msb);
    try std.testing.expectEqualStrings(&uuid_str, &roundtripped_uuid_str);
}

test "well-known correct uuids" {
    const cases = [10]struct { hex: []const u8, msb: u64, lsb: u64 }{
        .{ .hex = "645b7ca3-846c-49ef-8767-6e5c0dfb0fd1", .msb = 7231510668416666095, .lsb = 9756888459372072913 },
        .{ .hex = "05b19788-7f02-4d11-989f-3134f5d17adc", .msb = 410275653569629457, .lsb = 10997562918594247388 },
        .{ .hex = "46b32fdd-30bb-410b-b5b0-07698f43c2ca", .msb = 5094468230538019083, .lsb = 13091972266722575050 },
        .{ .hex = "335960bf-c1d5-4fa8-b448-bfcef3f38ec0", .msb = 3700094945568575400, .lsb = 12990844020727189184 },
        .{ .hex = "6009cb07-db9a-489e-a5d1-0224d76b7053", .msb = 6920285537041008798, .lsb = 11948333643646857299 },
        .{ .hex = "b0b420b1-d108-4d85-8a85-363dc093f064", .msb = 12732837994571517317, .lsb = 9981443787988398180 },
        .{ .hex = "82fdfdec-65df-44b7-94dc-00b877d37278", .msb = 9438979585801667767, .lsb = 10726449204774007416 },
        .{ .hex = "12062abd-ec25-45db-8fd4-a615a4f8dd3d", .msb = 1298772537742018011, .lsb = 10364091254378650941 },
        .{ .hex = "3f06a2a1-96d7-4c05-9848-1856612523ba", .msb = 4541496089153850373, .lsb = 10973047251364291514 },
        .{ .hex = "b7154bc2-3955-40fe-91ad-bf143ed50301", .msb = 13192533981009363198, .lsb = 10497256400144892673 },
    };

    for (cases) |case| {
        const uuid = try Uuid.fromString(case.hex);
        try std.testing.expectEqual(uuid.lsb, case.lsb);
        try std.testing.expectEqual(uuid.msb, case.msb);
        const uuid_str = uuid.toString();
        try std.testing.expectEqualStrings(&uuid_str, case.hex);
    }
}
