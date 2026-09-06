//! This is an inefficient, partial implementation of Regex evaluation. Its current form exists to learn about regexes, not to make an
//! efficient, production ready regex engine. It currently supports capture groups, backreferences, digit and word character classes,
//! alternations, and quantifiers. At some point once I deem funtionality sufficient, I'll work on converting it to a finite automaton.

const std = @import("std");

const EMPTY_SLICE: []const u8 = "";

// CaptureRef represents a single capture group's start position and length in the input string
pub const CaptureRef = struct {
    const Self = @This();

    start: usize,
    len: usize,

    pub fn get_slice(self: Self, input: []const u8) []const u8 {
        if (self.len == 0) return EMPTY_SLICE;
        return input[self.start .. self.start + self.len];
    }
};

// Snapshot represents a complete state of a regex match attempt, containing
// the cursor position and all capture group metadata at that point
pub const Snapshot = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    current: usize,
    refs: []CaptureRef,

    pub fn init(allocator: std.mem.Allocator, current: usize, refs: []const CaptureRef) !Self {
        const owned_refs = try allocator.alloc(CaptureRef, refs.len);
        std.mem.copyForwards(CaptureRef, owned_refs, refs);
        return Self{
            .allocator = allocator,
            .current = current,
            .refs = owned_refs,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.refs);
    }
};

// Cursor's represent the current state of a regex match attempt, containing the input string, the current position in the string,
// and any capture groups that have been matched so far.
pub const RegexCursor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    input: []const u8,
    current: usize,
    captures: []CaptureRef,

    pub fn init(allocator: std.mem.Allocator, input: []const u8, current: usize, num_captures: usize) !Self {
        const captures = try allocator.alloc(CaptureRef, num_captures);
        for (captures) |*cap| {
            cap.* = CaptureRef{ .start = 0, .len = 0 };
        }
        return Self{
            .allocator = allocator,
            .input = input,
            .current = current,
            .captures = captures,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.captures);
    }

    pub fn get_capture(self: Self, idx: usize) []const u8 {
        return self.captures[idx].get_slice(self.input);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("RegexCursor{{ .input='{s}', .current={d}, .captures=[", .{ self.input, self.current });
        for (self.captures, 0..) |capture, idx| {
            const slice = capture.get_slice(self.input);
            try writer.print("{d}: '{s}'(@{d}), ", .{ idx, slice, capture.start });
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

// Wrapper struct to provide a sane format method
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

fn tokenize(allocator: std.mem.Allocator, pattern: []const u8) !RegexTokens {
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

fn parse_number(tokens: RegexTokens, i: *usize) ?usize {
    const len = tokens.tokens.len;
    var val: usize = 0;
    var parsed: bool = false;
    while (i.* < len) {
        const t = tokens.tokens[i.*];
        switch (t) {
            .literal => |c| {
                if (!std.ascii.isDigit(c)) break;
                val = val * 10 + (c - '0');
                i.* += 1;
                parsed = true;
                continue;
            },
            else => {},
        }
        break;
    }
    if (!parsed) return null;
    return val;
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
        .comma => {
            atom.* = RegexNode{ .literal = ',' };
            i.* += 1; // consume ','
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
            .open_curly_bracket => {
                i.* += 1; // consume '{'

                const min = parse_number(tokens, i) orelse return error.InvalidQuantifier;

                var max_val: ?usize = min;
                if (i.* < len and tokens.tokens[i.*] == RegexToken.comma) {
                    i.* += 1; // consume ','
                    max_val = parse_number(tokens, i);
                }

                if (i.* >= len or tokens.tokens[i.*] != RegexToken.close_curly_bracket) return error.UnclosedCurlyBracket;
                i.* += 1; // consume '}'

                if (max_val) |mv| if (mv < min) return error.InvalidQuantifier;

                const qn = try allocator.create(RegexNode);
                qn.* = RegexNode{ .quantified = .{ .node = atom, .quantifier = RegexQuantifier{ .min = min, .max = max_val, .greedy = true } } };
                atom = qn;
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

fn parse_tokens(allocator: std.mem.Allocator, tokens: RegexTokens) !Regex {
    var idx: usize = 0;
    var capture_group_idx: u8 = 1;
    const root = try parse_alternation(allocator, tokens, &idx, &capture_group_idx, false);
    return Regex{
        .allocator = allocator,
        .root = root,
        .num_captures = capture_group_idx - 1,
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
            const capture_len = capture_end - capture_start;

            std.log.debug("Capture group {d} matched from {d} to {d}, cursor: {f}", .{ cg.idx, capture_start, capture_end, cursor });
            std.log.debug("Successfully matched capture group {d}='{s}', current cursor: {f}", .{ cg.idx, cursor.input[capture_start..capture_end], cursor });

            cursor.captures[cg.idx - 1] = CaptureRef{ .start = capture_start, .len = capture_len };

            const slice = cursor.get_capture(cg.idx - 1);
            std.log.debug("Recorded capture group {d}: start={d} len={d} slice='{s}'", .{ cg.idx, capture_start, capture_len, slice });
            return true;
        },
        .backreference => |cg_idx| {
            std.log.debug("Attempting to match backreference to capture group {d}, {f}", .{ cg_idx, cursor });
            const cap_slice = cursor.get_capture(cg_idx - 1);
            std.log.debug("Backreference {d} captured slice before match: '{s}' (len={d}), cursor.current={d}", .{ cg_idx, cap_slice, cap_slice.len, cursor.current });
            // for backreferences, we construct a sequence of literal nodes on the fly using the string that was previously matched
            for (cap_slice) |c| {
                const inline_node = RegexNode{ .literal = c };
                if (!match_single_node(allocator, &inline_node, cursor)) return false;
            }
            std.log.debug("Backreference {d} matched successfully, new cursor.current={d}", .{ cg_idx, cursor.current });
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

var rng = std.Random.DefaultPrng.init(0);
fn match_nodes(allocator: std.mem.Allocator, nodes: []const *RegexNode, idx: usize, cursor: *RegexCursor) bool {
    const id = rng.random().int(u64);
    const RegexNodes = struct {
        const Self = @This();

        nodes: []const *RegexNode,

        pub fn format(self: Self, writer: *std.Io.Writer) !void {
            try writer.print("RegexNodes([", .{});
            for (self.nodes) |node| {
                try writer.print("{f}, ", .{node});
            }
            try writer.print("])", .{});
        }
    };
    std.log.debug("[{d}] Attempting to match nodes starting at idx={d}: {f} against {f}", .{ id, idx, RegexNodes{ .nodes = nodes }, cursor });
    const n = nodes.len;
    if (idx >= n) return true;

    const node = nodes[idx];
    switch (node.*) {
        .quantified => |q| {
            const start_pos = cursor.current;
            var initial_snapshot = Snapshot.init(allocator, cursor.current, cursor.captures) catch unreachable;
            defer initial_snapshot.deinit();

            var snapshots = std.ArrayList(Snapshot).empty;
            defer {
                for (snapshots.items) |*snap| {
                    snap.deinit();
                }
                snapshots.deinit(allocator);
            }

            var count: usize = 0;
            while (true) {
                if (q.quantifier.max) |max| if (count >= max) break;
                const before = cursor.current;
                std.log.debug("[{d}] Quantifier matching iteration, count={d}, cursor={f}", .{ id, count, cursor });
                if (!match_single_node(allocator, q.node, cursor)) break;
                if (cursor.current == before) break; // avoid infinite loop on zero-width

                // Take a snapshot of the current state
                const snapshot = Snapshot.init(allocator, cursor.current, cursor.captures) catch unreachable;
                std.log.debug("[{d}] Taking snapshot at pos={d}, count={d}", .{ id, cursor.current, count });

                // Log captures for debugging
                for (cursor.captures, 0..) |cap, i| {
                    const slice = cap.get_slice(cursor.input);
                    std.log.debug("[{d}] snapshot capture[{d}] start={d} len={d} slice='{s}'", .{ id, i, cap.start, cap.len, slice });
                }

                snapshots.append(allocator, snapshot) catch unreachable;
                count += 1;
            }

            if (q.quantifier.greedy) {
                var k: usize = snapshots.items.len;
                while (true) {
                    if (k < q.quantifier.min) break;

                    if (k == 0) {
                        cursor.current = start_pos;
                        std.mem.copyForwards(CaptureRef, cursor.captures, initial_snapshot.refs);
                        std.log.debug("[{d}] Restored initial state for k=0: {f}", .{ id, cursor });
                    } else {
                        const snap = snapshots.items[k - 1];
                        cursor.current = snap.current;
                        std.mem.copyForwards(CaptureRef, cursor.captures, snap.refs);
                        std.log.debug("[{d}] Restored snapshot k={d}, cursor: {f}", .{ id, k, cursor });
                    }

                    // Log current state for debugging
                    for (cursor.captures, 0..) |cap, i| {
                        const slice = cap.get_slice(cursor.input);
                        std.log.debug("[{d}] after restore (greedy) k={d} capture[{d}] start={d} len={d} slice='{s}'", .{ id, k, i, cap.start, cap.len, slice });
                    }

                    // Try to match the rest with current state
                    const next_char_slice: []const u8 = if (cursor.current < cursor.input.len)
                        cursor.input[cursor.current .. cursor.current + 1]
                    else
                        EMPTY_SLICE;
                    if (cursor.captures.len >= 4) {
                        const c4 = cursor.captures[3];
                        const c4_slice = c4.get_slice(cursor.input);
                        std.log.debug("[{d}] greedy-backtrack try k={d} capture4 start={d} len={d} slice='{s}' next='{s}'", .{ id, k, c4.start, c4.len, c4_slice, next_char_slice });
                    } else {
                        std.log.debug("[{d}] greedy-backtrack try k={d} num_captures={d} next='{s}'", .{ id, k, cursor.captures.len, next_char_slice });
                    }

                    // Preview next node and remaining input
                    if (idx + 1 < nodes.len) {
                        const next_node = nodes[idx + 1];
                        const preview_end = if (cursor.current + 8 < cursor.input.len) cursor.current + 8 else cursor.input.len;
                        const preview = if (cursor.current < cursor.input.len) cursor.input[cursor.current..preview_end] else EMPTY_SLICE;
                        std.log.debug("[{d}] Next node to attempt: {f}, input preview='{s}'", .{ id, next_node, preview });
                    } else {
                        std.log.debug("[{d}] No next node to attempt (idx+1 >= nodes.len)", .{id});
                    }

                    const try_result = match_nodes(allocator, nodes, idx + 1, cursor);
                    std.log.debug("[{d}] match_nodes returned {} after greedy quantifier k={d}, cursor: {f}", .{ id, try_result, k, cursor });
                    if (try_result) return true;

                    if (k == 0) break;
                    k -= 1;
                }
            } else {
                var k: usize = q.quantifier.min;
                while (k <= snapshots.items.len) {
                    if (k == 0) {
                        cursor.current = start_pos;
                        std.mem.copyForwards(CaptureRef, cursor.captures, initial_snapshot.refs);
                        std.log.debug("[{d}] Restored initial state for non-greedy k=0: {f}", .{ id, cursor });
                    } else {
                        const snap = snapshots.items[k - 1];
                        cursor.current = snap.current;
                        std.mem.copyForwards(CaptureRef, cursor.captures, snap.refs);
                        std.log.debug("[{d}] Restored snapshot for non-greedy k={d}: {f}", .{ id, k, cursor });
                    }

                    const try_result = match_nodes(allocator, nodes, idx + 1, cursor);
                    if (try_result) return true;
                    k += 1;
                }
            }

            // Restore initial state before failing
            cursor.current = start_pos;
            std.mem.copyForwards(CaptureRef, cursor.captures, initial_snapshot.refs);
            std.log.debug("[{d}] Final restore before failing quantifier: {f}", .{ id, cursor });
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
    num_captures: usize,

    pub fn for_pattern(allocator: std.mem.Allocator, pattern: []const u8) !Self {
        const tokens = try tokenize(allocator, pattern);
        defer allocator.free(tokens.tokens);
        const regex = try parse_tokens(allocator, tokens);
        return regex;
    }

    pub fn matches(self: *const Self, input: []const u8) bool {
        std.log.debug("Attempting to match input '{s}' against regex {f}", .{ input, self });
        var i: usize = 0;
        while (i <= input.len) {
            var cursor = RegexCursor.init(self.allocator, input, i, self.num_captures) catch unreachable;
            defer cursor.deinit();
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
    }
};

fn test_regex(pattern: []const u8, input: []const u8, expect_matches: bool) !void {
    std.testing.log_level = .debug;

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

// quantifiers (+, ?, *)

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

// quantifiers (specified)

test "regex 'ca{3}t' matches 'caaat'" {
    try test_regex("ca{3}t", "caaat", true);
}

test "regex 'ca{3}t' does not match 'caat'" {
    try test_regex("ca{3}t", "caat", false);
}

test "regex 'ca{3}t' does not match 'caaaat'" {
    try test_regex("ca{3}t", "caaaat", false);
}

test "regex 'd\\d{2}g' matches 'd42g'" {
    try test_regex("d\\d{2}g", "d42g", true);
}

test "regex 'd\\d{2}g' does not match 'd1g'" {
    try test_regex("d\\d{2}g", "d1g", false);
}

test "regex 'd\\d{2}g' does not match 'd123g'" {
    try test_regex("d\\d{2}g", "d123g", false);
}

test "regex 'c[xyz]{4}w' matches 'czyxzw'" {
    try test_regex("c[xyz]{4}w", "czyxzw", true);
}

test "regex 'c[xyz]{4}w' does not match 'cxyzw'" {
    try test_regex("c[xyz]{4}w", "cxyzw", false);
}

test "regex 'a{12}' matches 'aaaaaaaaaaaa'" {
    try test_regex("a{12}", "aaaaaaaaaaaa", true);
}

test "regex 'a{12}' does not match 'a'" {
    try test_regex("a{12}", "a", false);
}

// quantifiers (specified unbounded range)

test "regex 'ca{2,}t' matches 'caat'" {
    try test_regex("ca{2,}t", "caat", true);
}

test "regex 'ca{2,}t' matches 'caaaaat'" {
    try test_regex("ca{2,}t", "caaaaat", true);
}

test "regex 'ca{2,}t' does not match 'cat'" {
    try test_regex("ca{2,}t", "cat", false);
}

test "regex 'x\\d{3,}y' matches 'x9999y'" {
    try test_regex("x\\d{3,}y", "x9999y", true);
}

test "regex 'x\\d{3,}y' does not match 'x42y'" {
    try test_regex("x\\d{3,}y", "x42y", false);
}

test "regex 'b[aeiou]{2,}r' matches 'baeiour'" {
    try test_regex("b[aeiou]{2,}r", "baeiour", true);
}

test "regex 'b[aeiou]{2,}r' does not match 'bar'" {
    try test_regex("b[aeiou]{2,}r", "bar", false);
}

test "regex 'm{10,}' matches 'mmmmmmmmmm'" {
    try test_regex("m{10,}", "mmmmmmmmmm", true);
}

test "regex 'm{10,}' matches 'mmmmmmmmmmm'" {
    try test_regex("m{10,}", "mmmmmmmmmmm", true);
}

test "regex 'm{10,}' does not match 'm'" {
    try test_regex("m{10,}", "m", false);
}

// quantifiers (specified bounded range)

test "regex 'ca{2,4}t' matches 'caat'" {
    try test_regex("ca{2,4}t", "caat", true);
}

test "regex 'ca{2,4}t' matches 'caaat'" {
    try test_regex("ca{2,4}t", "caaat", true);
}

test "regex 'ca{2,4}t' matches 'caaaat'" {
    try test_regex("ca{2,4}t", "caaaat", true);
}

test "regex 'ca{2,4}t' does not match 'caaaaat'" {
    try test_regex("ca{2,4}t", "caaaaat", false);
}

test "regex 'n\\d{1,3}m' matches 'n123m'" {
    try test_regex("n\\d{1,3}m", "n123m", true);
}

test "regex 'n\\d{1,3}m' does not match 'n1234m'" {
    try test_regex("n\\d{1,3}m", "n1234m", false);
}

test "regex 'p[xyz]{2,3}q' matches 'pzzzq'" {
    try test_regex("p[xyz]{2,3}q", "pzzzq", true);
}

test "regex 'p[xyz]{2,3}q' does not match 'pxq'" {
    try test_regex("p[xyz]{2,3}q", "pxq", false);
}

test "regex 'p[xyz]{2,3}q' does not match 'pxyzyq'" {
    try test_regex("p[xyz]{2,3}q", "pxyzyq", false);
}

test "regex 'a{10,11}' matches 'aaaaaaaaaa'" {
    try test_regex("a{10,11}", "aaaaaaaaaa", true);
}

test "regex 'a{10,11}' matches 'aaaaaaaaaaa'" {
    try test_regex("a{10,11}", "aaaaaaaaaaa", true);
}

test "regex 'a{10,11}' does not match 'aaaaaaaaa'" {
    try test_regex("a{10,11}", "aaaaaaaaa", false);
}

test "regex '^a{10,11}$' does not match 'aaaaaaaaaaaa'" {
    try test_regex("^a{10,11}$", "aaaaaaaaaaaa", false);
}

test "regex 'a{10,11}' does not match 'a'" {
    try test_regex("a{10,11}", "a", false);
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

test "regex '^([act]+) is \\1, not [^xyz]+$' matches 'cat is cat, not dog'" {
    try test_regex("^([act]+) is \\1, not [^xyz]+$", "cat is cat, not dog", true);
}

test "regex '(([abc]+)-([def]+)) is \\1, not ([^xyz]+), \\2, or \\3' matches 'abc-def is abc-def, not efg, abc, or def'" {
    try test_regex("(([abc]+)-([def]+)) is \\1, not ([^xyz]+), \\2, or \\3", "abc-def is abc-def, not efg, abc, or def", true);
}
