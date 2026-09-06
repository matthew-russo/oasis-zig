const std = @import("std");

pub const CliDefinitionError = error{
    DefinitionMissingName,
    DefinitionMissingHelpMessage,
    DefinitionMissingType,
    DuplicateCommandDefined,
    DuplicateArgumentDefined,
    DuplicatePositionalDefined,
    RequiredPositionalAfterOptional,
    VariadicPositionalMustBeLast,
    PositionalsWithSubcommands,
};

pub const CliParsingError = error{
    UnknownCommand,
    UnknownArgument,
    MissingRequiredArgument,
    MissingRequiredPositionalArgument,
    MissingArgumentValue,
    MissingCommand,
    InvalidBooleanValue,
    InvalidIntegerValue,
};

pub const CliType = enum {
    const Self = @This();

    u64,
    i64,
    bool,
    string,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const CliValue = union(enum) {
    const Self = @This();

    u64: u64,
    i64: i64,
    bool: bool,
    string: []const u8,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        switch (self) {
            .u64 => |value| try writer.print("u64({d})", .{value}),
            .i64 => |value| try writer.print("i64({d})", .{value}),
            .bool => |value| try writer.print("bool({})", .{value}),
            .string => |value| try writer.print("string('{s}')", .{value}),
        }
    }
};

/// converts a raw command line token into a typed value. shared by flag values
/// and positional arguments so both accept exactly the same syntax.
pub fn parseValue(ty: CliType, value_str: []const u8) CliParsingError!CliValue {
    switch (ty) {
        CliType.u64 => {
            const value = std.fmt.parseInt(u64, value_str, 10) catch { // base 10
                return CliParsingError.InvalidIntegerValue;
            };
            return CliValue{ .u64 = value };
        },
        CliType.i64 => {
            const value = std.fmt.parseInt(i64, value_str, 10) catch { // base 10
                return CliParsingError.InvalidIntegerValue;
            };
            return CliValue{ .i64 = value };
        },
        CliType.bool => {
            if (std.mem.eql(u8, value_str, "true")) {
                return CliValue{ .bool = true };
            } else if (std.mem.eql(u8, value_str, "false")) {
                return CliValue{ .bool = false };
            } else {
                return CliParsingError.InvalidBooleanValue;
            }
        },
        CliType.string => {
            return CliValue{ .string = value_str };
        },
    }
}

pub const CliShortName = struct {
    const Self = @This();

    name: []const u8,

    pub fn eq(self: *Self, other: *Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("-{s}", .{self.name});
    }
};

pub const CliLongName = struct {
    const Self = @This();

    name: []const u8,

    pub fn eq(self: *Self, other: *Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("--{s}", .{self.name});
    }
};

pub const CliPositionalName = struct {
    const Self = @This();

    name: []const u8,

    pub fn eq(self: *Self, other: *Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("<{s}>", .{self.name});
    }
};

pub const CliArgName = union(enum) {
    const Self = @This();

    short: CliShortName,
    long: CliLongName,
    positional: CliPositionalName,

    pub fn rawName(self: Self) []const u8 {
        return switch (self) {
            .short => |name| name.name,
            .long => |name| name.name,
            .positional => |name| name.name,
        };
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        switch (self) {
            .short => |name| try writer.print("{f}", .{name}),
            .long => |name| try writer.print("{f}", .{name}),
            .positional => |name| try writer.print("{f}", .{name}),
        }
    }
};

pub const Arg = struct {
    const Self = @This();

    /// the name as it was written on the command line. for a positional, the
    /// name of the slot it filled.
    name: CliArgName,
    /// the canonical name of the definition this arg came from: the long name if
    /// the definition has one, otherwise the short name. positionals use their
    /// declared name. this is what lets `Command.get` find an arg regardless of
    /// whether the user typed the short or the long form.
    def_name: []const u8,
    value: CliValue,

    pub fn matchesName(self: *const Self, name: []const u8) bool {
        return std.mem.eql(u8, self.def_name, name) or std.mem.eql(u8, self.name.rawName(), name);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("Arg{{ .name={f}, .def_name='{s}', .value={f} }}", .{ self.name, self.def_name, self.value });
    }
};

pub const ArgDefinition = struct {
    const Self = @This();

    /// at least one of `long_name` and `short_name` is always set
    long_name: ?[]const u8,
    short_name: ?[]const u8,
    help: []const u8,
    ty: CliType,
    required: bool,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("ArgDefinition{{ .long_name=", .{});
        if (self.long_name) |long_name| {
            try writer.print("'{s}'", .{long_name});
        } else {
            try writer.print("null", .{});
        }
        try writer.print(", .short_name=", .{});
        if (self.short_name) |short_name| {
            try writer.print("'{s}'", .{short_name});
        } else {
            try writer.print("null", .{});
        }
        try writer.print(", .help='{s}', .ty={f}, .required={} }}", .{ self.help, self.ty, self.required });
    }

    /// the canonical name for this arg: the long name when it has one, otherwise
    /// the short name. used for lookups and for error/help messages.
    pub fn defName(self: *const Self) []const u8 {
        if (self.long_name) |long_name| {
            return long_name;
        }
        return self.short_name.?;
    }

    /// bools are flags: their presence on the command line sets them to true, so
    /// they never consume the following token as a value.
    pub fn takesValue(self: *const Self) bool {
        return self.ty != CliType.bool;
    }

    pub fn matchesArgName(self: *const Self, argName: CliArgName) bool {
        switch (argName) {
            CliArgName.long => |long| {
                if (self.long_name) |long_name| {
                    return std.mem.eql(u8, long.name, long_name);
                } else {
                    return false;
                }
            },
            CliArgName.short => |short| {
                if (self.short_name) |short_name| {
                    return std.mem.eql(u8, short.name, short_name);
                } else {
                    return false;
                }
            },
            CliArgName.positional => return false,
        }
    }

    pub fn overlapsWith(self: *const Self, other: *const Self) bool {
        if (self.long_name) |our_long_name| {
            if (other.long_name) |other_long_name| {
                if (std.mem.eql(u8, our_long_name, other_long_name)) {
                    return true;
                }
            }
        }

        if (self.short_name) |our_short_name| {
            if (other.short_name) |other_short_name| {
                if (std.mem.eql(u8, our_short_name, other_short_name)) {
                    return true;
                }
            }
        }

        return false;
    }

    fn argSummaryLengthWithoutHelp(self: *const Self) usize {
        var current_length: usize = 0;
        current_length += 2; // '  '
        if (self.short_name) |short_name| {
            current_length += 1; // '-'
            current_length += short_name.len;
            if (self.long_name != null) {
                current_length += 2; // ', '
            }
        }
        if (self.long_name) |long_name| {
            current_length += 2; // '--'
            current_length += long_name.len;
        }
        if (self.takesValue()) {
            current_length += 2; // ' <'
            current_length += @tagName(self.ty).len;
            current_length += 1; // '>'
        }
        current_length += 1; // ' '
        return current_length;
    }

    fn printArgSummary(self: *const Self, min_spacing_before_help: usize) void {
        std.debug.print("  ", .{});
        if (self.short_name) |short_name| {
            std.debug.print("-{s}", .{short_name});
            if (self.long_name != null) {
                std.debug.print(", ", .{});
            }
        }
        if (self.long_name) |long_name| {
            std.debug.print("--{s}", .{long_name});
        }
        if (self.takesValue()) {
            std.debug.print(" <{s}>", .{@tagName(self.ty)});
        }
        std.debug.print(" ", .{});
        if (self.argSummaryLengthWithoutHelp() < min_spacing_before_help) {
            for (0..min_spacing_before_help - self.argSummaryLengthWithoutHelp()) |_| {
                std.debug.print(" ", .{});
            }
        }
        std.debug.print("{s}\n", .{self.help});
    }
};

pub const ArgDefinitionBuilder = struct {
    const Self = @This();

    long_name: ?[]const u8,
    short_name: ?[]const u8,
    help: ?[]const u8,
    ty: ?CliType,
    required: bool,

    pub fn init() Self {
        return Self{
            .long_name = null,
            .short_name = null,
            .help = null,
            .ty = null,
            .required = false,
        };
    }

    pub fn withLongName(s: Self, long_name: []const u8) Self {
        var self = s;
        self.long_name = long_name;
        return self;
    }

    pub fn withShortName(s: Self, short_name: []const u8) Self {
        var self = s;
        self.short_name = short_name;
        return self;
    }

    pub fn withHelp(s: Self, help: []const u8) Self {
        var self = s;
        self.help = help;
        return self;
    }

    pub fn withType(s: Self, ty: CliType) Self {
        var self = s;
        self.ty = ty;
        return self;
    }

    pub fn isRequired(s: Self, required: bool) Self {
        var self = s;
        self.required = required;
        return self;
    }

    pub fn build(self: Self) CliDefinitionError!ArgDefinition {
        // an arg needs at least one of the two names, but never needs both
        if (self.long_name == null and self.short_name == null) {
            return CliDefinitionError.DefinitionMissingName;
        }

        if (self.help) |_| {} else {
            return CliDefinitionError.DefinitionMissingHelpMessage;
        }

        if (self.ty) |_| {} else {
            return CliDefinitionError.DefinitionMissingType;
        }

        return ArgDefinition{ .long_name = self.long_name, .short_name = self.short_name, .help = self.help.?, .ty = self.ty.?, .required = self.required };
    }
};

pub const PositionalDefinition = struct {
    const Self = @This();

    name: []const u8,
    help: []const u8,
    ty: CliType,
    required: bool,
    /// a variadic positional consumes every remaining non-flag token, producing
    /// one Arg per token. it must be the last positional of its command.
    variadic: bool,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print(
            "PositionalDefinition{{ .name='{s}', .help='{s}', .ty={f}, .required={}, .variadic={} }}",
            .{ self.name, self.help, self.ty, self.required, self.variadic },
        );
    }

    pub fn overlapsWith(self: *const Self, other: *const Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }

    fn printUsage(self: *const Self) void {
        const open: []const u8 = if (self.required) "<" else "[";
        const close: []const u8 = if (self.required) ">" else "]";
        const ellipsis: []const u8 = if (self.variadic) "..." else "";
        std.debug.print(" {s}{s}{s}{s}", .{ open, self.name, ellipsis, close });
    }

    fn positionalSummaryLengthWithoutHelp(self: *const Self) usize {
        var current_length: usize = 0;
        current_length += 2; // '  '
        current_length += 1; // '<'
        current_length += self.name.len;
        if (self.variadic) {
            current_length += 3; // '...'
        }
        current_length += 1; // '>'
        current_length += 2; // ' <'
        current_length += @tagName(self.ty).len;
        current_length += 2; // '> '
        return current_length;
    }

    fn printPositionalSummary(self: *const Self, min_spacing_before_help: usize) void {
        std.debug.print("  <{s}{s}> <{s}> ", .{
            self.name,
            if (self.variadic) "..." else "",
            @tagName(self.ty),
        });
        if (self.positionalSummaryLengthWithoutHelp() < min_spacing_before_help) {
            for (0..min_spacing_before_help - self.positionalSummaryLengthWithoutHelp()) |_| {
                std.debug.print(" ", .{});
            }
        }
        std.debug.print("{s}\n", .{self.help});
    }
};

pub const PositionalDefinitionBuilder = struct {
    const Self = @This();

    name: ?[]const u8,
    help: ?[]const u8,
    ty: ?CliType,
    required: bool,
    variadic: bool,

    pub fn init() Self {
        return Self{
            .name = null,
            .help = null,
            .ty = null,
            .required = false,
            .variadic = false,
        };
    }

    pub fn withName(s: Self, name: []const u8) Self {
        var self = s;
        self.name = name;
        return self;
    }

    pub fn withHelp(s: Self, help: []const u8) Self {
        var self = s;
        self.help = help;
        return self;
    }

    pub fn withType(s: Self, ty: CliType) Self {
        var self = s;
        self.ty = ty;
        return self;
    }

    pub fn isRequired(s: Self, required: bool) Self {
        var self = s;
        self.required = required;
        return self;
    }

    pub fn isVariadic(s: Self, variadic: bool) Self {
        var self = s;
        self.variadic = variadic;
        return self;
    }

    pub fn build(self: Self) CliDefinitionError!PositionalDefinition {
        if (self.name) |_| {} else {
            return CliDefinitionError.DefinitionMissingName;
        }

        if (self.help) |_| {} else {
            return CliDefinitionError.DefinitionMissingHelpMessage;
        }

        if (self.ty) |_| {} else {
            return CliDefinitionError.DefinitionMissingType;
        }

        return PositionalDefinition{
            .name = self.name.?,
            .help = self.help.?,
            .ty = self.ty.?,
            .required = self.required,
            .variadic = self.variadic,
        };
    }
};

/// positionals are matched by order, so the declaration order has to be
/// unambiguous: no duplicate names, no required slot hiding behind an optional
/// one, and at most one variadic slot, at the end.
fn validatePositionals(positionals: []const PositionalDefinition) CliDefinitionError!void {
    for (0..positionals.len) |i| {
        for (i + 1..positionals.len) |j| {
            if (positionals[i].overlapsWith(&positionals[j])) {
                return CliDefinitionError.DuplicatePositionalDefined;
            }
        }
    }

    var seen_optional = false;
    for (positionals, 0..) |positional, i| {
        if (positional.required and seen_optional) {
            return CliDefinitionError.RequiredPositionalAfterOptional;
        }
        if (!positional.required) {
            seen_optional = true;
        }
        if (positional.variadic and i != positionals.len - 1) {
            return CliDefinitionError.VariadicPositionalMustBeLast;
        }
    }
}

fn validateArgs(args: []const ArgDefinition) CliDefinitionError!void {
    for (0..args.len) |i| {
        for (i + 1..args.len) |j| {
            if (args[i].overlapsWith(&args[j])) {
                return CliDefinitionError.DuplicateArgumentDefined;
            }
        }
    }
}

pub const Command = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    args: std.ArrayList(Arg),
    subcommand: ?*Command,

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("Command{{ .name='{s}', .args=[", .{self.name});
        for (self.args.items, 0..) |arg, index| {
            if (index != 0) try writer.print(", ", .{});
            try writer.print("{f}", .{arg});
        }
        try writer.print("], .subcommand=", .{});
        if (self.subcommand) |subcommand| {
            try writer.print("{f}", .{subcommand.*});
        } else {
            try writer.print("null", .{});
        }
        try writer.print(" }}", .{});
    }

    pub fn deinit(s: *Self) void {
        var self = s;

        self.args.deinit(self.allocator);

        if (self.subcommand) |subcommand| {
            subcommand.*.deinit();
            self.allocator.destroy(subcommand);
        }
    }

    /// looks up an arg by either its canonical (long, or short if there is no
    /// long) name or the name the user actually typed. returns the first match.
    pub fn get(self: *const Self, name: []const u8) ?CliValue {
        for (self.args.items) |arg| {
            if (arg.matchesName(name)) {
                return arg.value;
            }
        }
        return null;
    }

    /// every value supplied under `name`. mostly useful for variadic positionals.
    /// the caller owns the returned list.
    pub fn getAll(
        self: *const Self,
        allocator: std.mem.Allocator,
        name: []const u8,
    ) std.mem.Allocator.Error!std.ArrayList(CliValue) {
        var values = std.ArrayList(CliValue).empty;
        errdefer values.deinit(allocator);
        for (self.args.items) |arg| {
            if (arg.matchesName(name)) {
                try values.append(allocator, arg.value);
            }
        }
        return values;
    }

    /// bool args always have a value after parsing: absent flags are recorded as
    /// false, so this never has to distinguish "absent" from "false".
    pub fn getBool(self: *const Self, name: []const u8) bool {
        if (self.get(name)) |value| {
            return switch (value) {
                .bool => |b| b,
                else => false,
            };
        }
        return false;
    }

    pub fn getString(self: *const Self, name: []const u8) ?[]const u8 {
        if (self.get(name)) |value| {
            return switch (value) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getU64(self: *const Self, name: []const u8) ?u64 {
        if (self.get(name)) |value| {
            return switch (value) {
                .u64 => |v| v,
                else => null,
            };
        }
        return null;
    }

    pub fn getI64(self: *const Self, name: []const u8) ?i64 {
        if (self.get(name)) |value| {
            return switch (value) {
                .i64 => |v| v,
                else => null,
            };
        }
        return null;
    }
};

pub const CommandDefinition = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    help: []const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_positionals: std.ArrayList(PositionalDefinition),
    possible_subcommands: std.ArrayList(CommandDefinition),

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("CommandDefinition{{ .name='{s}', .help='{s}', .possible_args=[", .{ self.name, self.help });
        for (self.possible_args.items, 0..) |arg, index| {
            if (index != 0) try writer.print(", ", .{});
            try writer.print("{f}", .{arg});
        }
        try writer.print("], .possible_positionals=[", .{});
        for (self.possible_positionals.items, 0..) |positional, index| {
            if (index != 0) try writer.print(", ", .{});
            try writer.print("{f}", .{positional});
        }
        try writer.print("], .possible_subcommands=[", .{});
        for (self.possible_subcommands.items, 0..) |subcommand, index| {
            if (index != 0) try writer.print(", ", .{});
            try writer.print("{f}", .{subcommand});
        }
        try writer.print("] }}", .{});
    }

    pub fn deinit(s: *Self) void {
        var self = s;
        self.possible_args.deinit(self.allocator);
        self.possible_positionals.deinit(self.allocator);
        for (self.possible_subcommands.items) |*possible_subcommand| {
            possible_subcommand.deinit();
        }
        self.possible_subcommands.deinit(self.allocator);
    }

    pub fn overlapsWith(self: *const Self, other: *const Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }

    pub fn commandSummaryLengthWithoutHelp(self: *const Self) usize {
        // '  <name  '
        return 2 + self.name.len + 2;
    }

    pub fn printCommandSummary(self: *const Self, min_spacing_before_help: usize) void {
        std.debug.print("  {s}  ", .{self.name});
        if (self.commandSummaryLengthWithoutHelp() < min_spacing_before_help) {
            for (0..min_spacing_before_help - self.commandSummaryLengthWithoutHelp()) |_| {
                std.debug.print(" ", .{});
            }
        }
        std.debug.print("{s}\n", .{self.help});
    }
};

pub const CommandDefinitionBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: ?[]const u8,
    help: ?[]const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_positionals: std.ArrayList(PositionalDefinition),
    possible_subcommands: std.ArrayList(CommandDefinition),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .name = null,
            .help = null,
            .possible_args = std.ArrayList(ArgDefinition).empty,
            .possible_positionals = std.ArrayList(PositionalDefinition).empty,
            .possible_subcommands = std.ArrayList(CommandDefinition).empty,
        };
    }

    pub fn withName(s: Self, name: []const u8) Self {
        var self = s;
        self.name = name;
        return self;
    }

    pub fn withHelp(s: Self, help: []const u8) Self {
        var self = s;
        self.help = help;
        return self;
    }

    pub fn withArg(s: Self, arg_def: ArgDefinition) Self {
        var self = s;
        // TODO handle errors
        self.possible_args.append(self.allocator, arg_def) catch unreachable;
        return self;
    }

    pub fn withPositional(s: Self, positional_def: PositionalDefinition) Self {
        var self = s;
        // TODO handle errors
        self.possible_positionals.append(self.allocator, positional_def) catch unreachable;
        return self;
    }

    pub fn withSubcommand(s: Self, subcommand_def: CommandDefinition) Self {
        var self = s;
        // TODO handle errors
        self.possible_subcommands.append(self.allocator, subcommand_def) catch unreachable;
        return self;
    }

    fn deinitPartial(self: *Self) void {
        self.possible_args.deinit(self.allocator);
        self.possible_positionals.deinit(self.allocator);
        for (self.possible_subcommands.items) |*possible_subcommand| {
            possible_subcommand.deinit();
        }
        self.possible_subcommands.deinit(self.allocator);
    }

    pub fn build(s: Self) CliDefinitionError!CommandDefinition {
        var self = s;

        if (self.name) |_| {} else {
            self.deinitPartial();
            return CliDefinitionError.DefinitionMissingName;
        }

        if (self.help) |_| {} else {
            self.deinitPartial();
            return CliDefinitionError.DefinitionMissingHelpMessage;
        }

        // a bare token can't be both a positional and a subcommand name, so a
        // command has to pick one or the other
        if (self.possible_positionals.items.len > 0 and self.possible_subcommands.items.len > 0) {
            self.deinitPartial();
            return CliDefinitionError.PositionalsWithSubcommands;
        }

        validateArgs(self.possible_args.items) catch |err| {
            self.deinitPartial();
            return err;
        };

        validatePositionals(self.possible_positionals.items) catch |err| {
            self.deinitPartial();
            return err;
        };

        return CommandDefinition{
            .allocator = self.allocator,
            .name = self.name.?,
            .help = self.help.?,
            .possible_args = self.possible_args,
            .possible_positionals = self.possible_positionals,
            .possible_subcommands = self.possible_subcommands,
        };
    }
};

pub const ArgParser = struct {
    const Self = @This();

    offset: *usize,
    cli_args: [][]const u8,
    valid_args: []ArgDefinition,

    pub fn init(
        offset: *usize,
        cli_args: [][]const u8,
        valid_args: []ArgDefinition,
    ) Self {
        return Self{
            .offset = offset,
            .cli_args = cli_args,
            .valid_args = valid_args,
        };
    }

    /// returns null when the token at the current offset is not a flag at all,
    /// leaving the offset untouched so the caller can decide what to do with it.
    pub fn parse(self: *Self) CliParsingError!?Arg {
        if (self.offset.* >= self.cli_args.len) {
            return null;
        }

        var name = self.cli_args[self.offset.*];

        // args always start with "-",
        //   - short args are just a single "-", e.g. '-f'
        //   - large args are two "-", e.g. '--file'
        //
        // a bare "-" and a bare "--" are not args: the first is the conventional
        // stdin placeholder and the second is the end-of-flags separator, both of
        // which are the caller's business.
        if (name.len < 2 or name[0] != '-' or std.mem.eql(u8, name, "--")) {
            return null;
        }

        // check the second char to determine whether we're parsing a long or short arg
        // if the second char is another hyphen, we're parsing a long arg
        var arg_name: CliArgName = undefined;
        if (name[1] == '-') {
            name = name[2..];
            arg_name = CliArgName{ .long = CliLongName{ .name = name } };
        } else {
            // otherwise we're parsing a short arg
            name = name[1..];
            arg_name = CliArgName{ .short = CliShortName{ .name = name } };
        }

        // the definition has to be resolved before we know whether the next token
        // belongs to this arg: flags don't take a value
        var maybe_arg_def: ?ArgDefinition = null;
        for (self.valid_args) |valid_arg| {
            if (valid_arg.matchesArgName(arg_name)) {
                maybe_arg_def = valid_arg;
                break;
            }
        }

        const arg_def = maybe_arg_def orelse return CliParsingError.UnknownArgument;

        self.offset.* += 1;

        if (!arg_def.takesValue()) {
            // presence of the flag is the value
            return Arg{
                .name = arg_name,
                .def_name = arg_def.defName(),
                .value = CliValue{ .bool = true },
            };
        }

        if (self.offset.* >= self.cli_args.len) {
            return CliParsingError.MissingArgumentValue;
        }

        const value_str = self.cli_args[self.offset.*];
        self.offset.* += 1;

        return Arg{
            .name = arg_name,
            .def_name = arg_def.defName(),
            .value = try parseValue(arg_def.ty, value_str),
        };
    }
};

pub const CommandParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    offset: *usize,
    cli_args: [][]const u8,
    valid_commands: []CommandDefinition,

    pub fn init(allocator: std.mem.Allocator, offset: *usize, cli_args: [][]const u8, valid_commands: []CommandDefinition) Self {
        return Self{
            .allocator = allocator,
            .offset = offset,
            .cli_args = cli_args,
            .valid_commands = valid_commands,
        };
    }

    pub fn parse(self: *Self, allocator: std.mem.Allocator) CliParsingError!?Command {
        if (self.offset.* >= self.cli_args.len) {
            return null;
        }

        if (self.valid_commands.len == 0) {
            return null;
        }

        const curr_name = self.cli_args[self.offset.*];
        self.offset.* += 1;

        var maybe_target_command_def: ?CommandDefinition = null;
        for (self.valid_commands) |candidate_command| {
            if (std.mem.eql(u8, candidate_command.name, curr_name)) {
                maybe_target_command_def = candidate_command;
                break;
            }
        }

        const target_command_def = maybe_target_command_def orelse return CliParsingError.UnknownCommand;

        const args = try parseArgs(
            self.allocator,
            self.offset,
            self.cli_args,
            target_command_def.possible_args.items,
            target_command_def.possible_positionals.items,
        );

        var command = Command{
            .allocator = allocator,

            .name = curr_name,
            .args = args,
            .subcommand = null,
        };
        errdefer command.deinit();

        // chomp subcommand if available
        var subcommand_parser = CommandParser.init(
            allocator,
            self.offset,
            self.cli_args,
            target_command_def.possible_subcommands.items,
        );

        if (try subcommand_parser.parse(allocator)) |subcommand| {
            const subcommand_ptr = allocator.create(Command) catch unreachable;
            subcommand_ptr.* = subcommand;
            command.subcommand = subcommand_ptr;
        }

        return command;
    }
};

/// consumes flags and positionals from the current offset until it runs out of
/// tokens or hits a bare token that no positional slot wants -- that token is
/// left for the caller, which will try to read it as a subcommand.
fn parseArgs(
    allocator: std.mem.Allocator,
    offset: *usize,
    cli_args: [][]const u8,
    valid_args: []ArgDefinition,
    valid_positionals: []PositionalDefinition,
) CliParsingError!std.ArrayList(Arg) {
    var args = std.ArrayList(Arg).empty;
    errdefer args.deinit(allocator);

    // everything after a bare "--" is a positional, even if it looks like a flag
    var end_of_flags = false;
    // the positional slot we're currently filling, and how many tokens have gone
    // into it. the count only ever exceeds one for a variadic slot, which never
    // advances the index.
    var positional_index: usize = 0;
    var current_slot_count: usize = 0;

    while (offset.* < cli_args.len) {
        const token = cli_args[offset.*];

        if (!end_of_flags) {
            if (std.mem.eql(u8, token, "--")) {
                offset.* += 1;
                end_of_flags = true;
                continue;
            }

            var arg_parser = ArgParser.init(offset, cli_args, valid_args);
            if (try arg_parser.parse()) |arg| {
                args.append(allocator, arg) catch unreachable;
                continue;
            }
        }

        // a bare token. if there's no positional slot left to put it in, it
        // belongs to whatever comes next (a subcommand, or nothing at all)
        if (positional_index >= valid_positionals.len) {
            break;
        }

        const positional_def = valid_positionals[positional_index];
        const value = try parseValue(positional_def.ty, token);
        offset.* += 1;
        args.append(allocator, Arg{
            .name = CliArgName{ .positional = CliPositionalName{ .name = positional_def.name } },
            .def_name = positional_def.name,
            .value = value,
        }) catch unreachable;

        if (positional_def.variadic) {
            current_slot_count += 1;
        } else {
            positional_index += 1;
            current_slot_count = 0;
        }
    }

    for (valid_args) |possible_arg| {
        if (!possible_arg.required) {
            continue;
        }

        var found = false;
        for (args.items) |arg| {
            if (possible_arg.matchesArgName(arg.name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            return CliParsingError.MissingRequiredArgument;
        }
    }

    for (valid_positionals, 0..) |possible_positional, i| {
        if (!possible_positional.required) {
            continue;
        }

        const filled = i < positional_index or (i == positional_index and current_slot_count > 0);
        if (!filled) {
            return CliParsingError.MissingRequiredPositionalArgument;
        }
    }

    // an unsupplied bool flag is false rather than absent, so callers never have
    // to handle a missing bool
    for (valid_args) |possible_arg| {
        if (possible_arg.ty != CliType.bool) {
            continue;
        }

        var found = false;
        for (args.items) |arg| {
            if (possible_arg.matchesArgName(arg.name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            const name: CliArgName = if (possible_arg.long_name) |long_name|
                CliArgName{ .long = CliLongName{ .name = long_name } }
            else
                CliArgName{ .short = CliShortName{ .name = possible_arg.short_name.? } };

            args.append(allocator, Arg{
                .name = name,
                .def_name = possible_arg.defName(),
                .value = CliValue{ .bool = false },
            }) catch unreachable;
        }
    }

    return args;
}

pub const CliApp = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    offset: usize,

    name: []const u8,
    help: []const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_positionals: std.ArrayList(PositionalDefinition),
    possible_commands: std.ArrayList(CommandDefinition),

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        help: []const u8,
        possible_args: std.ArrayList(ArgDefinition),
        possible_positionals: std.ArrayList(PositionalDefinition),
        possible_commands: std.ArrayList(CommandDefinition),
    ) Self {
        return Self{
            .allocator = allocator,
            .name = name,
            .help = help,
            .possible_args = possible_args,
            .possible_positionals = possible_positionals,
            .offset = 0,
            .possible_commands = possible_commands,
        };
    }

    pub fn deinit(self: *Self) void {
        self.possible_args.deinit(self.allocator);
        self.possible_positionals.deinit(self.allocator);
        for (self.possible_commands.items) |*possible_command| {
            possible_command.deinit();
        }
        self.possible_commands.deinit(self.allocator);
    }

    pub fn printHelp(self: *const Self) void {
        std.debug.print("{s}\n\n", .{self.help});
        std.debug.print("USAGE: {s}", .{self.name});
        var option_padding_size: usize = 0;
        var positional_padding_size: usize = 0;
        var command_padding_size: usize = 0;
        for (self.possible_args.items) |possible_arg| {
            if (possible_arg.required) {
                if (possible_arg.long_name) |long_name| {
                    std.debug.print(" --{s}", .{long_name});
                } else {
                    std.debug.print(" -{s}", .{possible_arg.short_name.?});
                }
                if (possible_arg.takesValue()) {
                    std.debug.print(" <{s}>", .{@tagName(possible_arg.ty)});
                }
            }
            const current_length: usize = possible_arg.argSummaryLengthWithoutHelp();
            if (current_length > option_padding_size) {
                option_padding_size = current_length;
            }
        }
        if (self.possible_args.items.len > 0) {
            std.debug.print(" [OPTIONS]", .{});
        }
        for (self.possible_positionals.items) |possible_positional| {
            possible_positional.printUsage();
            const current_length: usize = possible_positional.positionalSummaryLengthWithoutHelp();
            if (current_length > positional_padding_size) {
                positional_padding_size = current_length;
            }
        }
        if (self.possible_commands.items.len > 0) {
            std.debug.print(" [COMMAND]", .{});
            std.debug.print("\n\nCommands:\n", .{});
            for (self.possible_commands.items) |possible_command| {
                const current_length: usize = possible_command.commandSummaryLengthWithoutHelp();
                if (current_length > command_padding_size) {
                    command_padding_size = current_length;
                }
            }
            for (self.possible_commands.items) |possible_command| {
                possible_command.printCommandSummary(command_padding_size);
            }
        }
        if (self.possible_positionals.items.len > 0) {
            std.debug.print("\n\nArguments:\n", .{});
            for (self.possible_positionals.items) |possible_positional| {
                possible_positional.printPositionalSummary(positional_padding_size);
            }
        }
        if (self.possible_args.items.len > 0) {
            std.debug.print("\nOptions:\n", .{});
            for (self.possible_args.items) |possible_arg| {
                possible_arg.printArgSummary(option_padding_size);
            }
        }
    }

    pub fn reset(self: *Self) void {
        self.offset = 0;
    }

    /// argc is the number of command arguments, unmodified from what main gives.
    /// it is always at least 1 because by convention, program name is always provided
    /// as the first argument
    ///
    /// argv are the space-separated arguments, the first entry is always the program
    /// name. its never used but expected so that callers can pass argv from main
    /// without any modifications
    ///
    /// the returned Command is always the app itself; a command supplied on the
    /// command line hangs off it as `subcommand`.
    pub fn parse(self: *Self, allocator: std.mem.Allocator, argc: usize, argv: [][]const u8) CliParsingError!Command {
        // first arg is always the program name
        std.debug.assert(argc >= 1);
        const cli_args = argv[1..];
        const args = try parseArgs(
            allocator,
            &self.offset,
            cli_args,
            self.possible_args.items,
            self.possible_positionals.items,
        );

        var command = Command{
            .allocator = allocator,
            .name = self.name,
            .args = args,
            .subcommand = null,
        };
        errdefer command.deinit();

        if (self.offset < cli_args.len) {
            if (self.possible_commands.items.len == 0) {
                return CliParsingError.UnknownCommand;
            }

            var parser = CommandParser.init(
                allocator,
                &self.offset,
                cli_args,
                self.possible_commands.items,
            );
            if (try parser.parse(allocator)) |parsed_subcommand| {
                const subcommand_ptr = allocator.create(Command) catch unreachable;
                subcommand_ptr.* = parsed_subcommand;
                command.subcommand = subcommand_ptr;
            }
        }

        return command;
    }
};

pub const CliAppBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    help: []const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_positionals: std.ArrayList(PositionalDefinition),
    possible_commands: std.ArrayList(CommandDefinition),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, help: []const u8) Self {
        return Self{
            .allocator = allocator,

            .name = name,
            .help = help,
            .possible_args = std.ArrayList(ArgDefinition).empty,
            .possible_positionals = std.ArrayList(PositionalDefinition).empty,
            .possible_commands = std.ArrayList(CommandDefinition).empty,
        };
    }

    pub fn deinit(s: *Self) void {
        var self = s;
        self.possible_args.deinit(self.allocator);
        self.possible_positionals.deinit(self.allocator);
        for (self.possible_commands.items) |*possible_command| {
            possible_command.deinit();
        }
        self.possible_commands.deinit(self.allocator);
    }

    pub fn withArg(s: Self, arg_def: ArgDefinition) Self {
        var self = s;
        self.possible_args.append(self.allocator, arg_def) catch unreachable;
        return self;
    }

    pub fn withPositional(s: Self, positional_def: PositionalDefinition) Self {
        var self = s;
        self.possible_positionals.append(self.allocator, positional_def) catch unreachable;
        return self;
    }

    pub fn withCommand(s: Self, command_def: CommandDefinition) Self {
        var self = s;
        self.possible_commands.append(self.allocator, command_def) catch unreachable;
        return self;
    }

    pub fn build(self: Self) CliDefinitionError!CliApp {
        validateArgs(self.possible_args.items) catch |err| {
            var s = self;
            s.deinit();
            return err;
        };

        for (0..self.possible_commands.items.len) |i| {
            for (i + 1..self.possible_commands.items.len) |j| {
                if (self.possible_commands.items[i].overlapsWith(&self.possible_commands.items[j])) {
                    var s = self;
                    s.deinit();
                    return CliDefinitionError.DuplicateCommandDefined;
                }
            }
        }

        // a bare token can't be both a root positional and a command name
        if (self.possible_positionals.items.len > 0 and self.possible_commands.items.len > 0) {
            var s = self;
            s.deinit();
            return CliDefinitionError.PositionalsWithSubcommands;
        }

        validatePositionals(self.possible_positionals.items) catch |err| {
            var s = self;
            s.deinit();
            return err;
        };

        return CliApp.init(
            self.allocator,
            self.name,
            self.help,
            self.possible_args,
            self.possible_positionals,
            self.possible_commands,
        );
    }
};

test "arg_definition_with_no_name_returns_error" {
    const err = ArgDefinitionBuilder.init()
        .withHelp("test help msg")
        .withType(CliType.bool)
        .build();

    try std.testing.expectEqual(err, CliDefinitionError.DefinitionMissingName);
}

test "arg_definition_with_no_help_returns_error" {
    const err = ArgDefinitionBuilder.init()
        .withLongName("name")
        .withType(CliType.bool)
        .build();

    try std.testing.expectEqual(err, CliDefinitionError.DefinitionMissingHelpMessage);
}

test "arg_definition_with_no_type_returns_error" {
    const err = ArgDefinitionBuilder.init()
        .withLongName("name")
        .withHelp("test help msg")
        .build();

    try std.testing.expectEqual(err, CliDefinitionError.DefinitionMissingType);
}

test "successful_arg_definition" {
    const maybe_arg_def = ArgDefinitionBuilder.init()
        .withLongName("name")
        .withShortName("n")
        .withHelp("test help msg")
        .withType(CliType.bool)
        .isRequired(true)
        .build();

    const arg_def = try maybe_arg_def;

    try std.testing.expectEqualStrings(arg_def.long_name.?, "name");
    try std.testing.expectEqualStrings(arg_def.short_name.?, "n");
    try std.testing.expectEqualStrings(arg_def.help, "test help msg");
    try std.testing.expectEqual(arg_def.ty, CliType.bool);
    try std.testing.expectEqual(arg_def.required, true);
}

test "command_definition_with_no_name_return_serror" {
    const err = CommandDefinitionBuilder.init(std.testing.allocator)
        .withHelp("test help msg")
        .build();

    try std.testing.expectEqual(err, CliDefinitionError.DefinitionMissingName);
}

test "command_definition_with_no_help_returns_error" {
    const err = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("name")
        .build();

    try std.testing.expectEqual(err, CliDefinitionError.DefinitionMissingHelpMessage);
}

test "successful_basic_command_definition" {
    const maybe_command_def = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("name")
        .withHelp("test help msg")
        .build();

    var command_def = try maybe_command_def;
    defer command_def.deinit();

    try std.testing.expectEqualStrings(command_def.name, "name");
    try std.testing.expectEqualStrings(command_def.help, "test help msg");

    try std.testing.expectEqual(command_def.possible_args.items.len, 0);
    try std.testing.expectEqual(command_def.possible_subcommands.items.len, 0);
}

test "successful_command_with_args_definition" {
    const maybe_command_def = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("name")
        .withHelp("test help msg")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("commandArg1")
            .withHelp("test help msg for commandArg1")
            .withType(CliType.u64)
            .build())
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("commandArg2")
            .withHelp("test help msg for commandArg2")
            .withType(CliType.i64)
            .build())
        .build();

    var command_def = try maybe_command_def;
    defer command_def.deinit();

    try std.testing.expectEqualStrings(command_def.name, "name");
    try std.testing.expectEqualStrings(command_def.help, "test help msg");

    try std.testing.expectEqual(command_def.possible_args.items.len, 2);

    const arg1 = command_def.possible_args.items[0];
    try std.testing.expectEqualStrings(arg1.long_name.?, "commandArg1");
    try std.testing.expectEqualStrings(arg1.help, "test help msg for commandArg1");
    try std.testing.expectEqual(arg1.ty, CliType.u64);

    const arg2 = command_def.possible_args.items[1];
    try std.testing.expectEqualStrings(arg2.long_name.?, "commandArg2");
    try std.testing.expectEqualStrings(arg2.help, "test help msg for commandArg2");
    try std.testing.expectEqual(arg2.ty, CliType.i64);

    try std.testing.expectEqual(command_def.possible_subcommands.items.len, 0);
}

test "successful_command_with_subcommands_definition" {
    const maybe_command_def = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("name")
        .withHelp("test help msg")
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand1")
            .withHelp("test help msg for subcommand1")
            .build())
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand2")
            .withHelp("test help msg for subcommand2")
            .build())
        .build();

    var command_def = try maybe_command_def;
    defer command_def.deinit();

    try std.testing.expectEqualStrings(command_def.name, "name");
    try std.testing.expectEqualStrings(command_def.help, "test help msg");

    try std.testing.expectEqual(command_def.possible_args.items.len, 0);

    try std.testing.expectEqual(command_def.possible_subcommands.items.len, 2);

    const subcommand1 = command_def.possible_subcommands.items[0];
    try std.testing.expectEqualStrings(subcommand1.name, "subcommand1");
    try std.testing.expectEqualStrings(subcommand1.help, "test help msg for subcommand1");

    const subcommand2 = command_def.possible_subcommands.items[1];
    try std.testing.expectEqualStrings(subcommand2.name, "subcommand2");
    try std.testing.expectEqualStrings(subcommand2.help, "test help msg for subcommand2");
}

test "successful_complex_command" {
    const maybe_command_def = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("name")
        .withHelp("test help msg")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("commandArg1")
            .withHelp("test help msg for commandArg1")
            .withType(CliType.u64)
            .build())
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand1")
            .withHelp("test help msg for subcommand1")
            .withArg(try ArgDefinitionBuilder.init()
                .withLongName("subcommand1Arg1")
                .withHelp("test help msg for subcommand1Arg1")
                .withType(CliType.i64)
                .build())
            .build())
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand2")
            .withHelp("test help msg for subcommand2")
            .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
                .withName("subcommand2subcommand1")
                .withHelp("test help msg for subcommand2subcommand1")
                .build())
            .build())
        .build();

    var command_def = try maybe_command_def;
    defer command_def.deinit();

    try std.testing.expectEqualStrings(command_def.name, "name");
    try std.testing.expectEqualStrings(command_def.help, "test help msg");

    try std.testing.expectEqual(command_def.possible_args.items.len, 1);
    const arg1 = command_def.possible_args.items[0];
    try std.testing.expectEqualStrings(arg1.long_name.?, "commandArg1");
    try std.testing.expectEqualStrings(arg1.help, "test help msg for commandArg1");
    try std.testing.expectEqual(arg1.ty, CliType.u64);

    try std.testing.expectEqual(command_def.possible_subcommands.items.len, 2);

    const subcommand1 = command_def.possible_subcommands.items[0];
    try std.testing.expectEqualStrings(subcommand1.name, "subcommand1");
    try std.testing.expectEqualStrings(subcommand1.help, "test help msg for subcommand1");
    try std.testing.expectEqual(subcommand1.possible_args.items.len, 1);
    const subcommand1_arg1 = subcommand1.possible_args.items[0];
    try std.testing.expectEqualStrings(subcommand1_arg1.long_name.?, "subcommand1Arg1");
    try std.testing.expectEqualStrings(subcommand1_arg1.help, "test help msg for subcommand1Arg1");
    try std.testing.expectEqual(subcommand1_arg1.ty, CliType.i64);

    const subcommand2 = command_def.possible_subcommands.items[1];
    try std.testing.expectEqualStrings(subcommand2.name, "subcommand2");
    try std.testing.expectEqualStrings(subcommand2.help, "test help msg for subcommand2");
    try std.testing.expectEqual(subcommand2.possible_subcommands.items.len, 1);
    const subcommand2_subcommand1 = subcommand2.possible_subcommands.items[0];
    try std.testing.expectEqualStrings(subcommand2_subcommand1.name, "subcommand2subcommand1");
    try std.testing.expectEqualStrings(subcommand2_subcommand1.help, "test help msg for subcommand2subcommand1");
}

// ============================= ArgParser Tests ==============================

test "arg_parser_returns_ok_none_with_empty_args" {
    var offset: usize = 0;
    var parser = ArgParser.init(&offset, &.{}, &.{});
    const arg = try parser.parse();
    try std.testing.expectEqual(arg, null);
}

test "arg_parser_returns_unknown_arg_error_with_empty_arg_defs" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "--file", "test.txt" };
    var parser = ArgParser.init(&offset, &cli_args, &.{});
    const err = parser.parse();
    try std.testing.expectEqual(err, CliParsingError.UnknownArgument);
}

test "arg_parser_returns_ok_none_if_word_doesnt_start_with_hyphen" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"test.txt"};
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "file",
        .short_name = "f",
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = try parser.parse();
    try std.testing.expectEqual(arg, null);
}

test "arg_parser_parses_long_arg" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "--file", "test.txt" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "file",
        .short_name = null,
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.long.name, "file");
    try std.testing.expectEqualStrings(arg.value.string, "test.txt");
}

test "arg_parser_parses_short_arg" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-f", "test.txt" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "file",
        .short_name = "f",
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.short.name, "f");
    try std.testing.expectEqualStrings(arg.value.string, "test.txt");
}

test "arg_parser_parses_u64" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-n", "42" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "num",
        .short_name = "n",
        .help = "test_arg",
        .ty = CliType.u64,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.short.name, "n");
    try std.testing.expectEqual(arg.value.u64, 42);
}

test "arg_parser_parses_i64" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-n", "-42" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "num",
        .short_name = "n",
        .help = "test_arg",
        .ty = CliType.i64,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.short.name, "n");
    try std.testing.expectEqual(arg.value.i64, -42);
}

test "arg_parser_parses_bool_flag_without_a_value" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"-b"};
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "bool",
        .short_name = "b",
        .help = "test_arg",
        .ty = CliType.bool,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.short.name, "b");
    try std.testing.expectEqualStrings(arg.def_name, "bool");
    try std.testing.expectEqual(arg.value.bool, true);
    try std.testing.expectEqual(offset, 1);
}

test "arg_parser_does_not_consume_the_token_after_a_bool_flag" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-b", "not-a-bool" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "bool",
        .short_name = "b",
        .help = "test_arg",
        .ty = CliType.bool,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqual(arg.value.bool, true);
    // the following token is untouched, ready to be read as a positional or command
    try std.testing.expectEqual(offset, 1);
}

test "arg_parser_fails_when_a_valued_arg_has_no_value" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"--file"};
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "file",
        .short_name = null,
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const err = parser.parse();

    try std.testing.expectEqual(err, CliParsingError.MissingArgumentValue);
}

test "arg_parser_fails_to_parse_invalid_integer" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-n", "not-a-number" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "num",
        .short_name = "n",
        .help = "test_arg",
        .ty = CliType.u64,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const err = parser.parse();

    try std.testing.expectEqual(err, CliParsingError.InvalidIntegerValue);
}

test "arg_parser_parses_a_short_only_arg" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-f", "test.txt" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = null,
        .short_name = "f",
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.short.name, "f");
    try std.testing.expectEqualStrings(arg.def_name, "f");
    try std.testing.expectEqualStrings(arg.value.string, "test.txt");
}

test "arg_parser_rejects_the_long_form_of_a_short_only_arg" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "--f", "test.txt" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = null,
        .short_name = "f",
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const err = parser.parse();

    try std.testing.expectEqual(err, CliParsingError.UnknownArgument);
}

test "arg_parser_returns_ok_none_for_end_of_flags_separator" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"--"};
    var parser = ArgParser.init(&offset, &cli_args, &.{});
    const arg = try parser.parse();
    try std.testing.expectEqual(arg, null);
    try std.testing.expectEqual(offset, 0);
}

test "arg_parser_returns_ok_none_for_a_lone_hyphen" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"-"};
    var parser = ArgParser.init(&offset, &cli_args, &.{});
    const arg = try parser.parse();
    try std.testing.expectEqual(arg, null);
    try std.testing.expectEqual(offset, 0);
}

test "arg_parser_returns_ok_none_for_a_single_character_token" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"x"};
    var parser = ArgParser.init(&offset, &cli_args, &.{});
    const arg = try parser.parse();
    try std.testing.expectEqual(arg, null);
    try std.testing.expectEqual(offset, 0);
}

test "arg_parser_parses_string" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "--file", "test.txt" };
    var arg_defs: [1]ArgDefinition = [_]ArgDefinition{ArgDefinition{
        .long_name = "file",
        .short_name = null,
        .help = "test_arg",
        .ty = CliType.string,
        .required = true,
    }};
    var parser = ArgParser.init(&offset, &cli_args, &arg_defs);
    const arg = (try parser.parse()).?;

    try std.testing.expectEqualStrings(arg.name.long.name, "file");
    try std.testing.expectEqualStrings(arg.value.string, "test.txt");
}

// ============================= CommandParser Tests ==============================

test "command_parser_returns_ok_none_with_empty_args" {
    var offset: usize = 0;
    var parser = CommandParser.init(std.testing.allocator, &offset, &.{}, &.{});
    const command = try parser.parse(std.testing.allocator);
    try std.testing.expectEqual(command, null);
}

test "command_parser_returns_ok_none_with_empty_command_def" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"command"};
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &.{});
    const command = try parser.parse(std.testing.allocator);
    try std.testing.expectEqual(command, null);
}

test "command_parser_parses_basic_command_with_no_args_or_subcommands" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"command"};
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{CommandDefinition{
        .allocator = std.testing.allocator,
        .name = "command",
        .help = "test_command",
        .possible_args = std.ArrayList(ArgDefinition).empty,
        .possible_positionals = std.ArrayList(PositionalDefinition).empty,
        .possible_subcommands = std.ArrayList(CommandDefinition).empty,
    }};
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 0);
    try std.testing.expectEqual(command.subcommand, null);
}

test "command_parser_parses_command_with_single_arg" {
    var offset: usize = 0;
    var cli_args: [3][]const u8 = [_][]const u8{ "command", "--file", "test.txt" };
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("file")
            .withHelp("test arg")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 1);

    const arg = command.args.items[0];
    try std.testing.expectEqualStrings(arg.name.long.name, "file");
    try std.testing.expectEqualStrings(arg.value.string, "test.txt");

    try std.testing.expectEqual(command.subcommand, null);
}

test "command_parser_parses_command_with_multiple_args" {
    var offset: usize = 0;
    var cli_args: [4][]const u8 = [_][]const u8{ "command", "--file", "test.txt", "-b" };
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("file")
            .withHelp("test arg 1")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("bool")
            .withShortName("b")
            .withHelp("test arg 2")
            .withType(CliType.bool)
            .isRequired(true)
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 2);

    const arg1 = command.args.items[0];
    try std.testing.expectEqualStrings(arg1.name.long.name, "file");
    try std.testing.expectEqualStrings(arg1.value.string, "test.txt");

    const arg2 = command.args.items[1];
    try std.testing.expectEqualStrings(arg2.name.short.name, "b");
    try std.testing.expectEqual(arg2.value.bool, true);

    try std.testing.expectEqual(command.subcommand, null);
}

test "command_parser_parses_without_non_required_arg" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"command"};
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("file")
            .withHelp("test arg 1")
            .withType(CliType.string)
            .isRequired(false)
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 0);
    try std.testing.expectEqual(command.subcommand, null);
}

test "command_parser_fails_to_parse_without_required_arg" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"command"};
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("file")
            .withHelp("test arg 1")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    const err = parser.parse(std.testing.allocator);

    try std.testing.expectEqual(err, CliParsingError.MissingRequiredArgument);
}

test "command_parser_parses_command_with_subcommand" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "command", "subcommand" };
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand")
            .withHelp("test subcommand")
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 0);

    const subcommand = command.subcommand.?;

    try std.testing.expectEqualStrings(subcommand.name, "subcommand");
    try std.testing.expectEqual(subcommand.args.items.len, 0);
    try std.testing.expectEqual(subcommand.subcommand, null);
}

test "command_parser_parses_command_with_multiple_subcommands" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "command", "subcommand2" };
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand1")
            .withHelp("test subcommand1")
            .build())
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand2")
            .withHelp("test subcommand2")
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 0);

    const subcommand = command.subcommand.?;

    try std.testing.expectEqualStrings(subcommand.name, "subcommand2");
    try std.testing.expectEqual(subcommand.args.items.len, 0);
    try std.testing.expectEqual(subcommand.subcommand, null);
}

test "command_parser_parses_without_requiring_subcommand" {
    var offset: usize = 0;
    var cli_args: [1][]const u8 = [_][]const u8{"command"};
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand1")
            .withHelp("test subcommand1")
            .build())
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand2")
            .withHelp("test subcommand2")
            .build())
        .build()};
    defer command_defs[0].deinit();
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 0);
    try std.testing.expectEqual(command.subcommand, null);
}

test "command_parser_ignores_unknown_subcommands" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "command", "subcommand" };
    var command_defs: [1]CommandDefinition = [_]CommandDefinition{try CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test_command")
        .build()};
    var parser = CommandParser.init(std.testing.allocator, &offset, &cli_args, &command_defs);
    var command = (try parser.parse(std.testing.allocator)).?;
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "command");
    try std.testing.expectEqual(command.args.items.len, 0);
    try std.testing.expectEqual(command.subcommand, null);
}

// ============================= CliApp Tests ==============================
test "empty_cli_app" {
    _ = try CliAppBuilder.init(std.testing.allocator, "test_app", "a sample application to unit test the module")
        .build();
}

test "cli_app_disallows_duplicate_commands" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "a sample application to unit test the module")
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("command")
            .withHelp("test help msg for command")
            .build())
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("command")
            .withHelp("test help msg for command")
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.DuplicateCommandDefined);
}

test "cli_app_disallows_duplicate_args" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "a sample application to unit test the module")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("arg")
            .withHelp("test help msg for arg")
            .withType(CliType.u64)
            .build())
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("arg")
            .withHelp("test help msg for arg")
            .withType(CliType.u64)
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.DuplicateArgumentDefined);
}

test "cli_app_parses_root_args_without_command" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "a server").withArg(
        try ArgDefinitionBuilder.init()
            .withLongName("arg")
            .withHelp("server argument")
            .withType(CliType.string)
            .isRequired(true)
            .build(),
    ).build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [3][]const u8 = [_][]const u8{ "my_binary", "--arg", "value" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqualStrings(command.name, "my_binary");
    try std.testing.expectEqual(command.args.items.len, 1);
    try std.testing.expectEqualStrings(command.args.items[0].name.long.name, "arg");
    try std.testing.expectEqualStrings(command.args.items[0].value.string, "value");
    try std.testing.expectEqual(command.subcommand, null);
}

// ============================= End-to-end Tests ==============================
test "end_to_end_cli_parser_test" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "test_app", "a sample application to unit test the module")
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("command")
            .withHelp("test help msg")
            .withArg(try ArgDefinitionBuilder.init()
                .withLongName("commandArg1")
                .withHelp("test help msg for commandArg1")
                .withType(CliType.u64)
                .build())
            .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
                .withName("subcommand1")
                .withHelp("test help msg for subcommand1")
                .withArg(try ArgDefinitionBuilder.init()
                    .withLongName("subcommand1Arg1")
                    .withHelp("test help msg for subcommand1Arg1")
                    .withType(CliType.i64)
                    .build())
                .build())
            .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
                .withName("subcommand2")
                .withHelp("test help msg for subcommand2")
                .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
                    .withName("subcommand2subcommand1")
                    .withHelp("test help msg for subcommand2subcommand1")
                    .build())
                .build())
            .build())
        .build();
    // zig fmt: on

    defer cli_parser.deinit();

    cli_parser.printHelp();

    const argc1 = 7;
    var argv1: [argc1][]const u8 = [_][]const u8{ "my_test", "command", "--commandArg1", "42", "subcommand1", "--subcommand1Arg1", "-42" };

    var root1 = try cli_parser.parse(std.testing.allocator, argc1, &argv1);
    defer root1.deinit();

    // the root command is always the app itself, whether or not a command was given
    try std.testing.expectEqualStrings(root1.name, "test_app");
    try std.testing.expectEqual(root1.args.items.len, 0);

    const command1 = root1.subcommand.?;
    try std.testing.expectEqualStrings(command1.name, "command");
    try std.testing.expectEqual(command1.args.items.len, 1);

    const command1arg1 = command1.args.items[0];
    try std.testing.expectEqualStrings(command1arg1.name.long.name, "commandArg1");
    try std.testing.expectEqual(command1arg1.value.u64, 42);

    const command1subcommand1 = command1.subcommand.?;
    try std.testing.expectEqualStrings(command1subcommand1.name, "subcommand1");
    try std.testing.expectEqual(command1subcommand1.args.items.len, 1);
    try std.testing.expectEqual(command1subcommand1.subcommand, null);

    const command1subcommand1arg1 = command1subcommand1.args.items[0];
    try std.testing.expectEqualStrings(command1subcommand1arg1.name.long.name, "subcommand1Arg1");
    try std.testing.expectEqual(command1subcommand1arg1.value.i64, -42);

    const argc2 = 4;
    var argv2: [argc2][]const u8 = [_][]const u8{ "my_test", "command", "subcommand2", "subcommand2subcommand1" };

    cli_parser.reset();
    var root2 = try cli_parser.parse(std.testing.allocator, argc2, &argv2);
    defer root2.deinit();

    try std.testing.expectEqualStrings(root2.name, "test_app");

    const command2 = root2.subcommand.?;
    try std.testing.expectEqualStrings(command2.name, "command");
    try std.testing.expectEqual(command2.args.items.len, 0);

    const command2subcommand2 = command2.subcommand.?;
    try std.testing.expectEqualStrings(command2subcommand2.name, "subcommand2");
    try std.testing.expectEqual(command2.args.items.len, 0);

    const command2subcommand2subcommand1 = command2subcommand2.subcommand.?;
    try std.testing.expectEqualStrings(command2subcommand2subcommand1.name, "subcommand2subcommand1");
    try std.testing.expectEqual(command2subcommand2subcommand1.args.items.len, 0);
    try std.testing.expectEqual(command2subcommand2subcommand1.subcommand, null);
}

// ============================= Bool Flag Tests ==============================

test "bool_flag_is_true_when_present_without_a_value" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("verbose")
            .withShortName("v")
            .withHelp("chatty output")
            .withType(CliType.bool)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [2][]const u8 = [_][]const u8{ "my_binary", "--verbose" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.args.items.len, 1);
    // args are looked up by their canonical name, whichever form was written
    try std.testing.expectEqual(command.getBool("verbose"), true);
}

test "bool_flag_is_true_when_present_in_its_short_form" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("verbose")
            .withShortName("v")
            .withHelp("chatty output")
            .withType(CliType.bool)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [2][]const u8 = [_][]const u8{ "my_binary", "-v" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.getBool("verbose"), true);
}

test "bool_flag_is_false_when_absent" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("verbose")
            .withShortName("v")
            .withHelp("chatty output")
            .withType(CliType.bool)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [1][]const u8 = [_][]const u8{"my_binary"};
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    // absent bools are materialized as false rather than left out
    try std.testing.expectEqual(command.args.items.len, 1);
    try std.testing.expectEqual(command.args.items[0].value.bool, false);
    try std.testing.expectEqual(command.getBool("verbose"), false);
}

test "bool_flag_does_not_swallow_the_following_command" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("verbose")
            .withHelp("chatty output")
            .withType(CliType.bool)
            .build())
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("serve")
            .withHelp("serve it")
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [3][]const u8 = [_][]const u8{ "my_binary", "--verbose", "serve" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.getBool("verbose"), true);
    try std.testing.expectEqualStrings(command.subcommand.?.name, "serve");
}

test "bool_flag_defaults_to_false_on_a_subcommand_too" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("serve")
            .withHelp("serve it")
            .withArg(try ArgDefinitionBuilder.init()
                .withLongName("daemonize")
                .withHelp("run in the background")
                .withType(CliType.bool)
                .build())
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [2][]const u8 = [_][]const u8{ "my_binary", "serve" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.subcommand.?.getBool("daemonize"), false);
}

// ============================= Single-Name Arg Tests ==============================

test "arg_definition_with_only_a_short_name_is_valid" {
    const arg_def = try ArgDefinitionBuilder.init()
        .withShortName("f")
        .withHelp("test help msg")
        .withType(CliType.string)
        .build();

    try std.testing.expectEqual(arg_def.long_name, null);
    try std.testing.expectEqualStrings(arg_def.short_name.?, "f");
    try std.testing.expectEqualStrings(arg_def.defName(), "f");
}

test "arg_definition_with_only_a_long_name_is_valid" {
    const arg_def = try ArgDefinitionBuilder.init()
        .withLongName("file")
        .withHelp("test help msg")
        .withType(CliType.string)
        .build();

    try std.testing.expectEqualStrings(arg_def.long_name.?, "file");
    try std.testing.expectEqual(arg_def.short_name, null);
    try std.testing.expectEqualStrings(arg_def.defName(), "file");
}

test "args_with_only_short_names_do_not_overlap_on_their_missing_long_names" {
    const first = try ArgDefinitionBuilder.init()
        .withShortName("f")
        .withHelp("test help msg")
        .withType(CliType.string)
        .build();
    const second = try ArgDefinitionBuilder.init()
        .withShortName("g")
        .withHelp("test help msg")
        .withType(CliType.string)
        .build();

    try std.testing.expectEqual(first.overlapsWith(&second), false);
}

test "cli_app_disallows_duplicate_short_only_args" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withShortName("f")
            .withHelp("test help msg")
            .withType(CliType.string)
            .build())
        .withArg(try ArgDefinitionBuilder.init()
            .withShortName("f")
            .withHelp("test help msg")
            .withType(CliType.string)
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.DuplicateArgumentDefined);
}

test "cli_app_parses_a_short_only_arg" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withShortName("n")
            .withHelp("how many")
            .withType(CliType.u64)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [3][]const u8 = [_][]const u8{ "my_binary", "-n", "7" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.getU64("n").?, 7);
}

// ============================= Positional Tests ==============================

test "positional_definition_requires_a_name" {
    const err = PositionalDefinitionBuilder.init()
        .withHelp("test help msg")
        .withType(CliType.string)
        .build();

    try std.testing.expectEqual(err, CliDefinitionError.DefinitionMissingName);
}

test "cli_app_parses_a_single_positional" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("path")
            .withHelp("the file to read")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [2][]const u8 = [_][]const u8{ "my_binary", "in.txt" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.args.items.len, 1);
    try std.testing.expectEqualStrings(command.args.items[0].name.positional.name, "path");
    try std.testing.expectEqualStrings(command.getString("path").?, "in.txt");
}

test "cli_app_parses_positionals_in_order_and_by_type" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("count")
            .withHelp("how many")
            .withType(CliType.u64)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [3][]const u8 = [_][]const u8{ "my_binary", "in.txt", "3" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqualStrings(command.getString("src").?, "in.txt");
    try std.testing.expectEqual(command.getU64("count").?, 3);
}

test "cli_app_allows_an_omitted_optional_positional" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("dst")
            .withHelp("destination")
            .withType(CliType.string)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [2][]const u8 = [_][]const u8{ "my_binary", "in.txt" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqualStrings(command.getString("src").?, "in.txt");
    try std.testing.expectEqual(command.get("dst"), null);
}

test "cli_app_fails_without_a_required_positional" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [1][]const u8 = [_][]const u8{"my_binary"};
    const err = cli_parser.parse(std.testing.allocator, argv.len, &argv);

    try std.testing.expectEqual(err, CliParsingError.MissingRequiredPositionalArgument);
}

test "cli_app_interleaves_flags_and_positionals" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("verbose")
            .withHelp("chatty output")
            .withType(CliType.bool)
            .build())
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("out")
            .withHelp("output path")
            .withType(CliType.string)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [5][]const u8 = [_][]const u8{ "my_binary", "--verbose", "in.txt", "--out", "out.txt" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.getBool("verbose"), true);
    try std.testing.expectEqualStrings(command.getString("src").?, "in.txt");
    try std.testing.expectEqualStrings(command.getString("out").?, "out.txt");
}

test "cli_app_parses_a_variadic_positional" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("paths")
            .withHelp("the files to read")
            .withType(CliType.string)
            .isRequired(true)
            .isVariadic(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [4][]const u8 = [_][]const u8{ "my_binary", "a.txt", "b.txt", "c.txt" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    var paths = try command.getAll(std.testing.allocator, "paths");
    defer paths.deinit(std.testing.allocator);

    try std.testing.expectEqual(paths.items.len, 3);
    try std.testing.expectEqualStrings(paths.items[0].string, "a.txt");
    try std.testing.expectEqualStrings(paths.items[1].string, "b.txt");
    try std.testing.expectEqualStrings(paths.items[2].string, "c.txt");
}

test "cli_app_fails_on_an_empty_required_variadic_positional" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("paths")
            .withHelp("the files to read")
            .withType(CliType.string)
            .isRequired(true)
            .isVariadic(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [1][]const u8 = [_][]const u8{"my_binary"};
    const err = cli_parser.parse(std.testing.allocator, argv.len, &argv);

    try std.testing.expectEqual(err, CliParsingError.MissingRequiredPositionalArgument);
}

test "cli_app_treats_everything_after_a_double_hyphen_as_positional" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("verbose")
            .withHelp("chatty output")
            .withType(CliType.bool)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("args")
            .withHelp("passthrough args")
            .withType(CliType.string)
            .isVariadic(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [4][]const u8 = [_][]const u8{ "my_binary", "--verbose", "--", "--verbose" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    try std.testing.expectEqual(command.getBool("verbose"), true);

    var passthrough = try command.getAll(std.testing.allocator, "args");
    defer passthrough.deinit(std.testing.allocator);

    try std.testing.expectEqual(passthrough.items.len, 1);
    try std.testing.expectEqualStrings(passthrough.items[0].string, "--verbose");
}

test "cli_app_rejects_extra_positionals" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [3][]const u8 = [_][]const u8{ "my_binary", "in.txt", "extra" };
    const err = cli_parser.parse(std.testing.allocator, argv.len, &argv);

    // there is no positional slot and no command to take "extra"
    try std.testing.expectEqual(err, CliParsingError.UnknownCommand);
}

test "cli_app_reports_a_bad_positional_value" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("count")
            .withHelp("how many")
            .withType(CliType.u64)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [2][]const u8 = [_][]const u8{ "my_binary", "not-a-number" };
    const err = cli_parser.parse(std.testing.allocator, argv.len, &argv);

    try std.testing.expectEqual(err, CliParsingError.InvalidIntegerValue);
}

test "subcommand_parses_positionals" {
    // zig fmt: off
    var cli_parser = try CliAppBuilder.init(std.testing.allocator, "my_binary", "an app")
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("copy")
            .withHelp("copy a file")
            .withArg(try ArgDefinitionBuilder.init()
                .withLongName("force")
                .withShortName("f")
                .withHelp("overwrite the destination")
                .withType(CliType.bool)
                .build())
            .withPositional(try PositionalDefinitionBuilder.init()
                .withName("src")
                .withHelp("source")
                .withType(CliType.string)
                .isRequired(true)
                .build())
            .withPositional(try PositionalDefinitionBuilder.init()
                .withName("dst")
                .withHelp("destination")
                .withType(CliType.string)
                .isRequired(true)
                .build())
            .build())
        .build();
    // zig fmt: on
    defer cli_parser.deinit();

    var argv: [5][]const u8 = [_][]const u8{ "my_binary", "copy", "-f", "in.txt", "out.txt" };
    var command = try cli_parser.parse(std.testing.allocator, argv.len, &argv);
    defer command.deinit();

    const copy = command.subcommand.?;
    try std.testing.expectEqualStrings(copy.name, "copy");
    try std.testing.expectEqual(copy.getBool("force"), true);
    try std.testing.expectEqualStrings(copy.getString("src").?, "in.txt");
    try std.testing.expectEqualStrings(copy.getString("dst").?, "out.txt");
}

// ============================= Positional Definition Validation Tests ==============================

test "positionals_cannot_coexist_with_subcommands" {
    // zig fmt: off
    const err = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test help msg")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .build())
        .withSubcommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("subcommand")
            .withHelp("test help msg")
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.PositionalsWithSubcommands);
}

test "root_positionals_cannot_coexist_with_commands" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .build())
        .withCommand(try CommandDefinitionBuilder.init(std.testing.allocator)
            .withName("command")
            .withHelp("test help msg")
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.PositionalsWithSubcommands);
}

test "a_required_positional_cannot_follow_an_optional_one" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("dst")
            .withHelp("destination")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.RequiredPositionalAfterOptional);
}

test "a_variadic_positional_must_come_last" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("paths")
            .withHelp("sources")
            .withType(CliType.string)
            .isRequired(true)
            .isVariadic(true)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("dst")
            .withHelp("destination")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.VariadicPositionalMustBeLast);
}

test "duplicate_positionals_are_rejected" {
    // zig fmt: off
    const err = CliAppBuilder.init(std.testing.allocator, "test_app", "an app")
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .withPositional(try PositionalDefinitionBuilder.init()
            .withName("src")
            .withHelp("source again")
            .withType(CliType.string)
            .isRequired(true)
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.DuplicatePositionalDefined);
}

test "command_definition_rejects_duplicate_args" {
    // zig fmt: off
    const err = CommandDefinitionBuilder.init(std.testing.allocator)
        .withName("command")
        .withHelp("test help msg")
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("arg")
            .withHelp("test help msg")
            .withType(CliType.u64)
            .build())
        .withArg(try ArgDefinitionBuilder.init()
            .withLongName("arg")
            .withHelp("test help msg")
            .withType(CliType.u64)
            .build())
        .build();
    // zig fmt: on
    try std.testing.expectEqual(err, CliDefinitionError.DuplicateArgumentDefined);
}
