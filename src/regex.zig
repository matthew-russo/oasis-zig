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

    pub fn evaluate(self: *const Self, cursor: *RegexCursor) RegexEvaluationInternal {
        std.log.debug("Evaluating {f} against '{s}'", .{ self.*, cursor.input[cursor.current..] });
        // while (cursor.current <= cursor.input.len) {
        switch (self.*) {
            .literal => |lit| {
                if (cursor.current >= cursor.input.len) {
                    return RegexEvaluationInternal{ .matches = false };
                }
                if (cursor.input[cursor.current] == lit) {
                    cursor.current += 1;
                    return RegexEvaluationInternal{ .matches = true };
                }
            },
            .dot => {
                if (cursor.current < cursor.input.len) {
                    cursor.current += 1;
                    return RegexEvaluationInternal{ .matches = true };
                }
            },
            .character_class => |class| {
                for (cursor.input[cursor.current..]) |c| {
                    var matched = false;
                    for (class.characters) |cc| {
                        switch (cc) {
                            .char => |ch| {
                                if (c == ch) matched = true;
                            },
                            .range => |r| {
                                if (c >= r.start and c <= r.end) matched = true;
                            },
                        }
                        if (matched) break;
                    }
                    if (class.negated) {
                        if (!matched) {
                            cursor.current += 1;
                            return RegexEvaluationInternal{ .matches = true };
                        }
                    } else {
                        if (matched) {
                            cursor.current += 1;
                            return RegexEvaluationInternal{ .matches = true };
                        }
                    }
                }
            },
            .start_of_line_anchor => {
                if (cursor.current == 0 or cursor.input[cursor.current - 1] == '\n') {
                    return RegexEvaluationInternal{ .matches = true };
                } else {
                    return RegexEvaluationInternal{ .matches = false };
                }
            },
            .end_of_line_anchor => {
                std.log.debug("At end_of_line_anchor, cursor.current={d}, input.len={d}, next char='{c}'", .{ cursor.current, cursor.input.len, if (cursor.current < cursor.input.len) cursor.input[cursor.current] else '?' });
                if (cursor.current == cursor.input.len or cursor.input[cursor.current] == '\n') {
                    return RegexEvaluationInternal{ .matches = true };
                } else {
                    return RegexEvaluationInternal{ .matches = false };
                }
            },
            .sequence => |nodes| {
                for (nodes) |node| {
                    const cursor_before = cursor.*;
                    const evaluation = node.evaluate(cursor);
                    std.log.debug("Evaluating node: {f}, Cursor before: {f}, Cursor after: {f}, Result: {}", .{ node, cursor_before, cursor, evaluation.matches });

                    if (!evaluation.matches) {
                        return RegexEvaluationInternal{ .matches = false };
                    }
                }
                return RegexEvaluationInternal{ .matches = true };
            },
            .alternation => |nodes| {
                for (nodes) |node| {
                    const evaluation = node.evaluate(cursor);
                    if (evaluation.matches) return evaluation;
                }
            },
            .quantified => |q| {
                std.log.debug("Evaluating '{s}' against Quantified min={d}, max={?d}, greedy={}, node={f}", .{ cursor.input[cursor.current..], q.quantifier.min, q.quantifier.max, q.quantifier.greedy, q.node });
                if (!q.quantifier.greedy) {
                    std.debug.panic("TODO: impl non-greedy quantifiers", .{});
                }
                var i: usize = 0;
                while (true) {
                    if (q.quantifier.max) |max| {
                        if (i >= max) {
                            break;
                        }
                    }
                    const evaluation = q.node.evaluate(cursor);
                    if (evaluation.matches) {
                        i += 1;
                    } else {
                        break;
                    }
                }
                if (i < q.quantifier.min) {
                    return RegexEvaluationInternal{ .matches = false };
                } else {
                    return RegexEvaluationInternal{ .matches = true };
                }
            },
        }
        return RegexEvaluationInternal{ .matches = false };
        // }
        // return RegexEvaluationInternal{ .matches = false };
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
        var i: usize = 0;
        while (true) {
            std.log.debug("Trying to match string '{s}' against regex: {f}", .{ input[i..], self.root });
            var cursor = RegexCursor{
                .input = input,
                .current = i,
            };
            const evaluation = self.root.evaluate(&cursor);

            if (evaluation.matches) {
                return true;
            } else {
                i += 1;
            }

            if (i > input.len) {
                return false;
            }
        }
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("{f}", .{self.root});
    }

    pub fn deinit(self: *const Self) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
    }
};

pub fn tokenize(allocator: std.mem.Allocator, pattern: []const u8) !RegexTokens {
    var tokens = std.ArrayList(RegexToken).empty;
    defer tokens.deinit(allocator);

    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        switch (pattern[i]) {
            '.' => try tokens.append(allocator, RegexToken.dot),
            ',' => try tokens.append(allocator, RegexToken.comma),
            '-' => try tokens.append(allocator, RegexToken.dash),
            '*' => try tokens.append(allocator, RegexToken.star),
            '+' => try tokens.append(allocator, RegexToken.plus),
            '?' => try tokens.append(allocator, RegexToken.question_mark),
            '|' => try tokens.append(allocator, RegexToken.pipe),
            '^' => try tokens.append(allocator, RegexToken.caret),
            '$' => try tokens.append(allocator, RegexToken.dollar_sign),
            '[' => try tokens.append(allocator, RegexToken.open_square_bracket),
            ']' => try tokens.append(allocator, RegexToken.close_square_bracket),
            '{' => try tokens.append(allocator, RegexToken.open_curly_bracket),
            '}' => try tokens.append(allocator, RegexToken.close_curly_bracket),
            '(' => try tokens.append(allocator, RegexToken.open_paren),
            ')' => try tokens.append(allocator, RegexToken.close_paren),
            '\\' => {
                i += 1;
                if (i >= pattern.len) {
                    return error.InvalidEscapeSequence;
                }
                try tokens.append(allocator, RegexToken{ .escaped = pattern[i] });
            },
            else => {
                try tokens.append(allocator, RegexToken{ .literal = pattern[i] });
            },
        }
    }

    return RegexTokens{ .tokens = try tokens.toOwnedSlice(allocator) };
}

pub fn parse_tokens(allocator: std.mem.Allocator, tokens: RegexTokens) !Regex {
    var nodes = std.ArrayList(*RegexNode).empty;
    defer nodes.deinit(allocator);

    var i: usize = 0;
    while (i < tokens.tokens.len) : (i += 1) {
        const token = tokens.tokens[i];
        const node = switch (token) {
            .literal => |c| blk: {
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .literal = c };
                break :blk node;
            },
            .dot => blk: {
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .dot = {} };
                break :blk node;
            },
            .escaped => |c| blk: {
                if (c == 'w') {
                    // \w = [a-zA-Z0-9_]
                    const chars = try allocator.alloc(RegexCharacter, 4);
                    chars[0] = RegexCharacter{ .range = .{ .start = 'a', .end = 'z' } };
                    chars[1] = RegexCharacter{ .range = .{ .start = 'A', .end = 'Z' } };
                    chars[2] = RegexCharacter{ .range = .{ .start = '0', .end = '9' } };
                    chars[3] = RegexCharacter{ .char = '_' };
                    const class = RegexCharacterClass{ .negated = false, .characters = chars };
                    const node = try allocator.create(RegexNode);
                    node.* = RegexNode{ .character_class = class };
                    break :blk node;
                } else if (c == 'd') {
                    // \d = [0-9]
                    const chars = try allocator.alloc(RegexCharacter, 1);
                    chars[0] = RegexCharacter{ .range = .{ .start = '0', .end = '9' } };
                    const class = RegexCharacterClass{ .negated = false, .characters = chars };
                    const node = try allocator.create(RegexNode);
                    node.* = RegexNode{ .character_class = class };
                    break :blk node;
                } else {
                    return error.UnsupportedEscape;
                }
            },
            .open_square_bracket => blk: {
                var char_list = std.ArrayList(RegexCharacter).empty;
                defer char_list.deinit(allocator);

                i += 1;
                var negated = false;
                if (i < tokens.tokens.len and tokens.tokens[i] == RegexToken.caret) {
                    negated = true;
                    i += 1;
                }

                while (i < tokens.tokens.len and tokens.tokens[i] != RegexToken.close_square_bracket) {
                    switch (tokens.tokens[i]) {
                        .literal => |c| {
                            // Check for range: [a-z]
                            if (i + 2 < tokens.tokens.len and tokens.tokens[i + 1] == RegexToken.dash and tokens.tokens[i + 2] == RegexToken.literal) {
                                const start = c;
                                const end = tokens.tokens[i + 2].literal;
                                try char_list.append(allocator, RegexCharacter{ .range = .{ .start = start, .end = end } });
                                i += 2; // skip over '-' and end char
                            } else {
                                try char_list.append(allocator, RegexCharacter{ .char = c });
                            }
                        },
                        .escaped => |c| {
                            // Support escapes like \d, \w, etc inside character classes
                            if (c == 'w') {
                                try char_list.append(allocator, RegexCharacter{ .range = .{ .start = 'a', .end = 'z' } });
                                try char_list.append(allocator, RegexCharacter{ .range = .{ .start = 'A', .end = 'Z' } });
                                try char_list.append(allocator, RegexCharacter{ .range = .{ .start = '0', .end = '9' } });
                                try char_list.append(allocator, RegexCharacter{ .char = '_' });
                            } else if (c == 'd') {
                                try char_list.append(allocator, RegexCharacter{ .range = .{ .start = '0', .end = '9' } });
                            } else {
                                // fallback: treat as literal
                                try char_list.append(allocator, RegexCharacter{ .char = c });
                            }
                        },
                        // TODO impl escaped character support, also many control
                        // characters are actually literals when in a character class,
                        // e.g. `[(]` matches the `(` character literally
                        else => return error.UnsupportedCharacterClassToken,
                    }
                    i += 1;
                }

                if (i >= tokens.tokens.len or tokens.tokens[i] != RegexToken.close_square_bracket) {
                    return error.UnclosedCharacterClass;
                }

                // No need to increment i here, the for loop will do it

                const class = RegexCharacterClass{ .negated = negated, .characters = try char_list.toOwnedSlice(allocator) };
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .character_class = class };
                break :blk node;
            },
            .caret => blk: {
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .start_of_line_anchor = {} };
                break :blk node;
            },
            .dollar_sign => blk: {
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .end_of_line_anchor = {} };
                break :blk node;
            },
            .plus => blk: {
                const prev_node = nodes.pop() orelse std.debug.panic("Found quantifier with no previous node", .{});
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .quantified = .{
                    .node = prev_node,
                    .quantifier = RegexQuantifier{ .min = 1, .max = null, .greedy = true },
                } };
                break :blk node;
            },
            .star => blk: {
                const prev_node = nodes.pop() orelse std.debug.panic("Found quantifier with no previous node", .{});
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .quantified = .{
                    .node = prev_node,
                    .quantifier = RegexQuantifier{ .min = 0, .max = null, .greedy = true },
                } };
                break :blk node;
            },
            .question_mark => blk: {
                const prev_node = nodes.pop() orelse std.debug.panic("Found quantifier with no previous node", .{});
                const node = try allocator.create(RegexNode);
                node.* = RegexNode{ .quantified = .{
                    .node = prev_node,
                    .quantifier = RegexQuantifier{ .min = 0, .max = 1, .greedy = true },
                } };
                break :blk node;
            },
            else => return error.UnsupportedToken,
        };
        try nodes.append(allocator, node);
    }

    if (nodes.items.len == 1) {
        return Regex{
            .allocator = allocator,
            .root = nodes.items[0],
        };
    } else {
        const seq_node = try allocator.create(RegexNode);
        seq_node.* = RegexNode{ .sequence = try nodes.toOwnedSlice(allocator) };
        return Regex{
            .allocator = allocator,
            .root = seq_node,
        };
    }
}

const RegexEvaluationInternal = struct {
    const Self = @This();

    matches: bool,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexEvaluationInternal{{ .matches={} }}", .{self.matches});
    }
};

fn test_regex(pattern: []const u8, input: []const u8, expect_matches: bool) !void {
    const allocator = std.testing.allocator;

    const tokens = try tokenize(allocator, pattern);
    defer allocator.free(tokens.tokens);

    const regex = try parse_tokens(allocator, tokens);
    defer regex.deinit();

    try std.testing.expect(regex.matches(input) == expect_matches);
}

test "regex 'd' matches dog" {
    try test_regex("d", "dog", true);
}

test "regex 'f' does not match dog" {
    try test_regex("f", "dog", false);
}

test "regex '\\d' matches 123" {
    try test_regex("\\d", "123", true);
}

test "regex '\\d' does not match apple" {
    try test_regex("\\d", "apple", false);
}

test "regex '\\w' matches banana" {
    try test_regex("\\w", "banana", true);
}

test "regex '\\w' matches PINEAPPLE" {
    try test_regex("\\w", "PINEAPPLE", true);
}

test "regex '\\w' matches 296" {
    try test_regex("\\w", "296", true);
}

test "regex '\\w' matches ×-#_×%=" {
    try test_regex("\\w", "×-#_×%=", true);
}

test "regex '\\w' does not match +#=-÷%" {
    try test_regex("\\w", "+#=-÷%", false);
}

test "regex '[abc]' matches 'apple'" {
    try test_regex("[abc]", "apple", true);
}

test "regex '[abc]' does not match 'dog'" {
    try test_regex("[abc]", "dog", false);
}

test "regex '[^abc]' matches 'cat'" {
    try test_regex("[^abc]", "cat", true);
}

test "regex '[^abc]' does not match 'cab'" {
    try test_regex("[^abc]", "cab", false);
}

test "regex '\\d apple' matches '1 apple'" {
    try test_regex("\\d apple", "1 apple", true);
}

test "regex '\\d apple' does not match '1 orange'" {
    try test_regex("\\d apple", "1 orange", false);
}

test "regex '\\d\\d\\d apple' matches '100 apples'" {
    try test_regex("\\d\\d\\d apple", "100 apples", true);
}

test "regex '\\d\\d\\d apple' does not match '1 apple'" {
    try test_regex("\\d\\d\\d apple", "1 apple", false);
}

test "regex '\\d \\w\\w\\ws' matches '3 dogs'" {
    try test_regex("\\d \\w\\w\\ws", "3 dogs", true);
}

test "regex '\\d \\w\\w\\ws' matches '4 cats'" {
    try test_regex("\\d \\w\\w\\ws", "4 cats", true);
}

test "regex '\\d \\w\\w\\ws' does not match '1 dog'" {
    try test_regex("\\d \\w\\w\\ws", "1 dog", false);
}

test "regex '^log' matches 'log'" {
    try test_regex("^log", "log", true);
}

test "regex '^log' matches 'logs'" {
    try test_regex("^log", "logs", true);
}

test "regex '^log' does not match 'slog'" {
    try test_regex("^log", "slog", false);
}

test "regex '^\\d\\d\\d' matches '123abc'" {
    try test_regex("^\\d\\d\\d", "123abc", true);
}

test "regex 'dog$' matches 'dog'" {
    try test_regex("dog$", "dog", true);
}

test "regex 'dog$' matches 'hotdog'" {
    try test_regex("dog$", "hotdog", true);
}

test "regex '\\d\\d\\d$' matches 'abc123'" {
    try test_regex("\\d\\d\\d$", "abc123", true);
}

test "regex '\\w\\w\\w$' does not match 'abc123@'" {
    try test_regex("\\w\\w\\w$", "abc123@", false);
}

test "regex '\\w\\w\\w$' matches 'abc123cde'" {
    try test_regex("\\w\\w\\w$", "abc123cde", true);
}

test "regex 'a+' matches 'apple'" {
    try test_regex("a+", "apple", true);
}

test "regex 'a+' matches 'SaaS'" {
    try test_regex("a+", "SaaS", true);
}

test "regex 'a+' does not match 'dog'" {
    try test_regex("a+", "dog", false);
}

test "regex 'ca+ts' matches 'cats'" {
    try test_regex("ca+ts", "cats", true);
}

test "regex 'ca+ts' matches 'caats'" {
    try test_regex("ca+ts", "caats", true);
}

test "regex 'ca+ts' does not match 'cts'" {
    try test_regex("ca+ts", "cts", false);
}

test "regex '\\d+' matches '123'" {
    try test_regex("\\d+", "123", true);
}

test "regex 'dogs?' matches 'dog'" {
    try test_regex("dogs?", "dog", true);
}

test "regex 'dogs?' matches 'dogs'" {
    try test_regex("dogs?", "dogs", true);
}

test "regex 'dogs?$' does not match 'dogss'" {
    try test_regex("dogs?$", "dogss", false);
}

test "regex 'dogs?' does not match 'cat'" {
    try test_regex("dogs?", "cat", false);
}

test "regex 'colou?r' matches 'color'" {
    try test_regex("colou?r", "color", true);
}

test "regex 'colou?r' matches 'colour'" {
    try test_regex("colou?r", "colour", true);
}

test "regex '\\d?' matches '5'" {
    try test_regex("\\d?", "5", true);
}

test "regex '\\d?' matches ''" {
    try test_regex("\\d?", "", true);
}

test "regex 'd.g' matches 'dog'" {
    try test_regex("d.g", "dog", true);
}

test "regex 'd.g' matches 'dag'" {
    try test_regex("d.g", "dag", true);
}

test "regex 'd.g' matches 'd9g'" {
    try test_regex("d.g", "d9g", true);
}

test "regex 'd.g' does not match 'cog'" {
    try test_regex("d.g", "cog", false);
}

test "regex 'd.g' does not match 'dg'" {
    try test_regex("d.g", "dg", false);
}

test "regex '...' matches 'cat'" {
    try test_regex("...", "cat", true);
}

test "regex '.\\d.' matches 'a1b'" {
    try test_regex(".\\d.", "a1b", true);
}
