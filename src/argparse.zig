// Libraries
const std = @import("std");

// Modules
const io = std.io;
const fmt = std.fmt;
const eql = std.mem.eql;
const len = std.mem.len;
const testing = std.testing;

// Types
const File = std.fs.File;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;
const StructField = TypeInfo.StructField;
const Declaration = TypeInfo.Declaration;

// Ansi format
const reset = "\x1b[000m";
const bold = "\x1b[001m";
const red = "\x1b[091m";
const blue = "\x1b[094m";
const green = "\x1b[092m";
const yellow = "\x1b[093m";

pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,
};

pub const ParserConfig = struct {
    bin_name: []const u8,
    bin_info: []const u8,
    bin_version: Version,
};

pub const ParserOption = struct {
    name: []const u8,
    long: []const u8,
    short: ?[]const u8 = null,
    metavar: []const u8 = "ARG",
    description: []const u8,
    takes: comptime_int = 0,
    required: bool = false,
};

pub const ParserSubcommand = struct {
    name: []const u8,
    description: []const u8,
    opts_subcmds: []const ParserOptionSubcommand,
};

pub const ParserOptionSubcommand = union(enum) {
    option: ParserOption,
    subcommand: ParserSubcommand,
};

pub fn ArgumentParser(comptime config: ParserConfig, comptime parser_opts_subcmds: []const ParserOptionSubcommand) type {
    return struct {
        const Self = @This();
        const help_option = .{
            .name = "help",
            .long = "--help",
            .short = "-h",
            .description = "Display this and exit",
        };

        pub fn displayNameVersionWriter(name: []const u8, version: Version, writer: anytype) !void {
            const major = version.major;
            const minor = version.minor;
            const patch = version.patch;

            try writer.print(bold ++ green ++ "{s}" ++ bold ++ blue ++ " {d}.{d}.{d}\n" ++ reset, .{ name, major, minor, patch });
        }

        pub fn displayParserNameVersionWriter(writer: anytype) !void {
            try displayNameVersionWriter(config.bin_name, config.bin_version, writer);
        }

        pub fn displayParserNameVersion() !void {
            const stdout = io.getStdOut().writer();

            try displayParserNameVersionWriter(stdout);
        }

        pub fn displayInfoWriter(info: []const u8, writer: anytype) !void {
            try writer.print("{s}\n", .{info});
        }

        pub fn displayParserInfoWriter(writer: anytype) !void {
            try displayInfoWriter(config.bin_info, writer);
        }

        pub fn displayParserInfo() !void {
            const stdout = io.getStdOut().writer();

            try displayParserInfoWriter(stdout);
        }

        pub fn displayUsageParserOptionSubcommandWriter(comptime command: []const u8, comptime opts_subcmds: []const ParserOptionSubcommand, writer: anytype) !void {
            var n_subcmds: usize = 0;

            inline for (opts_subcmds) |opt_subcmd| switch (opt_subcmd) {
                .subcommand => n_subcmds += 1,
                .option => {},
            };

            const subcmd = if (n_subcmds > 0) "[SUBCOMMAND|OPTION] " else "";
            const opt = "[OPTION]";

            try writer.print("{s}", .{bold ++ yellow ++ "USAGE\n" ++ reset});
            try writer.print("    {s} {s}{s}\n", .{ command, subcmd, opt });
        }

        pub fn displayParserUsageWriter(writer: anytype) !void {
            try displayUsageParserOptionSubcommandWriter(config.bin_name, parser_opts_subcmds, writer);
        }

        pub fn displayParserUsage() !void {
            const stdout = io.getStdOut().writer();

            try displayParserUsageWriter(stdout);
        }

        pub fn displayParserSubcommandWriter(comptime subcommand: ParserSubcommand, writer: anytype) !void {
            const name = subcommand.name;
            const description = subcommand.description;

            try writer.print("    {s}\n", .{bold ++ green ++ name ++ reset});
            try writer.print("        {s}\n", .{description});
        }

        pub fn displayParserOptionWriter(comptime option: ParserOption, writer: anytype) !void {
            const short = if (option.short) |s| s ++ ", " else "";
            const long = option.long;
            const metavar = switch (option.takes) {
                0 => "",
                1 => " <" ++ option.metavar ++ ">",
                else => " <" ++ option.metavar ++ "...>",
            };
            const description = option.description;

            try writer.print("    {s}\n", .{bold ++ green ++ short ++ long ++ metavar ++ reset});
            try writer.print("        {s}\n", .{description});
        }

        pub fn displayParserOptionSubcommandWriter(comptime opts_subcmds: []const ParserOptionSubcommand, writer: anytype) !void {
            var n_subcmds: usize = 0;

            inline for (opts_subcmds) |opt_subcmd| switch (opt_subcmd) {
                .subcommand => n_subcmds += 1,
                else => {},
            };

            if (comptime n_subcmds > 0) {
                try writer.print("{s}", .{bold ++ yellow ++ "SUBCOMMANDS\n" ++ reset});
                inline for (opts_subcmds) |opt_subcmd| switch (opt_subcmd) {
                    .subcommand => |subcmd| blk: {
                        try writer.print("\n", .{});
                        try displayParserSubcommandWriter(subcmd, writer);
                        break :blk;
                    },
                    else => continue,
                };
                try writer.print("\n", .{});
            }

            try writer.print("{s}", .{bold ++ yellow ++ "OPTIONS\n" ++ reset});
            inline for (opts_subcmds) |opt_subcmd| switch (opt_subcmd) {
                .option => |opt| blk: {
                    try writer.print("\n", .{});
                    try displayParserOptionWriter(opt, writer);
                    break :blk;
                },
                else => {},
            };

            try writer.print("\n", .{});
            try displayParserOptionWriter(help_option, writer);
        }

        pub fn displayParserOptionSubcommand(comptime opts_subcmds: []const ParserOptionSubcommand) !void {
            const stdout = io.getStdOut().writer();

            try displayParserOptionSubcommandWriter(opts_subcmds, stdout);
        }

        fn StructFromOptionSubcommand(comptime opts_subcmds: []const ParserOptionSubcommand) type {
            const n_fields = opts_subcmds.len;
            if (n_fields == 0) @compileError("Subcommand can not have zero options and subcommands");

            var fields: [n_fields]StructField = undefined;

            inline for (opts_subcmds) |opt_subcmd, i| switch (opt_subcmd) {
                .option => |opt| blk: {
                    const OptT = switch (opt.takes) {
                        0 => bool,
                        1 => []const u8,
                        else => [opt.takes][]const u8,
                    };

                    fields[i] = .{
                        .name = opt.name,
                        .field_type = OptT,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf(OptT),
                    };

                    break :blk;
                },
                .subcommand => |subcmd| blk: {
                    const SubcmdT = StructFromOptionSubcommand(subcmd.opts_subcmds);

                    fields[i] = .{
                        .name = subcmd.name,
                        .field_type = SubcmdT,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf(SubcmdT),
                    };

                    break :blk;
                },
            };

            const decls: [0]Declaration = .{};

            const subcommand_type_information = TypeInfo{
                .Struct = .{
                    .layout = .Auto,
                    .fields = &fields,
                    .decls = &decls,
                    .is_tuple = false,
                },
            };

            const SubcommandStruct = @Type(subcommand_type_information);

            return SubcommandStruct;
        }

        pub const ParserResult = StructFromOptionSubcommand(parser_opts_subcmds);

        pub fn parseSlice(comptime T: type, slice: []const u8) !T {
            switch (@typeInfo(T)) {
                .Int => return try fmt.parseInt(T, slice, 10),
                .Float => return try fmt.parseFloat(T, slice),
                .Pointer => return slice,
                else => @compileError("Unsopported type for argument: " ++ @typeName(T)),
            }
        }

        pub fn parseArgumentsOptionAllocator(arguments: [][*:0]u8, comptime opt: ParserOption, container: anytype, allocator: *Allocator) !usize {
            const short = opt.short orelse "";
            const long = opt.long orelse "";

            var consumed: usize = 0;
            var next_arg = arguments[0][0..len(arguments[0])];

            if (eql(u8, next_arg, short) or eql(u8, next_arg, long)) {
                consumed += 1;

                switch (opt.takes) {
                    .n => |n| switch (n) {
                        0 => @field(container, opt.name) = true,
                        1 => blk: {
                            @field(container, opt.name) = try parseSlice(opt.Type, next_arg);
                            consumed += 1;
                            break :blk;
                        },
                        else => {
                            try @field(container, opt.name).init(allocator);
                            try @field(container, opt.name).append(try parseSlice(opt.Type, next_arg));
                        },
                    },
                    .range => |range| switch (range) {
                        .zero_or_more => {},
                        .one_or_more => {},
                    },
                }
            }
        }

        pub fn parseArgumentsParserOptionSubcommandAllocator(arguments: [][*:0]u8, comptime opts_subcmds: []const ParserOptionSubcommand, _: *Allocator) !ParserResult {
            var parsed_args: ParserResult = undefined;

            var i: usize = 0;
            while (i < arguments.len) : (i += 1) {
                // Get slice from null terminated string
                const arg = arguments[i][0..len(arguments[i])];

                inline for (opts_subcmds) |opt_subcmd| switch (opt_subcmd) {
                    .subcommand => |subcmd| blk: {
                        if (eql(u8, arg, subcmd.name)) {}
                        break :blk;
                    },
                    .option => |opt| blk: {
                        const short = opt.short orelse "";
                        const long = opt.long orelse "";
                        if (eql(u8, arg, short) or eql(u8, arg, long)) {}
                        break :blk;
                    },
                };
            }

            return parsed_args;
        }

        pub fn parseAllocator(allocator: *Allocator) !ParserResult {
            const arguments: [][*:0]const u8 = std.os.argv;

            return try parseArgumentsParserOptionSubcommandAllocator(arguments, parser_opts_subcmds, allocator);
        }
    };
}

test "Argparse displayParserNameVersionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "Foo",
        .bin_info = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{});

    try Parser.displayParserNameVersionWriter(w);
    const str = bold ++ green ++ "Foo" ++ bold ++ blue ++ " 1.2.3\n" ++ reset;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayParserInfoWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "foo",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{});

    try Parser.displayParserInfoWriter(w);
    const str = "foo\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayParserUsageWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "foo",
        .bin_info = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .short = "-b",
                .description = "bar",
            },
        },
        .{
            .subcommand = .{
                .name = "baz",
                .description = "baz",
                .opts_subcmds = &[_]ParserOptionSubcommand{},
            },
        },
    });

    try Parser.displayParserUsageWriter(w);
    const str = bold ++ yellow ++ "USAGE\n" ++ reset ++ "    foo [SUBCOMMAND|OPTION] [OPTION]\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayParserSubcommandWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{});

    const subcommand = .{
        .name = "foo",
        .description = "bar",
        .opts_subcmds = &[_]ParserOptionSubcommand{},
    };

    try Parser.displayParserSubcommandWriter(subcommand, w);
    const str = "    " ++ bold ++ green ++ "foo" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayParserOptionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
    };

    try Parser.displayParserOptionWriter(option, w);
    const str = "    " ++ bold ++ green ++ "-f, --foo <ARG...>" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayParserOptionSubcommandWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{});

    const opts_subcmds = &[_]ParserOptionSubcommand{
        .{
            .option = .{
                .name = "foo",
                .long = "--foo",
                .short = "-f",
                .description = "foo",
                .metavar = "FOO",
                .takes = 3,
            },
        },
        .{
            .subcommand = .{
                .name = "bar",
                .description = "bar",
                .opts_subcmds = &[_]ParserOptionSubcommand{},
            },
        },
    };

    try Parser.displayParserOptionSubcommandWriter(opts_subcmds, w);

    const str1 = bold ++ yellow ++ "SUBCOMMANDS\n" ++ reset ++ "\n";
    const str2 = "    " ++ bold ++ green ++ "bar" ++ reset ++ "\n";
    const str3 = "        bar\n\n";
    const str4 = bold ++ yellow ++ "OPTIONS\n" ++ reset ++ "\n";
    const str5 = "    " ++ bold ++ green ++ "-f, --foo <FOO...>" ++ reset ++ "\n";
    const str6 = "        foo\n\n";
    const str7 = "    " ++ bold ++ green ++ "-h, --help" ++ reset ++ "\n";
    const str8 = "        Display this and exit\n";
    const str = str1 ++ str2 ++ str3 ++ str4 ++ str5 ++ str6 ++ str7 ++ str8;

    try testing.expectEqualStrings(list.items, str);
}

test "Argparse StructFromSubcommand" {
    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]ParserOptionSubcommand{});

    const opts_subcmds = &[_]ParserOptionSubcommand{
        .{
            .option = .{
                .name = "foo",
                .long = "--foo",
                .short = "-f",
                .description = "foo",
            },
        },
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .short = "-b",
                .description = "bar",
                .takes = 3,
            },
        },
        .{
            .option = .{
                .name = "baz",
                .long = "--baz",
                .short = "-z",
                .description = "baz",
                .takes = 1,
            },
        },
        .{
            .subcommand = .{
                .name = "qux",
                .description = "qux",
                .opts_subcmds = &[_]ParserOptionSubcommand{
                    .{
                        .option = .{
                            .name = "quux",
                            .long = "--quux",
                            .short = "-q",
                            .description = "quux",
                            .takes = 2,
                        },
                    },
                },
            },
        },
    };

    const OptionSubcommandStruct = Parser.StructFromOptionSubcommand(opts_subcmds);
    const info = @typeInfo(OptionSubcommandStruct).Struct;

    try testing.expect(info.fields.len == 4);

    try testing.expect(info.fields[0].field_type == bool);
    try testing.expectEqualStrings(info.fields[0].name, "foo");

    try testing.expect(info.fields[1].field_type == [3][]const u8);
    try testing.expectEqualStrings(info.fields[1].name, "bar");

    try testing.expect(info.fields[2].field_type == []const u8);
    try testing.expectEqualStrings(info.fields[2].name, "baz");

    var subcmd_struct: OptionSubcommandStruct = .{
        .foo = true,
        .bar = [_][]const u8{ "alpha", "beta", "gamma" },
        .baz = "omega",
        .qux = .{ .quux = [_][]const u8{ "hello", "world" } },
    };

    try testing.expect(subcmd_struct.foo);

    try testing.expectEqualStrings(subcmd_struct.bar[0], "alpha");
    try testing.expectEqualStrings(subcmd_struct.bar[1], "beta");
    try testing.expectEqualStrings(subcmd_struct.bar[2], "gamma");

    try testing.expectEqualStrings(subcmd_struct.baz, "omega");

    try testing.expectEqualStrings(subcmd_struct.qux.quux[0], "hello");
    try testing.expectEqualStrings(subcmd_struct.qux.quux[1], "world");
}
