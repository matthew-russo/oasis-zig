const std = @import("std");

/// A ByteBuffer is a growable read-write container for bytes
/// that provides utilities for reading or appending different
/// sized primitives. As data is read out of the ByteBuffer, it is
/// logically consumed and advances an internal cursor
pub const ByteBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    /// the offset within `curr` where the cursor currently is
    curr_offset: usize,
    /// the current list that is being accessed,
    curr: std.ArrayList(u8),
    /// a staging list where mutations are held while curr
    /// is being accessed, once `curr` is exhausted, `pending`
    /// and `curr` are swapped.
    pending: std.ArrayList(u8),

    pub const Writer = std.io.Writer(*ByteBuffer, anyerror, append);
    pub const Reader = std.io.Reader(*ByteBuffer, anyerror, read);

    /// initialize a new ByteBuffer the provided `std.mem.Allocator`
    /// will be used to grow the internal lists
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .curr_offset = 0,
            .curr = std.ArrayList(u8).init(allocator),
            .pending = std.ArrayList(u8).init(allocator),
        };
    }

    /// deinitialize any memory allocated in this ByteBuffer
    pub fn deinit(self: *Self) void {
        self.curr.deinit();
        self.pending.deinit();
    }

    /// get a `std.io.Writer` for this ByteBuffer
    pub fn writer(self: *ByteBuffer) Writer {
        return .{ .context = self };
    }

    /// get a `std.io.Reader` for this ByteBuffer
    pub fn reader(self: *ByteBuffer) Reader {
        return .{ .context = self };
    }

    // get the remaining length of the ByteBuffer
    pub fn len(self: *Self) usize {
        return self.curr.items.len - self.curr_offset + self.pending.items.len;
    }

    /// returns true if there is no more data to read
    pub fn isEmpty(self: *Self) bool {
        return self.len() == 0;
    }

    /// appends a slice to the ByteBuffer, returning an error
    /// if the allocation failed, otherwise returning the
    /// amount of bytes appended
    ///
    /// the internal allocator is used to extend the internal `pending`
    /// list
    pub fn append(self: *Self, bytes: []const u8) anyerror!usize {
        try self.pending.appendSlice(bytes);
        return bytes.len;
    }

    /// copy a slice out of the ByteBuffer, returning an error
    /// if the allocation failed, otherwise returning the
    /// amount of bytes copied
    ///
    /// the internal allocator is used to copy data to the
    /// provided slice
    pub fn read(self: *Self, dst: []u8) anyerror!usize {
        const to_copy = self.getSlice(dst.len);
        if (to_copy) |src| {
            std.mem.copyForwards(u8, dst, src);
            return src.len;
        } else {
            return 0;
        }
    }

    pub fn getSlice(self: *Self, max_len: usize) ?[]const u8 {
        self.validateLenGreaterThanOrEqualTo(1) orelse return null;

        const to_fetch = @min(max_len, self.curr.items.len - self.curr_offset);
        const to_return = self.curr.items[self.curr_offset .. self.curr_offset + to_fetch];
        self.curr_offset += to_return.len;

        return to_return;
    }

    /// read a single unsigned 8-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is
    /// advanced by one byte
    pub fn getU8(self: *Self) ?u8 {
        self.validateLenGreaterThanOrEqualTo(1) orelse return null;

        const to_return = self.curr.items[self.curr_offset];
        self.curr_offset += 1;

        return to_return;
    }

    /// read an unsigned big-endian 16-bit number out of the
    /// ByteBuffer or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 2 bytes.
    pub fn getU16BigEndian(self: *Self) ?u16 {
        return self.getInt(u16, std.builtin.Endian.big);
    }

    /// read an unsigned big-endian 32-bit number out of the
    /// ByteBuffer or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 4 bytes.
    pub fn getU32BigEndian(self: *Self) ?u32 {
        return self.getInt(u32, std.builtin.Endian.big);
    }

    /// read an unsigned big-endian 64-bit number out of the
    /// ByteBuffer or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 8 bytes.
    pub fn getU64BigEndian(self: *Self) ?u64 {
        return self.getInt(u64, std.builtin.Endian.big);
    }

    /// read an unsigned little-endian 16-bit number out of the
    /// ByteBuffer or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 2 bytes.
    pub fn getU16LittleEndian(self: *Self) ?u16 {
        return self.getInt(u16, std.builtin.Endian.little);
    }

    /// read an unsigned little-endian 32-bit number out of the
    /// ByteBuffer or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 4 bytes.
    pub fn getU32LittleEndian(self: *Self) ?u32 {
        return self.getInt(u32, std.builtin.Endian.little);
    }

    /// read an unsigned little-endian 64-bit number out of the
    /// ByteBuffer or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 8 bytes.
    pub fn getU64LittleEndian(self: *Self) ?u64 {
        return self.getInt(u64, std.builtin.Endian.little);
    }

    /// read a signed 8-bit number out of the ByteBuffer or null if
    /// the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 1 byte.
    pub fn getI8(self: *Self) ?i8 {
        self.validateLenGreaterThanOrEqualTo(1) orelse return null;

        const to_return: i8 = @bitCast(self.curr.items[self.curr_offset]);
        self.curr_offset += 1;

        return to_return;
    }

    /// read a signed big-endian 16-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 2 bytes.
    pub fn getI16BigEndian(self: *Self) ?i16 {
        return self.getInt(i16, std.builtin.Endian.big);
    }

    /// read a signed big-endian 32-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 4 bytes.
    pub fn getI32BigEndian(self: *Self) ?i32 {
        return self.getInt(i32, std.builtin.Endian.big);
    }

    /// read a signed big-endian 64-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 8 bytes.
    pub fn getI64BigEndian(self: *Self) ?i64 {
        return self.getInt(i64, std.builtin.Endian.big);
    }

    /// read a signed little-endian 16-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 2 bytes.
    pub fn getI16LittlEndian(self: *Self) ?i16 {
        return self.getInt(i16, std.builtin.Endian.little);
    }

    /// read a signed little-endian 32-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 4 bytes.
    pub fn getI32LittlEndian(self: *Self) ?i32 {
        return self.getInt(i32, std.builtin.Endian.little);
    }

    /// read a signed little-endian 64-bit number out of the ByteBuffer
    /// or null if the ByteBuffer is empty.
    ///
    /// no allocations are made and the internal cursor is advanced
    /// by 8 bytes.
    pub fn getI64LittlEndian(self: *Self) ?i64 {
        return self.getInt(i64, std.builtin.Endian.little);
    }

    inline fn validateLenGreaterThanOrEqualTo(self: *Self, expected: usize) ?void {
        if (self.len() < expected) {
            return null;
        }

        self.swapCurrIfExhausted();
    }

    fn swapCurrIfExhausted(self: *Self) void {
        if (self.curr_offset >= self.curr.items.len) {
            self.curr_offset = 0;
            const temp = self.curr;
            self.curr = self.pending;
            self.pending = temp;
            self.pending.clearRetainingCapacity();
        }
    }

    fn getInt(self: *Self, comptime T: type, endianness: std.builtin.Endian) ?T {
        const num_bytes = comptime @bitSizeOf(T) / 8;

        self.validateLenGreaterThanOrEqualTo(num_bytes) orelse return null;

        var staging: [num_bytes]u8 = undefined;
        const available = @min(num_bytes, self.curr.items.len - self.curr_offset);
        @memcpy(staging[0..available], self.curr.items[self.curr_offset .. self.curr_offset + available]);
        self.curr_offset += available;
        if (available == staging.len) {
            return std.mem.readInt(T, &staging, endianness);
        }

        self.swapCurrIfExhausted();
        const remaining = staging.len - available;
        @memcpy(staging[available..], self.curr.items[self.curr_offset .. self.curr_offset + remaining]);
        self.curr_offset += remaining;
        return std.mem.readInt(T, &staging, endianness);
    }
};

test "can create" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
}

test "can append" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    const bytes = [_]u8{ 0, 1, 2, 3, 4 };
    _ = try buf.append(&bytes);
}

test "len is properly updated when appending" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    const bytes = [_]u8{ 0, 1, 2, 3, 4 };
    try std.testing.expect(buf.len() == 0);
    _ = try buf.append(&bytes);
    try std.testing.expect(buf.len() == bytes.len);
}

test "can get u8" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    const bytes = [_]u8{ 0, 1, 2, 3, 4 };
    _ = try buf.append(&bytes);

    for (bytes) |expected| {
        const actual = buf.getU8() orelse unreachable;
        try std.testing.expect(expected == actual);
    }

    if (buf.getU8()) |shouldnt_exist| {
        std.debug.panic("should have exhausted ByteBuffer but got {d}", .{shouldnt_exist});
    }
}

test "can append while reading" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    const bytes = [_]u8{ 0, 1, 2, 3, 4 };
    _ = try buf.append(&bytes);

    const a1 = buf.getU8() orelse unreachable;
    try std.testing.expect(a1 == 0);
    const a2 = buf.getU8() orelse unreachable;
    try std.testing.expect(a2 == 1);

    const new_bytes = [_]u8{ 5, 6, 7, 8, 9 };
    _ = try buf.append(&new_bytes);

    var expected: u8 = 2;
    while (buf.getU8()) |actual| {
        try std.testing.expect(actual == expected);
        expected += 1;
    }

    try std.testing.expect(expected == 10);
}

test "can get u16" {
    {
        var buf = ByteBuffer.init(std.testing.allocator);
        defer buf.deinit();
        const bytes = [_]u8{ 0, 1, 2, 3 };
        _ = try buf.append(&bytes);

        const a1 = buf.getU16BigEndian() orelse unreachable;
        try std.testing.expect(a1 == 1);
        const a2 = buf.getU16BigEndian() orelse unreachable;
        try std.testing.expect(a2 == 515);
    }

    {
        var buf = ByteBuffer.init(std.testing.allocator);
        defer buf.deinit();
        const bytes = [_]u8{ 0, 1, 2 };
        _ = try buf.append(&bytes);

        const a1 = buf.getU16BigEndian() orelse unreachable;
        try std.testing.expect(a1 == 1);

        // at this point, curr only has `2` left in it and appending will add to
        // `pending` next time we get a U16, we'll need to read the first byte from
        // `curr` and second byte from `pending`. we append an extra byte, `4`,
        // here to validate that getU16BigEndian sets offsets properly and switches
        // `curr` and `pending`.
        _ = try buf.append(&[_]u8{ 3, 4 });

        const a2 = buf.getU16BigEndian() orelse unreachable;
        try std.testing.expect(a2 == 515);

        const a3 = buf.getU8() orelse unreachable;
        try std.testing.expect(a3 == 4);
    }
}

test "can get slice" {
    {
        var buf = ByteBuffer.init(std.testing.allocator);
        defer buf.deinit();
        const bytes = [_]u8{ 0, 1, 2, 3 };
        _ = try buf.append(&bytes);

        const a = buf.getSlice(std.math.maxInt(usize)) orelse unreachable;
        try std.testing.expect(std.mem.eql(u8, &bytes, a));
    }

    {
        var buf = ByteBuffer.init(std.testing.allocator);
        defer buf.deinit();
        const bytes = [_]u8{ 0, 1, 2 };
        _ = try buf.append(&bytes);

        // arbitrary, just to consume 2 bytes
        _ = buf.getU16BigEndian() orelse unreachable;

        // at this point, curr only has `2` left in it and appending will add to
        // `pending`
        const new_bytes = [_]u8{ 3, 4 };
        _ = try buf.append(&new_bytes);

        // the first slice should be [2] and second slice [3, 4]
        const a1 = buf.getSlice(std.math.maxInt(usize)) orelse unreachable;
        try std.testing.expect(std.mem.eql(u8, a1, &[_]u8{2}));

        const a2 = buf.getSlice(std.math.maxInt(usize)) orelse unreachable;
        try std.testing.expect(std.mem.eql(u8, a2, &new_bytes));
    }
}
