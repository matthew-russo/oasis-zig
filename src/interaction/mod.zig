pub const cli = @import("cli/parser.zig");

test {
    // `refAllDecls` in root.zig only references decls, it does not pull in the
    // tests of imported files, so name them explicitly
    _ = cli;
}
