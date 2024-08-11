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
            .Void => "void", // void
            .Bool => "type: bool", // void
            .NoReturn => "type: no_return", // void
            .Int => "type: int", // Int
            .Float => "type: float", // Float
            .Pointer => "type: pointer", // Pointer
            .Array => "type: array", // Array
            .Struct => "type: struct", // Struct
            .ComptimeFloat => "type: comptime_float", // void
            .ComptimeInt => "type: comptime_int", // void
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