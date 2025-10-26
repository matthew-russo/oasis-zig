const std = @import("std");

pub const RegexCursor = struct {
    const Self = @This();

    input: []const u8,
    current: usize,
    capture_groups: [][]const u8,

    pub fn init(input: []const u8, current: usize, capture_groups: [][]const u8) Self {
        return Self{
            .input = input,
            .current = current,
            .capture_groups = capture_groups,
        };
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexCursor{{ .input='{s}', .current={d}, .capture_groups=[", .{ self.input, self.current });
        for (self.capture_groups, 0..) |capture_group, idx| {
            try writer.print("{d}: '{s}', ", .{ idx, capture_group });
        }
        try writer.print("] }}", .{});
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
    const Self = @This();

    min: usize,
    max: ?usize, // null means unbounded
    greedy: bool,
};

pub const RegexAlternation = struct {
    const Self = @This();

    alternations: []const []const *RegexNode,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexAlternation {{ .alternations={{", .{});
        for (self.alternations, 0..) |sequence, idx| {
            try writer.print("{d}: [", .{idx});
            for (sequence) |node| {
                try writer.print("{f}, ", .{node});
            }
            try writer.print("], ", .{});
        }
        try writer.print("}} }}", .{});
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        for (self.alternations) |alt| {
            for (alt) |node| {
                node.deinit(allocator);
                allocator.destroy(node);
            }
            allocator.free(alt);
        }
        allocator.free(self.alternations);
    }
};

pub const RegexNode = union(enum) {
    const Self = @This();

    literal: u8,
    dot: void,
    character_class: RegexCharacterClass,
    start_of_line_anchor: void,
    end_of_line_anchor: void,
    capture_group: struct { idx: usize, node: RegexAlternation },
    alternation: RegexAlternation,
    quantified: struct { quantifier: RegexQuantifier, node: *RegexNode },
    backreference: u8,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        switch (self) {
            .literal => |lit| try writer.print("Literal({c})", .{lit}),
            .dot => try writer.print("Dot", .{}),
            .character_class => |class| try writer.print("{f}", .{class}),
            .start_of_line_anchor => try writer.print("StartOfLineAnchor", .{}),
            .end_of_line_anchor => try writer.print("EndOfLineAnchor", .{}),
            .capture_group => |cg| try writer.print("CaptureGroup {{ .idx={d}, .alternation={f} }}", .{ cg.idx, cg.node }),
            .alternation => |alternation| try writer.print("{f}", .{alternation}),
            .quantified => |q| try writer.print("Quantified {{ min={d}, max={?d}, node={f} }}", .{ q.quantifier.min, q.quantifier.max, q.node }),
            .backreference => |b| try writer.print("Backreference({d})", .{b}),
        }
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .literal => {},
            .dot => {},
            .character_class => |class| allocator.free(class.characters),
            .start_of_line_anchor => {},
            .end_of_line_anchor => {},
            .capture_group => |cg| {
                cg.node.deinit(allocator);
            },
            .alternation => |alt| {
                alt.deinit(allocator);
            },
            .quantified => |q| {
                q.node.deinit(allocator);
                allocator.destroy(q.node);
            },
            .backreference => {},
        }
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
                if (i >= pattern.len) return error.InvalidEscapeSequence;
                try tokens.append(allocator, RegexToken{ .escaped = pattern[i] });
            },
            else => try tokens.append(allocator, RegexToken{ .literal = pattern[i] }),
        }
    }

    return RegexTokens{ .tokens = try tokens.toOwnedSlice(allocator) };
}

fn parse_expression(allocator: std.mem.Allocator, tokens: RegexTokens, i: *usize, capture_group_idx: *u8) !*RegexNode {
    const len = tokens.tokens.len;

    var atom: *RegexNode = try allocator.create(RegexNode);
    errdefer allocator.destroy(atom);
    const tok = tokens.tokens[i.*];
    switch (tok) {
        .literal => |c| {
            atom.* = RegexNode{ .literal = c };
            i.* += 1;
        },
        .dot => {
            atom.* = RegexNode{ .dot = {} };
            i.* += 1;
        },
        .escaped => |c| {
            if (c == 'w') {
                const chars = try allocator.alloc(RegexCharacter, 4);
                chars[0] = RegexCharacter{ .range = .{ .start = 'a', .end = 'z' } };
                chars[1] = RegexCharacter{ .range = .{ .start = 'A', .end = 'Z' } };
                chars[2] = RegexCharacter{ .range = .{ .start = '0', .end = '9' } };
                chars[3] = RegexCharacter{ .char = '_' };
                const class = RegexCharacterClass{ .negated = false, .characters = chars };
                atom.* = RegexNode{ .character_class = class };
                i.* += 1;
            } else if (c == 'd') {
                const chars = try allocator.alloc(RegexCharacter, 1);
                chars[0] = RegexCharacter{ .range = .{ .start = '0', .end = '9' } };
                const class = RegexCharacterClass{ .negated = false, .characters = chars };
                atom.* = RegexNode{ .character_class = class };
                i.* += 1;
            } else if (std.ascii.isDigit(c)) {
                atom.* = RegexNode{ .backreference = c - '0' };
                i.* += 1;
            } else {
                std.log.err("Unsupported escape in parse_expression: {f}", .{tok});
                return error.UnsupportedEscape;
            }
        },
        .open_square_bracket => {
            var char_list = std.ArrayList(RegexCharacter).empty;
            defer char_list.deinit(allocator);

            i.* += 1;
            var negated = false;
            if (i.* < len and tokens.tokens[i.*] == RegexToken.caret) {
                negated = true;
                i.* += 1;
            }

            while (i.* < len and tokens.tokens[i.*] != RegexToken.close_square_bracket) {
                switch (tokens.tokens[i.*]) {
                    .literal => |c| {
                        if (i.* + 2 < len and tokens.tokens[i.* + 1] == RegexToken.dash and tokens.tokens[i.* + 2] == RegexToken.literal) {
                            const start = c;
                            const end = tokens.tokens[i.* + 2].literal;
                            try char_list.append(allocator, RegexCharacter{ .range = .{ .start = start, .end = end } });
                            i.* += 3;
                            continue;
                        } else {
                            try char_list.append(allocator, RegexCharacter{ .char = c });
                        }
                    },
                    .escaped => |c| {
                        if (c == 'w') {
                            try char_list.append(allocator, RegexCharacter{ .range = .{ .start = 'a', .end = 'z' } });
                            try char_list.append(allocator, RegexCharacter{ .range = .{ .start = 'A', .end = 'Z' } });
                            try char_list.append(allocator, RegexCharacter{ .range = .{ .start = '0', .end = '9' } });
                            try char_list.append(allocator, RegexCharacter{ .char = '_' });
                        } else if (c == 'd') {
                            try char_list.append(allocator, RegexCharacter{ .range = .{ .start = '0', .end = '9' } });
                        } else {
                            try char_list.append(allocator, RegexCharacter{ .char = c });
                        }
                    },
                    else => return error.UnsupportedCharacterClassToken,
                }
                i.* += 1;
            }

            if (i.* >= len or tokens.tokens[i.*] != RegexToken.close_square_bracket) return error.UnclosedCharacterClass;
            const class = RegexCharacterClass{ .negated = negated, .characters = try char_list.toOwnedSlice(allocator) };
            atom.* = RegexNode{ .character_class = class };
            i.* += 1;
        },
        .caret => {
            atom.* = RegexNode{ .start_of_line_anchor = {} };
            i.* += 1;
        },
        .dollar_sign => {
            atom.* = RegexNode{ .end_of_line_anchor = {} };
            i.* += 1;
        },
        .open_paren => {
            i.* += 1; // consume '('
            const cap_group_idx = capture_group_idx.*;
            capture_group_idx.* += 1;
            const node = try parse_alternation(allocator, tokens, i, capture_group_idx, true);
            atom.* = RegexNode{ .capture_group = .{ .idx = cap_group_idx, .node = node } };
            if (i.* >= len or tokens.tokens[i.*] != RegexToken.close_paren) return error.UnclosedParenthesis;
            i.* += 1; // consume ')'
        },
        .dash => {
            atom.* = RegexNode{ .literal = '-' };
            i.* += 1; // consume '-'
        },
        else => {
            std.log.err("Unsupported token in parse_expression: {f}", .{tok});
            return error.UnsupportedToken;
        },
    }

    // quantifiers
    if (i.* < len) {
        const qtok = tokens.tokens[i.*];
        switch (qtok) {
            .star => {
                const qn = try allocator.create(RegexNode);
                qn.* = RegexNode{ .quantified = .{ .node = atom, .quantifier = RegexQuantifier{ .min = 0, .max = null, .greedy = true } } };
                atom = qn;
                i.* += 1;
            },
            .plus => {
                const qn = try allocator.create(RegexNode);
                qn.* = RegexNode{ .quantified = .{ .node = atom, .quantifier = RegexQuantifier{ .min = 1, .max = null, .greedy = true } } };
                atom = qn;
                i.* += 1;
            },
            .question_mark => {
                const qn = try allocator.create(RegexNode);
                qn.* = RegexNode{ .quantified = .{ .node = atom, .quantifier = RegexQuantifier{ .min = 0, .max = 1, .greedy = true } } };
                atom = qn;
                i.* += 1;
            },
            else => {},
        }
    }

    return atom;
}

fn parse_alternation(allocator: std.mem.Allocator, tokens: RegexTokens, i: *usize, capture_group_idx: *u8, in_capture_group: bool) anyerror!RegexAlternation {
    const len = tokens.tokens.len;
    var nodes = std.ArrayList([]const *RegexNode).empty;
    defer nodes.deinit(allocator);

    // outer group, collecting all alternations
    while (true) {
        var acc = std.ArrayList(*RegexNode).empty;
        defer acc.deinit(allocator);

        // inner group, collecting the nodes of the alteration
        while (true) {
            const node = try parse_expression(allocator, tokens, i, capture_group_idx);
            try acc.append(allocator, node);
            if (i.* >= len or tokens.tokens[i.*] == RegexToken.pipe or tokens.tokens[i.*] == RegexToken.close_paren) break;
        }

        if (i.* >= len) {
            try nodes.append(allocator, try acc.toOwnedSlice(allocator));
            break;
        }

        if (tokens.tokens[i.*] == RegexToken.close_paren) {
            if (!in_capture_group) return error.UnexpectedCloseParen;
            try nodes.append(allocator, try acc.toOwnedSlice(allocator));
            break;
        }

        std.debug.assert(tokens.tokens[i.*] == RegexToken.pipe);
        try nodes.append(allocator, try acc.toOwnedSlice(allocator));
        i.* += 1;
    }

    return RegexAlternation{ .alternations = try nodes.toOwnedSlice(allocator) };
}

pub fn parse_tokens(allocator: std.mem.Allocator, tokens: RegexTokens) !Regex {
    var idx: usize = 0;
    var capture_group_idx: u8 = 1;
    const root = try parse_alternation(allocator, tokens, &idx, &capture_group_idx, false);
    return Regex{
        .allocator = allocator,
        .root = root,
        .capture_group_buffer = try allocator.alloc([]const u8, capture_group_idx - 1),
    };
}

// Atomic matcher: matches a single node (possibly complex like a sequence or alternation)
// but does not perform continuation/backtracking for the parent sequence. Continuation
// and backtracking live in `match_nodes` only.
fn match_single_node(allocator: std.mem.Allocator, node: *const RegexNode, cursor: *RegexCursor) bool {
    std.log.debug("Attempting to match node: {f} against {f}", .{ node, cursor });
    const input_len = cursor.input.len;
    switch (node.*) {
        .literal => |lit| {
            if (cursor.current >= input_len) return false;
            if (cursor.input[cursor.current] == lit) {
                cursor.current += 1;
                return true;
            }
            return false;
        },
        .dot => {
            if (cursor.current < input_len) {
                cursor.current += 1;
                return true;
            }
            return false;
        },
        .character_class => |class| {
            if (cursor.current >= input_len) return false;
            const c = cursor.input[cursor.current];
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
            if (class.negated) matched = !matched;
            if (matched) {
                cursor.current += 1;
                return true;
            }
            return false;
        },
        .start_of_line_anchor => {
            if (cursor.current == 0 or cursor.input[cursor.current - 1] == '\n') return true;
            return false;
        },
        .end_of_line_anchor => {
            if (cursor.current == input_len or cursor.input[cursor.current] == '\n') return true;
            return false;
        },
        .capture_group => |cg| {
            std.log.debug("Attempting to match capture group {d}, {f}", .{ cg.idx, cursor });
            const capture_start = cursor.current;
            const alternation_matches = match_alternation(allocator, cg.node, cursor);
            if (!alternation_matches) return false;
            const capture_end = cursor.current;
            std.log.debug("Capture group {d} matched from {d} to {d}, cursor: {f}", .{ cg.idx, capture_start, capture_end, cursor });
            std.log.debug("Successfully matched capture group {d}={s}, current cursor: {f}", .{ cg.idx, cursor.input[capture_start..capture_end], cursor });
            cursor.capture_groups[cg.idx - 1] = cursor.input[capture_start..capture_end];
            return true;
        },
        .backreference => |cg_idx| {
            std.log.debug("Attempting to match backreference to capture group {d}, {f}", .{ cg_idx, cursor });
            // for backreferences, we construct a sequence of literal nodes on the fly using the string that was previously matched
            const captured = cursor.capture_groups[cg_idx - 1];
            for (captured) |c| {
                const inline_node = RegexNode{ .literal = c };
                if (!match_single_node(allocator, &inline_node, cursor)) return false;
            }
            return true;
        },
        else => std.debug.panic("Invalid Node passed to `match_single_node`: {f}", .{node}),
    }
}

fn match_alternation(allocator: std.mem.Allocator, alternation: RegexAlternation, cursor: *RegexCursor) bool {
    std.log.debug("Attempting to match Alternation: {f} against {f}", .{ alternation, cursor });
    const before = cursor.*;
    for (alternation.alternations) |sequence| {
        cursor.* = before;
        if (match_nodes(allocator, sequence, 0, cursor)) return true;
    }
    cursor.* = before;
    return false;
}

fn match_nodes(allocator: std.mem.Allocator, nodes: []const *RegexNode, idx: usize, cursor: *RegexCursor) bool {
    const n = nodes.len;
    if (idx >= n) return true;

    const node = nodes[idx];
    switch (node.*) {
        .quantified => |q| {
            const start_pos = cursor.current;
            var positions = std.ArrayList(usize).empty;
            defer positions.deinit(allocator);

            // greedy matches need to backtrack. for example, with the following pattern `ca+ats` and the input `caaats`,
            // matching `a+` would naively eat all 3 `a`'s, however then we're left without any remaining `a`'s to match.
            // to handle this, we first match as many of the quantifier nodes as possible, recording the position of each
            // pattern we match.
            //
            // with all match positions in hand, we then walk backwards through them, attempting to match the rest of the
            // nodes. we prioritize the longest match and if we walk too far back such that we don't satisfy our minimum
            // amount, we break out.

            var count: usize = 0;
            while (true) {
                if (q.quantifier.max) |max| if (count >= max) break;
                const before = cursor.current;
                if (!match_single_node(allocator, q.node, cursor)) break;
                if (cursor.current == before) break; // avoid infinite loop on zero-width
                positions.append(allocator, cursor.current) catch unreachable;
                count += 1;
            }

            if (q.quantifier.greedy) {
                var k: usize = positions.items.len;
                while (true) {
                    if (k < q.quantifier.min) break;
                    if (k == 0) {
                        cursor.current = start_pos;
                    } else {
                        cursor.current = positions.items[k - 1];
                    }
                    if (match_nodes(allocator, nodes, idx + 1, cursor)) return true;
                    if (k == 0) break;
                    k -= 1;
                }
            } else {
                var k: usize = q.quantifier.min;
                while (k <= positions.items.len) {
                    if (k == 0) {
                        cursor.current = start_pos;
                    } else {
                        cursor.current = positions.items[k - 1];
                    }
                    if (match_nodes(allocator, nodes, idx + 1, cursor)) return true;
                    k += 1;
                }
            }

            cursor.current = start_pos;
            return false;
        },
        .alternation => |alternation| {
            return match_alternation(allocator, alternation, cursor);
        },
        else => {
            const before = cursor.current;
            if (!match_single_node(allocator, node, cursor)) return false;
            if (match_nodes(allocator, nodes, idx + 1, cursor)) return true;
            cursor.current = before;
            return false;
        },
    }
}

pub const Regex = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    root: RegexAlternation,
    capture_group_buffer: [][]const u8,

    pub fn matches(self: *const Self, input: []const u8) bool {
        std.log.debug("Attempting to match input '{s}' against regex {f}", .{ input, self });
        var i: usize = 0;
        while (i <= input.len) {
            var cursor = RegexCursor.init(input, i, self.capture_group_buffer);
            if (match_alternation(self.allocator, self.root, &cursor)) return true;
            i += 1;
        }
        return false;
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("Regex{{ .root = {f} }}", .{self.root});
    }

    pub fn deinit(self: *const Self) void {
        self.root.deinit(self.allocator);
        self.allocator.free(self.capture_group_buffer);
    }
};

fn test_regex(pattern: []const u8, input: []const u8, expect_matches: bool) !void {
    std.testing.log_level = .err;

    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, pattern);
    defer allocator.free(tokens.tokens);

    const regex = try parse_tokens(allocator, tokens);
    defer regex.deinit();

    try std.testing.expect(regex.matches(input) == expect_matches);
}

// literal characters

test "regex 'd' matches dog" {
    try test_regex("d", "dog", true);
}

test "regex 'f' does not match dog" {
    try test_regex("f", "dog", false);
}

// character classes

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

// negated character classes

test "regex '[^abc]' matches 'cat'" {
    try test_regex("[^abc]", "cat", true);
}

test "regex '[^abc]' does not match 'cab'" {
    try test_regex("[^abc]", "cab", false);
}

// combined patterns

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

// start of line anchor

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

// end of line anchor

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

// quantifiers

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

test "regex 'ca+ats' matches 'caaats'" {
    try test_regex("ca+ats", "caaats", true);
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

test "regex 'ca*t' matches 'ct'" {
    try test_regex("ca*t", "ct", true);
}

test "regex 'ca*t' matches 'caaat'" {
    try test_regex("ca*t", "caaat", true);
}

test "regex 'ca*t' does not match 'dog'" {
    try test_regex("ca*t", "dog", false);
}

test "regex 'k\\d*t' matches 'kt'" {
    try test_regex("k\\d*t", "kt", true);
}

test "regex 'k\\d*t' matches 'k1t'" {
    try test_regex("k\\d*t", "k1t", true);
}

test "regex 'k\\d*t' does not match 'kabct'" {
    try test_regex("k\\d*t", "kabct", false);
}

test "regex 'k[abc]*t' matches 'kt'" {
    try test_regex("k[abc]*t", "kt", true);
}

test "regex 'k[abc]*t' matches 'kat'" {
    try test_regex("k[abc]*t", "kat", true);
}

test "regex 'k[abc]*t' matches 'kabct'" {
    try test_regex("k[abc]*t", "kabct", true);
}

test "regex 'k[abc]*t' does not match 'kaxyzt'" {
    try test_regex("k[abc]*t", "kaxyzt", false);
}

// wildcard

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

// alternations

test "regex 'cat|dog' matches 'cat'" {
    try test_regex("cat|dog", "cat", true);
}

test "regex 'cat|dog' matches 'dog'" {
    try test_regex("cat|dog", "dog", true);
}

// capture groups and alternations

test "regex '(cat|dog)' matches 'cat'" {
    try test_regex("(cat|dog)", "cat", true);
}

test "regex '(cat|dog)' matches 'dog'" {
    try test_regex("(cat|dog)", "dog", true);
}

test "regex '(cat|dog)' does not match 'apple'" {
    try test_regex("(cat|dog)", "apple", false);
}

test "regex '(cat|dog)' matches 'doghouse'" {
    try test_regex("(cat|dog)", "doghouse", true);
}

test "regex 'I like (cats|dogs)' matches 'I like cats'" {
    try test_regex("I like (cats|dogs)", "I like cats", true);
}

test "regex 'I like (cats|dogs)' matches 'I like dogs'" {
    try test_regex("I like (cats|dogs)", "I like dogs", true);
}

test "regex '(red|blue|green)' matches 'blue'" {
    try test_regex("(red|blue|green)", "blue", true);
}

// backreferences

test "regex '(cat) and \\1' matches 'cat and cat'" {
    try test_regex("(cat) and \\1", "cat and cat", true);
}

test "regex '(cat) and \\1' does not match 'cat and dog'" {
    try test_regex("(cat) and \\1", "cat and dog", false);
}

test "regex '(\\w+) and \\1' matches 'cat and cat'" {
    try test_regex("(\\w+) and \\1", "cat and cat", true);
}

test "regex '(\\w+) and \\1' matches 'dog and dog'" {
    try test_regex("(\\w+) and \\1", "dog and dog", true);
}

test "regex '(\\w+) and \\1' does not match 'cat and dog'" {
    try test_regex("(\\w+) and \\1", "cat and dog", false);
}

test "regex '(\\d+)-\\1' matches '123-123'" {
    try test_regex("(\\d+)-\\1", "123-123", true);
}

test "regex '(\\d+) (\\w+) and \\1 \\2' matches '3 red and 3 red'" {
    try test_regex("(\\d+) (\\w+) and \\1 \\2", "3 red and 3 red", true);
}

test "regex '(\\d+) (\\w+) and \\1 \\2' does not match '3 red and 4 red'" {
    try test_regex("(\\d+) (\\w+) and \\1 \\2", "3 red and 4 red", false);
}

test "regex '(\\d+) (\\w+) and \\1 \\2' does not match '3 red and 3 blue'" {
    try test_regex("(\\d+) (\\w+) and \\1 \\2", "3 red and 3 blue", false);
}

test "regex '(cat) and (dog) are \\2 and \\1' matches 'cat and dog are dog and cat'" {
    try test_regex("(cat) and (dog) are \\2 and \\1", "cat and dog are dog and cat", true);
}

test "regex '(\\w+)-(\\w+)-(\\1)-(\\2)' matches 'foo-bar-foo-bar'" {
    try test_regex("(\\w+)-(\\w+)-(\\1)-(\\2)", "foo-bar-foo-bar", true);
}

test "regex '((dog)-\\2)' matches 'dog-dog'" {
    try test_regex("((dog)-\\2)", "dog-dog", true);
}

test "regex '((\\w+) \\2) and \\1' matches 'cat cat and cat cat'" {
    try test_regex("((\\w+) \\2) and \\1", "cat cat and cat cat", true);
}

test "regex '((cat) and \\2) is the same as \\1' matches 'cat and cat is the same as cat'" {
    try test_regex("((cat) and \\2) is the same as \\1", "cat and cat is the same as cat and cat", true);
}
