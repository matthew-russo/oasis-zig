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
        try Self.sprintfWithContext(&ctx, t);
        return ctx.buffer;
    }

    pub fn sprintfWithContext(ctx: *FormatContext, t: anytype) !void {
        const type_info = @typeInfo(@TypeOf(t));
        switch (type_info) {
            .type => {
                try ctx.buffer.appendSlice(@typeName(t));
            },
            .void => {
                try ctx.buffer.appendSlice("void");
            },
            .bool => {
                if (t) {
                    try ctx.buffer.appendSlice("true");
                } else {
                    try ctx.buffer.appendSlice("false");
                }
            },
            .noreturn => unreachable,
            .int => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
            },
            .float => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
            },
            .pointer => "type: pointer", // Pointer
            .array => "type: array", // Array
            .@"struct" => |struc| {
                try ctx.buffer.appendSlice(@typeName(@TypeOf(t)));
                try ctx.buffer.appendSlice(" { ");
                inline for (struc.fields) |field| {
                    try ctx.buffer.appendSlice(field.name);
                    try ctx.buffer.appendSlice(": ");
                    try Self.sprintfWithContext(ctx, @field(t, field.name));
                    try ctx.buffer.appendSlice(", ");
                }
                try ctx.buffer.appendSlice("}");
            },
            .comptime_float => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
            },
            .comptime_int => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(actual_buf);
            },
            .undefined => unreachable,
            .null => unreachable,
            .optional => "TODO: type: optional", // Optional
            .error_union => "TODO: type: error_union", // ErrorUnion
            .error_set => "TODO: type: error_set", // ErrorSet
            .@"enum" => |_| {
                try ctx.buffer.appendSlice(@typeName(@TypeOf(t)));
                try ctx.buffer.appendSlice(".");
                try ctx.buffer.appendSlice(@tagName(t));
            },
            .@"union" => |unio| {
                if (unio.tag_type) |_| {
                    try ctx.buffer.appendSlice(@typeName(@TypeOf(t)));
                    try ctx.buffer.appendSlice(" { .");
                    try ctx.buffer.appendSlice(@tagName(t));
                    try ctx.buffer.appendSlice(": ");

                    inline for (unio.fields, 0..) |field, i| {
                        if (@intFromEnum(t) == i) {
                            try Self.sprintfWithContext(ctx, @field(t, field.name));
                            break;
                        }
                    }

                    try ctx.buffer.appendSlice(" }");
                } else {
                    std.debug.panic("its impossible to format an untagged union as it cannot be known what field is active", .{});
                }
            },
            .@"fn" => "TODO: type: fn", // Fn
            .@"opaque" => "TODO: type: opaque", // Opaque
            .frame => "TODO: type: frame", // Frame
            .@"anyframe" => "TODO: type: any_frame", // AnyFrame
            .vector => "TODO: type: vector", // Vector
            .enum_literal => "TODO: type: enum_literal", // void
        }
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

test "expect DebugFormatter to work with basic structs" {
    const MyStruct = struct {
        a: u8,
        b: u64,
        c: bool,
    };

    const my_struct = MyStruct{
        .a = 42,
        .b = 2934092390498,
        .c = true,
    };

    const output = try DebugFormatter.sprintf(std.testing.allocator, my_struct);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with basic structs.MyStruct { a: 42, b: 2934092390498, c: true, }",
    ));
    output.deinit();
}

test "expect DebugFormatter to work with composite structs" {
    const InnerStruct = struct {
        b: u64,
        c: bool,
    };

    const MyStruct = struct {
        a: u8,
        inner: InnerStruct,
    };

    const my_struct = MyStruct{
        .a = 42,
        .inner = InnerStruct{
            .b = 2934092390498,
            .c = true,
        },
    };

    const output = try DebugFormatter.sprintf(std.testing.allocator, my_struct);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with composite structs.MyStruct { a: 42, inner: debug_formatter.test.expect DebugFormatter to work with composite structs.InnerStruct { b: 2934092390498, c: true, }, }",
    ));
    output.deinit();
}

test "expect DebugFormatter to work with enums" {
    const MyEnum = enum(u32) {
        hundred = 100,
        thousand = 1000,
        million = 1000000,
    };

    var my_enum = MyEnum.hundred;
    var output = try DebugFormatter.sprintf(std.testing.allocator, my_enum);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with enums.MyEnum.hundred",
    ));
    output.deinit();

    my_enum = MyEnum.thousand;
    output = try DebugFormatter.sprintf(std.testing.allocator, my_enum);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with enums.MyEnum.thousand",
    ));
    output.deinit();

    my_enum = MyEnum.million;
    output = try DebugFormatter.sprintf(std.testing.allocator, my_enum);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with enums.MyEnum.million",
    ));
    output.deinit();
}

test "expect DebugFormatter to work with tagged unions" {
    const MyStruct = struct {
        a: u8,
        b: i64,
        c: bool,
    };

    const MyTaggedUnion = union(enum) {
        void_value: void,
        u64_value: u64,
        struct_value: MyStruct,
    };

    var my_tagged_union: MyTaggedUnion = MyTaggedUnion.void_value;
    var output = try DebugFormatter.sprintf(std.testing.allocator, my_tagged_union);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with tagged unions.MyTaggedUnion { .void_value: void }",
    ));
    output.deinit();

    my_tagged_union = MyTaggedUnion{ .u64_value = 90823409 };
    output = try DebugFormatter.sprintf(std.testing.allocator, my_tagged_union);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with tagged unions.MyTaggedUnion { .u64_value: 90823409 }",
    ));
    output.deinit();

    my_tagged_union = MyTaggedUnion{ .struct_value = MyStruct{ .a = 42, .b = -73, .c = true } };
    output = try DebugFormatter.sprintf(std.testing.allocator, my_tagged_union);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with tagged unions.MyTaggedUnion { .struct_value: debug_formatter.test.expect DebugFormatter to work with tagged unions.MyStruct { a: 42, b: -73, c: true, } }",
    ));
    output.deinit();
}
