const std = @import("std");

pub const RegexCursor = struct {
    const Self = @This();

    input: []const u8,
    current: usize,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexCursor{{ .input='{s}', .current={d} }}", .{ self.input, self.current });
    }
};

pub const RegexToken = union(enum) {
    const Self = @This();

    literal: u8,
    escaped: u8, // some character preceded by a backslash
    dot: void, // .
    comma: void, // ,
    dash: void, // -
    star: void, // *
    plus: void, // +
    question_mark: void, // ?
    pipe: void, // |
    caret: void, // ^
    dollar_sign: void, // $
    open_square_bracket: void, // [
    close_square_bracket: void, // ]
    open_curly_bracket: void, // {
    close_curly_bracket: void, // }
    open_paren: void, // (
    close_paren: void, // )

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        switch (self) {
            .literal => |c| try writer.print("Literal({c})", .{c}),
            .escaped => |c| try writer.print("Escaped({c})", .{c}),
            .dot => try writer.print("Dot", .{}),
            .comma => try writer.print("Comma", .{}),
            .dash => try writer.print("Dash", .{}),
            .star => try writer.print("Star", .{}),
            .plus => try writer.print("Plus", .{}),
            .question_mark => try writer.print("QuestionMark", .{}),
            .pipe => try writer.print("Pipe", .{}),
            .caret => try writer.print("Caret", .{}),
            .dollar_sign => try writer.print("DollarSign", .{}),
            .open_square_bracket => try writer.print("OpenSquareBracket", .{}),
            .close_square_bracket => try writer.print("CloseSquareBracket", .{}),
            .open_curly_bracket => try writer.print("OpenCurlyBracket", .{}),
            .close_curly_bracket => try writer.print("CloseCurlyBracket", .{}),
            .open_paren => try writer.print("OpenParen", .{}),
            .close_paren => try writer.print("CloseParen", .{}),
        }
    }
};

pub const RegexTokens = struct {
    const Self = @This();

    tokens: []const RegexToken,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexTokens([", .{});
        for (self.tokens) |token| {
            try writer.print("{f}, ", .{token});
        }
        try writer.print("])", .{});
    }
};

pub const RegexCharacter = union(enum) {
    const Self = @This();

    char: u8,
    range: struct { start: u8, end: u8 },

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        switch (self) {
            .char => |c| try writer.print("RegexCharacter::Char({c})", .{c}),
            .range => |r| try writer.print("RegexCharacter::Range({c}-{c})", .{ r.start, r.end }),
        }
    }
};

pub const RegexCharacterClass = struct {
    const Self = @This();

    negated: bool,
    characters: []RegexCharacter,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexCharacterClass {{ .negated={}, .chars=[", .{self.negated});
        for (self.characters) |character| {
            try writer.print("{f}, ", .{character});
        }
        try writer.print("] }}", .{});
    }
};

pub const RegexQuantifier = struct {
    min: usize,
    max: ?usize, // null means unbounded
    greedy: bool,
};

pub const RegexNode = union(enum) {
    const Self = @This();

    literal: u8,
    dot: void,
    character_class: RegexCharacterClass,
    start_of_line_anchor: void,
    end_of_line_anchor: void,
    sequence: []*RegexNode,
    alternation: []*RegexNode,
    quantified: struct {
        node: *RegexNode,
        quantifier: RegexQuantifier,
    },

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        switch (self) {
            .literal => |lit| try writer.print("Literal({c})", .{lit}),
            .dot => try writer.print("Dot", .{}),
            .character_class => |class| {
                try writer.print("{f}", .{class});
            },
            .start_of_line_anchor => try writer.print("StartOfLineAnchor", .{}),
            .end_of_line_anchor => try writer.print("EndOfLineAnchor", .{}),
            .sequence => |nodes| {
                try writer.print("Sequence {{ .nodes=[", .{});
                for (nodes) |node| {
                    try writer.print("{f}, ", .{node});
                }
                try writer.print("] }}", .{});
            },
            .alternation => |nodes| {
                try writer.print("Alternation {{ .nodes=[", .{});
                for (nodes) |node| {
                    try writer.print("{f}, ", .{node});
                }
                try writer.print("] }}", .{});
            },
            .quantified => |q| try writer.print("Quantified {{ min={d}, max={?d}, node={f} }}", .{ q.quantifier.min, q.quantifier.max, q.node }),
        }
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .literal => {},
            .dot => {},
            .character_class => |class| {
                allocator.free(class.characters);
            },
            .start_of_line_anchor => {},
            .end_of_line_anchor => {},
            .sequence => |nodes| {
                for (nodes) |node| {
                    node.deinit(allocator);
                    allocator.destroy(node);
                }
                allocator.free(nodes);
            },
            .alternation => |nodes| {
                for (nodes) |node| {
                    node.deinit(allocator);
                    allocator.destroy(node);
                }
                allocator.free(nodes);
            },
            .quantified => |q| {
                q.node.deinit(allocator);
                allocator.destroy(q.node);
            },
        }
    }
};

pub const Regex = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    root: *RegexNode,

    pub fn matches(self: *const Self, input: []const u8) bool {
        _ = self;
        _ = input;
        std.debug.panic("TODO: impl Regex.matches", .{});
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("{f}", .{self.root});
    }

    pub fn deinit(self: *const Self) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
    }
};
