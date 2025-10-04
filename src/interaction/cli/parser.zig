const std = @import("std");

pub const CliDefinitionError = error{
    DefinitionMissingName,
    DefinitionMissingHelpMessage,
    DefinitionMissingType,
    DuplicateCommandDefined,
    DuplicateArgumentDefined,
};

pub const CliParsingError = error{
    UnknownCommand,
    UnknownArgument,
    MissingRequiredArgument,
    MissingCommand,
    InvalidBooleanValue,
};

pub const CliType = enum {
    u64,
    i64,
    bool,
    string,
};

pub const CliValue = union(enum) {
    u64: u64,
    i64: i64,
    bool: bool,
    string: []const u8,
};

pub const CliShortName = struct {
    const Self = @This();

    name: []const u8,

    pub fn eq(self: *Self, other: *Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }
};

pub const CliLongName = struct {
    const Self = @This();

    name: []const u8,

    pub fn eq(self: *Self, other: *Self) bool {
        return std.mem.eql(u8, self.name, other.name);
    }
};

pub const CliArgName = union(enum) {
    short: CliShortName,
    long: CliLongName,
};

pub const Arg = struct {
    const Self = @This();

    name: CliArgName,
    value: CliValue,
};

pub const ArgDefinition = struct {
    const Self = @This();

    long_name: []const u8,
    short_name: ?[]const u8,
    help: []const u8,
    ty: CliType,
    required: bool,

    pub fn matchesArgName(self: *const Self, argName: CliArgName) bool {
        switch (argName) {
            CliArgName.long => |long| {
                return std.mem.eql(u8, long.name, self.long_name);
            },
            CliArgName.short => |short| {
                if (self.short_name) |short_name| {
                    return std.mem.eql(u8, short.name, short_name);
                } else {
                    return false;
                }
            },
        }
    }

    pub fn overlapsWith(self: *const Self, other: *const Self) bool {
        if (std.mem.eql(u8, self.long_name, other.long_name)) {
            return true;
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
            current_length += 2; // ', '
        }
        current_length += 2; // '--'
        current_length += self.long_name.len;
        current_length += 1; // ' '
        current_length += self.long_name.len;
        current_length += 1; // ' '
        return current_length;
    }

    fn printArgSummary(self: *const Self, min_spacing_before_help: usize) void {
        std.debug.print("  ", .{});
        if (self.short_name) |short_name| {
            std.debug.print("-{s}, ", .{short_name});
        }
        std.debug.print("--{s} <{s}> ", .{ self.long_name, self.long_name });
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
        if (self.long_name) |_| {} else {
            return CliDefinitionError.DefinitionMissingName;
        }

        if (self.help) |_| {} else {
            return CliDefinitionError.DefinitionMissingHelpMessage;
        }

        if (self.ty) |_| {} else {
            return CliDefinitionError.DefinitionMissingType;
        }

        return ArgDefinition{ .long_name = self.long_name.?, .short_name = self.short_name, .help = self.help.?, .ty = self.ty.?, .required = self.required };
    }
};

pub const Command = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    args: std.ArrayList(Arg),
    subcommand: ?*Command,

    pub fn deinit(s: *Self) void {
        var self = s;

        self.args.deinit(self.allocator);

        if (self.subcommand) |subcommand| {
            subcommand.*.deinit();
            self.allocator.destroy(subcommand);
        }
    }
};

pub const CommandDefinition = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    help: []const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_subcommands: std.ArrayList(CommandDefinition),

    pub fn deinit(s: *Self) void {
        var self = s;
        self.possible_args.deinit(self.allocator);
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
    possible_subcommands: std.ArrayList(CommandDefinition),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .name = null,
            .help = null,
            .possible_args = std.ArrayList(ArgDefinition).empty,
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

    pub fn withSubcommand(s: Self, subcommand_def: CommandDefinition) Self {
        var self = s;
        // TODO handle errors
        self.possible_subcommands.append(self.allocator, subcommand_def) catch unreachable;
        return self;
    }

    pub fn build(s: Self) CliDefinitionError!CommandDefinition {
        var self = s;

        if (self.name) |_| {} else {
            self.possible_args.deinit(self.allocator);
            self.possible_subcommands.deinit(self.allocator);
            return CliDefinitionError.DefinitionMissingName;
        }

        if (self.help) |_| {} else {
            self.possible_args.deinit(self.allocator);
            self.possible_subcommands.deinit(self.allocator);
            return CliDefinitionError.DefinitionMissingHelpMessage;
        }

        return CommandDefinition{
            .allocator = self.allocator,
            .name = self.name.?,
            .help = self.help.?,
            .possible_args = self.possible_args,
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

    pub fn parse(self: *Self) CliParsingError!?Arg {
        if (self.offset.* >= self.cli_args.len) {
            return null;
        }

        var name = self.cli_args[self.offset.*];
        std.debug.assert(name.len >= 2);

        // args always start with "-",
        //   - short args are just a single "-", e.g. '-f'
        //   - large args are two "-", e.g. '--file'
        if (name[0] != '-') {
            // if the next word does not start with a '-', we're not parsing an arg
            return null;
        }

        self.offset.* += 1;

        // check the second char to determine whether we're parsing a long or short arg
        // if the second char is another hyphen, we're parsing a long arg
        var arg_name: ?CliArgName = null;
        if (name[1] == '-') {
            name = name[2..];
            arg_name = CliArgName{ .long = CliLongName{ .name = name } };
        } else {
            // otherwise we're parsing a short arg
            name = name[1..];
            arg_name = CliArgName{ .short = CliShortName{ .name = name } };
        }

        std.debug.assert(self.offset.* < self.cli_args.len);
        const value_str = self.cli_args[self.offset.*];
        self.offset.* += 1;
        var maybe_arg_value: ?CliValue = null;

        var maybe_arg_def: ?ArgDefinition = null;
        for (self.valid_args) |valid_arg| {
            if (valid_arg.matchesArgName(arg_name.?)) {
                maybe_arg_def = valid_arg;
            }
        }

        if (maybe_arg_def) |arg_def| {
            switch (arg_def.ty) {
                CliType.u64 => {
                    // TODO handle errors
                    maybe_arg_value = CliValue{
                        .u64 = std.fmt.parseInt(u64, value_str, 10) catch unreachable, // base 10
                    };
                },
                CliType.i64 => {
                    // TODO handle errors
                    maybe_arg_value = CliValue{
                        .i64 = std.fmt.parseInt(i64, value_str, 10) catch unreachable, // base 10
                    };
                },
                CliType.bool => {
                    if (std.mem.eql(u8, value_str, "true")) {
                        maybe_arg_value = CliValue{
                            .bool = true,
                        };
                    } else if (std.mem.eql(u8, value_str, "false")) {
                        maybe_arg_value = CliValue{
                            .bool = false,
                        };
                    } else {
                        return CliParsingError.InvalidBooleanValue;
                    }
                },
                CliType.string => {
                    maybe_arg_value = CliValue{ .string = value_str };
                },
            }
        } else {
            return CliParsingError.UnknownArgument;
        }

        return Arg{
            .name = arg_name.?,
            .value = maybe_arg_value.?,
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

        var args = std.ArrayList(Arg).empty;
        const curr_name = self.cli_args[self.offset.*];
        self.offset.* += 1;

        var maybe_target_command_def: ?CommandDefinition = null;
        for (self.valid_commands) |candidate_command| {
            if (std.mem.eql(u8, candidate_command.name, curr_name)) {
                maybe_target_command_def = candidate_command;
                break;
            }
        }

        if (maybe_target_command_def) |target_command_def| {
            // 1. chomp all arguments
            while (true) {
                var arg_parser = ArgParser.init(
                    self.offset,
                    self.cli_args,
                    target_command_def.possible_args.items,
                );
                const maybe_arg = try arg_parser.parse();

                if (maybe_arg) |arg| {
                    args.append(self.allocator, arg) catch unreachable;
                } else {
                    break;
                }
            }

            // 2. make sure all required arguments have been populated. if not, return
            // an error
            for (target_command_def.possible_args.items) |possible_arg| {
                if (possible_arg.required) {
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
            }

            // 3. chomp subcommand if available
            var subcommand_parser = CommandParser.init(
                std.testing.allocator,
                self.offset,
                self.cli_args,
                target_command_def.possible_subcommands.items,
            );
            const maybe_subcommand = try subcommand_parser.parse(allocator);

            if (maybe_subcommand) |subcommand| {
                const subcommand_ptr = allocator.create(Command) catch unreachable;
                subcommand_ptr.* = subcommand;
                return Command{
                    .allocator = allocator,

                    .name = curr_name,
                    .args = args,
                    .subcommand = subcommand_ptr,
                };
            } else {
                return Command{
                    .allocator = allocator,

                    .name = curr_name,
                    .args = args,
                    .subcommand = null,
                };
            }
        } else {
            return CliParsingError.UnknownCommand;
        }
    }
};

pub const CliApp = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    offset: usize,

    name: []const u8,
    help: []const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_commands: std.ArrayList(CommandDefinition),

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        help: []const u8,
        possible_args: std.ArrayList(ArgDefinition),
        possible_commands: std.ArrayList(CommandDefinition),
    ) Self {
        return Self{
            .allocator = allocator,
            .name = name,
            .help = help,
            .possible_args = possible_args,
            .offset = 0,
            .possible_commands = possible_commands,
        };
    }

    pub fn deinit(self: *Self) void {
        self.possible_args.deinit(self.allocator);
        for (self.possible_commands.items) |*possible_command| {
            possible_command.deinit();
        }
        self.possible_commands.deinit(self.allocator);
    }

    pub fn printHelp(self: *const Self) void {
        std.debug.print("{s}\n\n", .{self.help});
        std.debug.print("USAGE: {s}", .{self.name});
        var option_padding_size: usize = 0;
        var command_padding_size: usize = 0;
        for (self.possible_args.items) |possible_arg| {
            if (possible_arg.required) {
                std.debug.print(" --{s} <{s}>", .{ self.name, self.name });
            }
            const current_length: usize = possible_arg.argSummaryLengthWithoutHelp();
            if (current_length > option_padding_size) {
                option_padding_size = current_length;
            }
        }
        if (self.possible_args.items.len > 0) {
            std.debug.print(" [OPTIONS]", .{});
        }
        if (self.possible_commands.items.len > 0) {
            std.debug.print(" [COMMAND]", .{});
            std.debug.print("\n\nCommands:\n", .{});
            for (self.possible_commands.items) |possible_command| {
                const current_length: usize = possible_command.commandSummaryLengthWithoutHelp();
                if (current_length > option_padding_size) {
                    command_padding_size = current_length;
                }
            }
            for (self.possible_commands.items) |possible_command| {
                possible_command.printCommandSummary(command_padding_size);
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
    pub fn parse(self: *Self, allocator: std.mem.Allocator, argc: usize, argv: [][]const u8) CliParsingError!Command {
        std.debug.assert(self.possible_commands.items.len != 0);

        // first arg is always the program name
        if (argc == 1) {
            return CliParsingError.MissingCommand;
        }

        var parser = CommandParser.init(std.testing.allocator, &self.offset, argv[1..], self.possible_commands.items);

        const maybe_subcommand = try parser.parse(allocator);

        if (maybe_subcommand) |subcommand| {
            return subcommand;
        } else {
            return CliParsingError.MissingCommand;
        }
    }
};

pub const CliAppBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    help: []const u8,
    possible_args: std.ArrayList(ArgDefinition),
    possible_commands: std.ArrayList(CommandDefinition),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, help: []const u8) Self {
        return Self{
            .allocator = allocator,

            .name = name,
            .help = help,
            .possible_args = std.ArrayList(ArgDefinition).empty,
            .possible_commands = std.ArrayList(CommandDefinition).empty,
        };
    }

    pub fn deinit(s: *Self) void {
        var self = s;
        self.possible_args.deinit(self.allocator);
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

    pub fn withCommand(s: Self, command_def: CommandDefinition) Self {
        var self = s;
        self.possible_commands.append(self.allocator, command_def) catch unreachable;
        return self;
    }

    pub fn build(self: Self) CliDefinitionError!CliApp {
        for (0..self.possible_args.items.len) |i| {
            for (i..self.possible_args.items.len) |j| {
                if (i == j) {
                    continue;
                }
                if (self.possible_args.items[i].overlapsWith(&self.possible_args.items[j])) {
                    var s = self;
                    s.deinit();
                    return CliDefinitionError.DuplicateArgumentDefined;
                }
            }
        }

        for (0..self.possible_commands.items.len) |i| {
            for (i..self.possible_commands.items.len) |j| {
                if (i == j) {
                    continue;
                }
                if (self.possible_commands.items[i].overlapsWith(&self.possible_commands.items[j])) {
                    var s = self;
                    s.deinit();
                    return CliDefinitionError.DuplicateCommandDefined;
                }
            }
        }

        return CliApp.init(self.allocator, self.name, self.help, self.possible_args, self.possible_commands);
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

    try std.testing.expectEqualStrings(arg_def.long_name, "name");
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
    try std.testing.expectEqualStrings(arg1.long_name, "commandArg1");
    try std.testing.expectEqualStrings(arg1.help, "test help msg for commandArg1");
    try std.testing.expectEqual(arg1.ty, CliType.u64);

    const arg2 = command_def.possible_args.items[1];
    try std.testing.expectEqualStrings(arg2.long_name, "commandArg2");
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
    try std.testing.expectEqualStrings(arg1.long_name, "commandArg1");
    try std.testing.expectEqualStrings(arg1.help, "test help msg for commandArg1");
    try std.testing.expectEqual(arg1.ty, CliType.u64);

    try std.testing.expectEqual(command_def.possible_subcommands.items.len, 2);

    const subcommand1 = command_def.possible_subcommands.items[0];
    try std.testing.expectEqualStrings(subcommand1.name, "subcommand1");
    try std.testing.expectEqualStrings(subcommand1.help, "test help msg for subcommand1");
    try std.testing.expectEqual(subcommand1.possible_args.items.len, 1);
    const subcommand1_arg1 = subcommand1.possible_args.items[0];
    try std.testing.expectEqualStrings(subcommand1_arg1.long_name, "subcommand1Arg1");
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

test "arg_parser_parses_bool_true" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-b", "true" };
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
    try std.testing.expectEqual(arg.value.bool, true);
}

test "arg_parser_parses_bool_false" {
    var offset: usize = 0;
    var cli_args: [2][]const u8 = [_][]const u8{ "-b", "false" };
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
    try std.testing.expectEqual(arg.value.bool, false);
}

test "arg_parser_fails_to_parse_invalid_bool" {
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
    const err = parser.parse();

    try std.testing.expectEqual(err, CliParsingError.InvalidBooleanValue);
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
    var cli_args: [5][]const u8 = [_][]const u8{ "command", "--file", "test.txt", "-b", "true" };
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

    var command1 = try cli_parser.parse(std.testing.allocator, argc1, &argv1);
    defer command1.deinit();

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
    var command2 = try cli_parser.parse(std.testing.allocator, argc2, &argv2);
    defer command2.deinit();

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
