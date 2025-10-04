const std = @import("std");

pub const FormatStyle = enum {
    pretty,
    dense,
};

pub const FormatContext = struct {
    allocator: std.mem.Allocator,
    style: FormatStyle,
    indentation: u8,
    buffer: std.ArrayList(u8),
};

pub const DebugFormatter = struct {
    const Self = @This();

    pub fn sprintf(allocator: std.mem.Allocator, t: anytype) !std.ArrayList(u8) {
        var ctx = FormatContext{
            .allocator = allocator,
            .style = FormatStyle.dense,
            .indentation = 0,
            .buffer = std.ArrayList(u8).empty,
        };
        try Self.sprintfWithContext(&ctx, t);
        return ctx.buffer;
    }

    pub fn sprintfWithContext(ctx: *FormatContext, t: anytype) !void {
        const type_info = @typeInfo(@TypeOf(t));
        switch (type_info) {
            .type => {
                try ctx.buffer.appendSlice(ctx.allocator, @typeName(t));
            },
            .void => {
                try ctx.buffer.appendSlice(ctx.allocator, "void");
            },
            .bool => {
                if (t) {
                    try ctx.buffer.appendSlice(ctx.allocator, "true");
                } else {
                    try ctx.buffer.appendSlice(ctx.allocator, "false");
                }
            },
            .noreturn => unreachable,
            .int => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(ctx.allocator, actual_buf);
            },
            .float => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(ctx.allocator, actual_buf);
            },
            .pointer => "type: pointer", // Pointer
            .array => "type: array", // Array
            .@"struct" => |struc| {
                try ctx.buffer.appendSlice(ctx.allocator, @typeName(@TypeOf(t)));
                try ctx.buffer.appendSlice(ctx.allocator, " { ");
                inline for (struc.fields) |field| {
                    try ctx.buffer.appendSlice(ctx.allocator, field.name);
                    try ctx.buffer.appendSlice(ctx.allocator, ": ");
                    try Self.sprintfWithContext(ctx, @field(t, field.name));
                    try ctx.buffer.appendSlice(ctx.allocator, ", ");
                }
                try ctx.buffer.appendSlice(ctx.allocator, "}");
            },
            .comptime_float => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(ctx.allocator, actual_buf);
            },
            .comptime_int => {
                var buf: [256]u8 = undefined;
                const actual_buf = try std.fmt.bufPrint(&buf, "{}", .{t});
                try ctx.buffer.appendSlice(ctx.allocator, actual_buf);
            },
            .undefined => unreachable,
            .null => unreachable,
            .optional => "TODO: type: optional", // Optional
            .error_union => "TODO: type: error_union", // ErrorUnion
            .error_set => "TODO: type: error_set", // ErrorSet
            .@"enum" => |_| {
                try ctx.buffer.appendSlice(ctx.allocator, @typeName(@TypeOf(t)));
                try ctx.buffer.appendSlice(ctx.allocator, ".");
                try ctx.buffer.appendSlice(ctx.allocator, @tagName(t));
            },
            .@"union" => |unio| {
                if (unio.tag_type) |_| {
                    try ctx.buffer.appendSlice(ctx.allocator, @typeName(@TypeOf(t)));
                    try ctx.buffer.appendSlice(ctx.allocator, " { .");
                    try ctx.buffer.appendSlice(ctx.allocator, @tagName(t));
                    try ctx.buffer.appendSlice(ctx.allocator, ": ");

                    inline for (unio.fields, 0..) |field, i| {
                        if (@intFromEnum(t) == i) {
                            try Self.sprintfWithContext(ctx, @field(t, field.name));
                            break;
                        }
                    }

                    try ctx.buffer.appendSlice(ctx.allocator, " }");
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
    output.deinit(std.testing.allocator);

    output = try DebugFormatter.sprintf(std.testing.allocator, struct_type);
    std.debug.assert(std.mem.eql(u8, output.items, "debug_formatter.test.expect DebugFormatter to work with types.MyStruct"));
    output.deinit(std.testing.allocator);
}

test "expect DebugFormatter to work with void" {
    const void_value: void = undefined;

    var output = try DebugFormatter.sprintf(std.testing.allocator, void_value);
    std.debug.assert(std.mem.eql(u8, output.items, "void"));
    output.deinit(std.testing.allocator);
}

test "expect DebugFormatter to work with bools" {
    var output = try DebugFormatter.sprintf(std.testing.allocator, true);
    std.debug.assert(std.mem.eql(u8, output.items, "true"));
    output.deinit(std.testing.allocator);

    output = try DebugFormatter.sprintf(std.testing.allocator, false);
    std.debug.assert(std.mem.eql(u8, output.items, "false"));
    output.deinit(std.testing.allocator);
}

test "expect DebugFormatter to work with ints" {
    const u: u32 = 42;
    var output = try DebugFormatter.sprintf(std.testing.allocator, u);
    std.debug.assert(std.mem.eql(u8, output.items, "42"));
    output.deinit(std.testing.allocator);

    const i: i32 = -73;
    output = try DebugFormatter.sprintf(std.testing.allocator, i);
    std.debug.assert(std.mem.eql(u8, output.items, "-73"));
    output.deinit(std.testing.allocator);

    const uu: u64 = 2890409822222;
    output = try DebugFormatter.sprintf(std.testing.allocator, uu);
    std.debug.assert(std.mem.eql(u8, output.items, "2890409822222"));
    output.deinit(std.testing.allocator);
}

test "expect DebugFormatter to work with floats" {
    const u: f32 = 42.42;
    var output = try DebugFormatter.sprintf(std.testing.allocator, u);
    std.debug.assert(std.mem.eql(u8, output.items, "42.42"));
    output.deinit(std.testing.allocator);

    const i: f32 = -73.73;
    output = try DebugFormatter.sprintf(std.testing.allocator, i);
    std.debug.assert(std.mem.eql(u8, output.items, "-73.73"));
    output.deinit(std.testing.allocator);

    const uu: f64 = 2890409822222.2394820;
    output = try DebugFormatter.sprintf(std.testing.allocator, uu);
    std.debug.assert(std.mem.eql(u8, output.items, "2890409822222.2393"));
    output.deinit(std.testing.allocator);
}

test "expect DebugFormatter to work with comptime ints" {
    var output = try DebugFormatter.sprintf(std.testing.allocator, 42);
    std.debug.assert(std.mem.eql(u8, output.items, "42"));
    output.deinit(std.testing.allocator);

    output = try DebugFormatter.sprintf(std.testing.allocator, -73);
    std.debug.assert(std.mem.eql(u8, output.items, "-73"));
    output.deinit(std.testing.allocator);

    output = try DebugFormatter.sprintf(std.testing.allocator, 2890409822222);
    std.debug.assert(std.mem.eql(u8, output.items, "2890409822222"));
    output.deinit(std.testing.allocator);
}

test "expect DebugFormatter to work with comptime floats" {
    var output = try DebugFormatter.sprintf(std.testing.allocator, 42.42);
    std.debug.assert(std.mem.eql(u8, output.items, "42.42"));
    output.deinit(std.testing.allocator);

    output = try DebugFormatter.sprintf(std.testing.allocator, -73.73);
    std.debug.assert(std.mem.eql(u8, output.items, "-73.73"));
    output.deinit(std.testing.allocator);

    output = try DebugFormatter.sprintf(std.testing.allocator, 2890409822222.2394820);
    std.debug.assert(std.mem.eql(u8, output.items, "2890409822222.239482"));
    output.deinit(std.testing.allocator);
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

    var output = try DebugFormatter.sprintf(std.testing.allocator, my_struct);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with basic structs.MyStruct { a: 42, b: 2934092390498, c: true, }",
    ));
    output.deinit(std.testing.allocator);
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

    var output = try DebugFormatter.sprintf(std.testing.allocator, my_struct);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with composite structs.MyStruct { a: 42, inner: debug_formatter.test.expect DebugFormatter to work with composite structs.InnerStruct { b: 2934092390498, c: true, }, }",
    ));
    output.deinit(std.testing.allocator);
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
    output.deinit(std.testing.allocator);

    my_enum = MyEnum.thousand;
    output = try DebugFormatter.sprintf(std.testing.allocator, my_enum);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with enums.MyEnum.thousand",
    ));
    output.deinit(std.testing.allocator);

    my_enum = MyEnum.million;
    output = try DebugFormatter.sprintf(std.testing.allocator, my_enum);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with enums.MyEnum.million",
    ));
    output.deinit(std.testing.allocator);
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
    output.deinit(std.testing.allocator);

    my_tagged_union = MyTaggedUnion{ .u64_value = 90823409 };
    output = try DebugFormatter.sprintf(std.testing.allocator, my_tagged_union);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with tagged unions.MyTaggedUnion { .u64_value: 90823409 }",
    ));
    output.deinit(std.testing.allocator);

    my_tagged_union = MyTaggedUnion{ .struct_value = MyStruct{ .a = 42, .b = -73, .c = true } };
    output = try DebugFormatter.sprintf(std.testing.allocator, my_tagged_union);
    std.debug.assert(std.mem.eql(
        u8,
        output.items,
        "debug_formatter.test.expect DebugFormatter to work with tagged unions.MyTaggedUnion { .struct_value: debug_formatter.test.expect DebugFormatter to work with tagged unions.MyStruct { a: 42, b: -73, c: true, } }",
    ));
    output.deinit(std.testing.allocator);
}
