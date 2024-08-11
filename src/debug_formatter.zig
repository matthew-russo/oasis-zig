const std = @import("std");

pub const FormatStyle = enum {
    pretty,
    dense,
};

pub const FormatContext = struct {
    style: FormatStyle,
    indentation: u8,
    buffer: std.ArrayList(u8),
};

pub const DebugFormatter = struct {
    const Self = @This();

    pub fn sprintf(allocator: std.mem.Allocator, t: anytype) !std.ArrayList(u8) {
        var ctx = FormatContext{
            .style = FormatStyle.dense,
            .indentation = 0,
            .buffer = std.ArrayList(u8).init(allocator),
        };
        return Self.sprintfWithContext(&ctx, t);
    }

    pub fn sprintfWithContext(ctx: *FormatContext, t: anytype) !std.ArrayList(u8) {
        const type_info = @typeInfo(@TypeOf(t));
        return switch (type_info) {
            .Type => blk: {
                try ctx.buffer.appendSlice(@typeName(t));
                break :blk ctx.buffer;
            },
            .Void => blk: {
                try ctx.buffer.appendSlice("void");
                break :blk ctx.buffer;
            },
            .Bool => blk: {
                if (t) {
                    try ctx.buffer.appendSlice("true");
                } else {
                    try ctx.buffer.appendSlice("false");
                }
                break :blk ctx.buffer;
            },
            .NoReturn => unreachable,
            .Int => blk: {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
                break :blk ctx.buffer;
            },
            .Float => blk: {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
                break :blk ctx.buffer;
            },
            .Pointer => "type: pointer", // Pointer
            .Array => "type: array", // Array
            .Struct => "type: struct", // Struct
            .ComptimeFloat => blk: {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
                break :blk ctx.buffer;
            },
            .ComptimeInt => blk: {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
                break :blk ctx.buffer;
            },
            .Undefined => "type: undefined", // void
            .Null => "null", // void
            .Optional => "type: optional", // Optional
            .ErrorUnion => "type: error_union", // ErrorUnion
            .ErrorSet => "type: error_set", // ErrorSet
            .Enum => "type: enum", // Enum
            .Union => "type: union", // Union
            .Fn => "type: fn", // Fn
            .Opaque => "type: opaque", // Opaque
            .Frame => "type: frame", // Frame
            .AnyFrame => "type: any_frame", // AnyFrame
            .Vector => "type: vector", // Vector
            .EnumLiteral => "type: enum_literal", // void
        };
    }
};

test "expect DebugFormatter to work with types" {
    const MyStruct = struct {
        a: u8,
        b: u64,
        c: bool,
    };

    const u64_type: type = u64;
    const struct_type: type = MyStruct;

    var output = try DebugFormatter.sprintf(std.testing.allocator, u64_type);
    std.debug.assert(std.mem.eql(u8, output.items, "u64"));
    output.deinit();

    output = try DebugFormatter.sprintf(std.testing.allocator, struct_type);
    std.debug.assert(std.mem.eql(u8, output.items, "debug_formatter.test.expect DebugFormatter to work with types.MyStruct"));
    output.deinit();
}

test "expect DebugFormatter to work with void" {
    const void_value: void = undefined;

    var output = try DebugFormatter.sprintf(std.testing.allocator, void_value);
    std.debug.assert(std.mem.eql(u8, output.items, "void"));
    output.deinit();
}

test "expect DebugFormatter to work with bools" {
    var output = try DebugFormatter.sprintf(std.testing.allocator, true);
    std.debug.assert(std.mem.eql(u8, output.items, "true"));
    output.deinit();

    output = try DebugFormatter.sprintf(std.testing.allocator, false);
    std.debug.assert(std.mem.eql(u8, output.items, "false"));
    output.deinit();
}

test "expect DebugFormatter to work with ints" {
    const u: u32 = 42;
    var output = try DebugFormatter.sprintf(std.testing.allocator, u);
    std.debug.assert(std.mem.eql(u8, output.items, "42"));
    output.deinit();

    const i: i32 = -73;
    output = try DebugFormatter.sprintf(std.testing.allocator, i);
    std.debug.assert(std.mem.eql(u8, output.items, "-73"));
    output.deinit();

    const uu: u64 = 2890409822222;
    output = try DebugFormatter.sprintf(std.testing.allocator, uu);
    std.debug.assert(std.mem.eql(u8, output.items, "2890409822222"));
    output.deinit();
}

test "expect DebugFormatter to work with floats" {
    const u: f32 = 42.42;
    var output = try DebugFormatter.sprintf(std.testing.allocator, u);
    std.debug.assert(std.mem.eql(u8, output.items, "4.242e1"));
    output.deinit();

    const i: f32 = -73.73;
    output = try DebugFormatter.sprintf(std.testing.allocator, i);
    std.debug.assert(std.mem.eql(u8, output.items, "-7.373e1"));
    output.deinit();

    const uu: f64 = 2890409822222.2394820;
    output = try DebugFormatter.sprintf(std.testing.allocator, uu);
    std.debug.assert(std.mem.eql(u8, output.items, "2.8904098222222393e12"));
    output.deinit();
}

test "expect DebugFormatter to work with comptime ints" {
    var output = try DebugFormatter.sprintf(std.testing.allocator, 42);
    std.debug.assert(std.mem.eql(u8, output.items, "42"));
    output.deinit();

    output = try DebugFormatter.sprintf(std.testing.allocator, -73);
    std.debug.assert(std.mem.eql(u8, output.items, "-73"));
    output.deinit();

    output = try DebugFormatter.sprintf(std.testing.allocator, 2890409822222);
    std.debug.assert(std.mem.eql(u8, output.items, "2890409822222"));
    output.deinit();
}

test "expect DebugFormatter to work with comptime floats" {
    var output = try DebugFormatter.sprintf(std.testing.allocator, 42.42);
    std.debug.assert(std.mem.eql(u8, output.items, "4.242e1"));
    output.deinit();

    output = try DebugFormatter.sprintf(std.testing.allocator, -73.73);
    std.debug.assert(std.mem.eql(u8, output.items, "-7.373e1"));
    output.deinit();

    output = try DebugFormatter.sprintf(std.testing.allocator, 2890409822222.2394820);
    std.debug.assert(std.mem.eql(u8, output.items, "2.890409822222239482e12"));
    output.deinit();
}

// test "expect DebugFormatter to work with structs" {
//     const MyStruct = struct {
//         a: u8,
//         b: u64,
//         c: bool,
//     };
//
//     const my_struct = MyStruct{
//         .a = 42,
//         .b = 2934092390498,
//         .c = true,
//     };
//
//     const output = DebugFormatter.debugSprintf(std.testing.allocator, my_struct);
//
//     std.debug.print("\n\nhelloworld: {s}\n\n", .{output});
//     std.debug.assert(std.mem.eql(u8, output, "MyStruct { a: 42, b: 2934092390498, c: true }"));
// }
