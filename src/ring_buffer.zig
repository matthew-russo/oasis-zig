const std = @import("std");
const Allocator = std.mem.Allocator;

const RingBufferError = error{
    NoCapacity,
    OutOfBounds,
};

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,

        capacity: usize,
        used: usize,
        writer: usize,
        reader: usize,
        buf: []T,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            const buf = try allocator.alloc(T, capacity);

            return Self{
                .allocator = allocator,
                .capacity = capacity,
                .used = 0,
                .writer = 0,
                .reader = 0,
                .buf = buf,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buf);
        }

        pub fn len(self: *Self) usize {
            return self.used;
        }

        pub fn cap(self: *Self) usize {
            return self.capacity;
        }

        pub fn free_space(self: *Self) usize {
            return self.capacity - self.used;
        }

        pub fn is_empty(self: *Self) bool {
            return self.used == 0;
        }

        pub fn push(self: *Self, data: T) !void {
            if (self.used >= self.capacity) {
                return RingBufferError.NoCapacity;
            }

            self.buf[self.writer] = data;
            self.used += 1;
            self.writer += 1;
            if (self.writer >= self.capacity) {
                self.writer = 0;
            }
        }

        pub fn peek(self: *Self) ?*T {
            if (self.used == 0) {
                return null;
            }
            return &self.buf[self.reader];
        }

        pub fn pop(self: *Self) ?T {
            if (self.used == 0) {
                return null;
            }
            const t = self.buf[self.reader];
            self.buf[self.reader] = undefined;

            self.used -= 1;
            self.reader += 1;
            if (self.reader >= self.capacity) {
                self.reader = 0;
            }

            return t;
        }

        pub fn get(self: *Self, idx: usize) !?*T {
            if (idx >= self.capacity) {
                return RingBufferError.OutOfBounds;
            }

            var actual_idx = self.reader + idx;
            if (actual_idx >= self.capacity) {
                actual_idx = actual_idx % self.capacity;
            }

            return &self.buf[actual_idx];
        }
    };
}

test "capacity returns const size" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try std.testing.expect(rb.cap() == capacity);
}

test "peek on empty ringbuffer returns none" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try std.testing.expect(rb.peek() == null);
}

test "pop on empty ringbuffer returns none" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try std.testing.expect(rb.pop() == null);
}

test "can push in to ringbuffer" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try rb.push(73);
}

test "can peek in to ringbuffer" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    const n: u32 = 73;
    try rb.push(n);
    try std.testing.expect((rb.peek() orelse unreachable).* == n);
}

test "can pop from ringbuffer" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try rb.push(73);
    try std.testing.expect(rb.pop() orelse unreachable == 73);
}

test "is empty is only true when no elements" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try std.testing.expect(rb.is_empty());
    try rb.push(73);
    try std.testing.expect(!rb.is_empty());
    try std.testing.expect(rb.pop() orelse unreachable == 73);
    try std.testing.expect(rb.is_empty());
}

test "push increases len" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try rb.push(73);
    try std.testing.expect(rb.len() == 1);
    try rb.push(42);
    try std.testing.expect(rb.len() == 2);
}

test "pop decreases len" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    try rb.push(73);
    try std.testing.expect(rb.len() == 1);
    try rb.push(42);
    try std.testing.expect(rb.len() == 2);
    try std.testing.expect(rb.pop() orelse unreachable == 73);
    try std.testing.expect(rb.len() == 1);
    try std.testing.expect(rb.pop() orelse unreachable == 42);
    try std.testing.expect(rb.len() == 0);
}

test "peek doesnt remove entries and keeps len same" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();
    const n1: u32 = 73;
    const n2: u32 = 42;
    try rb.push(n1);
    try std.testing.expect(rb.len() == 1);
    try rb.push(n2);
    try std.testing.expect(rb.len() == 2);
    try std.testing.expect((rb.peek() orelse unreachable).* == n1);
    try std.testing.expect(rb.len() == 2);
    try std.testing.expect((rb.peek() orelse unreachable).* == n1);
    try std.testing.expect(rb.len() == 2);
}

test "push when full results in err" {
    const capacity: usize = 2;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();

    var i: u32 = 0;
    while (i < capacity) {
        try rb.push(73);
        i += 1;
    }

    try std.testing.expectError(RingBufferError.NoCapacity, rb.push(73));
}

test "smoke test" {
    const MyTestStruct = struct {
        i: u32,
        name: []const u8,
    };
    const capacity: usize = 3;
    var rb = try RingBuffer(MyTestStruct).init(std.testing.allocator, capacity);
    defer rb.deinit();
    const ms1 = MyTestStruct{
        .i = 1,
        .name = "peter",
    };
    const ms2 = MyTestStruct{
        .i = 2,
        .name = "paul",
    };
    const ms3 = MyTestStruct{
        .i = 3,
        .name = "mary",
    };
    const ms4 = MyTestStruct{
        .i = 2,
        .name = "john",
    };

    try rb.push(ms1);
    try rb.push(ms2);
    try rb.push(ms3);
    try std.testing.expectError(RingBufferError.NoCapacity, rb.push(ms4));

    try std.testing.expect(std.meta.eql((rb.peek() orelse unreachable).*, ms1));
    try std.testing.expect(std.meta.eql(rb.pop() orelse unreachable, ms1));

    try rb.push(ms4);

    try std.testing.expect(std.meta.eql(rb.pop() orelse unreachable, ms2));
    try std.testing.expect(std.meta.eql(rb.pop() orelse unreachable, ms3));
    try std.testing.expect(std.meta.eql(rb.pop() orelse unreachable, ms4));
    try std.testing.expect(std.meta.eql(rb.pop(), null));
}

test "can get without wrapping, no offset" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();

    const expected_ns = [_]u32{ 73, 42, 119 };
    for (expected_ns) |expected_n| {
        try rb.push(expected_n);
    }

    for (expected_ns, 0..) |expected_n, idx| {
        const actual_n = rb.get(idx) catch unreachable orelse unreachable;
        try std.testing.expect(expected_n == actual_n.*);
    }
}

test "can get without wrapping, with offset" {
    const capacity: usize = 8;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();

    const expected_ns = [_]u32{ 73, 42, 119 };
    for (expected_ns) |expected_n| {
        try rb.push(expected_n);
    }

    for (expected_ns, 0..) |expected_n, idx| {
        const actual_n = rb.get(idx) catch unreachable orelse unreachable;
        try std.testing.expect(expected_n == actual_n.*);
    }

    try std.testing.expect(rb.pop() orelse unreachable == expected_ns[0]);

    const new_first = rb.get(0) catch unreachable orelse unreachable;
    try std.testing.expect(expected_ns[1] == new_first.*);
    const new_second = rb.get(1) catch unreachable orelse unreachable;
    try std.testing.expect(expected_ns[2] == new_second.*);
}

test "can get with wrapping" {
    const capacity: usize = 3;
    var rb = try RingBuffer(u32).init(std.testing.allocator, capacity);
    defer rb.deinit();

    const expected_ns = [_]u32{ 73, 42, 119 };
    for (expected_ns) |expected_n| {
        try rb.push(expected_n);
    }

    for (expected_ns, 0..) |expected_n, idx| {
        const actual_n = rb.get(idx) catch unreachable orelse unreachable;
        try std.testing.expect(expected_n == actual_n.*);
    }

    // we now pop an entry, which leaves the first slot of the buffer empty
    try std.testing.expect(rb.pop() orelse unreachable == expected_ns[0]);
    // at this point our ring buffer should look like:
    //
    // [       ,     head      ,     tail     ]]
    // [       ,       |       ,       |      ]]
    // [       ,       V       ,       V      ]]
    // [<empty>, expected_ns[1], expected_ns[2]]

    // we now push a new entry which will be inserted at index 0 of the underlying buffer
    const new_tail: u32 = 17;
    try rb.push(new_tail);
    // at this point our ring buffer should look like:
    //
    // [  tail  ,     head      ,              ]]
    // [    |   ,       |       ,              ]]
    // [    V   ,       V       ,              ]]
    // [new_tail, expected_ns[1], expected_ns[2]]

    const new_first = rb.get(0) catch unreachable orelse unreachable;
    try std.testing.expect(expected_ns[1] == new_first.*);
    const new_second = rb.get(1) catch unreachable orelse unreachable;
    try std.testing.expect(expected_ns[2] == new_second.*);
    // validate that get will properly wrap back around to the front of the buffer
    const new_third = rb.get(2) catch unreachable orelse unreachable;
    try std.testing.expect(new_tail == new_third.*);
}
