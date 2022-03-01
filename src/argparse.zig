// Libraries
const std = @import("std");

// Modules
const io = std.io;
const fmt = std.fmt;
const eql = std.mem.eql;
const len = std.mem.len;
const copy = std.mem.copy;
const testing = std.testing;
const startsWith = std.mem.startsWith;

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

pub const AppInfo = struct {
    app_name: []const u8,
    app_description: []const u8,
    app_version: Version,
};

pub const AppOption = struct {
    name: []const u8,
    long: ?[]const u8 = null,
    short: ?[]const u8 = null,
    metavar: []const u8 = "ARG",
    description: []const u8,
    takes: comptime_int = 0,
    required: bool = false,
};

pub const AppPositional = struct {
    name: []const u8,
    metavar: []const u8 = "ARG",
    description: []const u8,
};

pub const AppOptionPositional = union(enum) {
    option: AppOption,
    positional: AppPositional,
};

pub fn ArgumentParser(comptime info: AppInfo, comptime opt_pos: []const AppOptionPositional) type {
    return struct {
        const help_option = AppOption{
            .name = "help",
            .long = "--help",
            .short = "-h",
            .description = "Display this and exit",
        };

        fn displayNameVersionWriter(writer: anytype) !void {
            const name = info.app_name;
            const major = info.app_version.major;
            const minor = info.app_version.minor;
            const patch = info.app_version.patch;

            try writer.print(bold ++ green ++ "{s}" ++ bold ++ blue ++ " {d}.{d}.{d}\n" ++ reset, .{ name, major, minor, patch });
        }

        pub fn displayNameVersion() !void {
            const stdout = io.getStdOut().writer();
            try displayNameVersionWriter(stdout);
        }

        fn displayDescriptionWriter(writer: anytype) !void {
            try writer.print("{s}\n", .{info.app_description});
        }

        pub fn displayDescription() !void {
            const stdout = io.getStdOut().writer();
            try displayDescriptionWriter(stdout);
        }

        fn displayUsageWriter(writer: anytype) !void {
            try writer.print("{s}", .{bold ++ yellow ++ "USAGE\n" ++ reset});
            try writer.print("    {s} [OPTION]", .{info.app_name});

            inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                .positional => |p| try writer.writeAll(" " ++ p.metavar),
                .option => {},
            };

            try writer.writeByte('\n');
        }

        pub fn displayUsage() !void {
            const stdout = io.getStdOut().writer();
            try displayUsageWriter(stdout);
        }

        fn displayOptionWriter(comptime option: AppOption, writer: anytype) !void {
            const short = if (option.short) |s| s else "";
            const sep = if (option.short != null and option.long != null) ", " else "";
            const long = if (option.long) |l| l else "";
            if (option.short == null and option.long == null) @compileError("Option short and long can't both be empty");
            const metavar = switch (option.takes) {
                0 => "",
                1 => " <" ++ option.metavar ++ ">",
                else => " <" ++ option.metavar ++ "...>",
            };
            const description = option.description;

            try writer.print("    {s}\n", .{bold ++ green ++ short ++ sep ++ long ++ metavar ++ reset});
            try writer.print("        {s}\n", .{description});
        }

        fn displayPositionalWriter(comptime positional: AppPositional, writer: anytype) !void {
            const metavar = positional.metavar;
            const description = positional.description;

            try writer.print("    {s}\n", .{bold ++ green ++ metavar ++ reset});
            try writer.print("        {s}\n", .{description});
        }

        fn displayOptionPositionalWriter(writer: anytype) !void {
            var n_pos: usize = 0;

            inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                .positional => n_pos += 1,
                else => {},
            };

            if (comptime n_pos > 0) {
                try writer.print("{s}", .{bold ++ yellow ++ "POSITIONALS\n" ++ reset});
                inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                    .positional => |pos| {
                        try writer.print("\n", .{});
                        try displayPositionalWriter(pos, writer);
                    },
                    else => continue,
                };
                try writer.print("\n", .{});
            }

            try writer.print("{s}", .{bold ++ yellow ++ "OPTIONS\n" ++ reset});
            inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                .option => |opt| {
                    try writer.print("\n", .{});
                    try displayOptionWriter(opt, writer);
                },
                else => {},
            };

            try writer.print("\n", .{});
            try displayOptionWriter(help_option, writer);
        }

        pub fn displayOptionPositional() !void {
            const stdout = io.getStdOut().writer();
            try displayOptionPositionalWriter(stdout);
        }

        fn displayHelpWriter(writer: anytype) !void {
            try displayNameVersionWriter(writer);
            try writer.writeByte('\n');
            try displayDescriptionWriter(writer);
            try writer.writeByte('\n');
            try displayUsageWriter(writer);
            try writer.writeByte('\n');
            try displayOptionPositionalWriter(writer);
            try writer.writeByte('\n');
        }

        pub fn displayHelp() !void {
            const stdout = io.getStdOut().writer();
            try displayHelpWriter(stdout);
        }

        fn ParserResultFromOptionPositional() type {
            const n_fields = opt_pos.len;

            var fields: [n_fields]StructField = undefined;

            inline for (opt_pos) |opt_pos_, i| comptime switch (opt_pos_) {
                .option => |opt| {
                    const OptT = switch (opt.takes) {
                        0 => bool,
                        1 => []const u8,
                        else => |n| [n][]const u8,
                    };

                    fields[i] = .{
                        .name = opt.name,
                        .field_type = OptT,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf(OptT),
                    };
                },
                .positional => |pos| {
                    const PosT = []const u8;

                    fields[i] = .{
                        .name = pos.name,
                        .field_type = PosT,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf(PosT),
                    };
                },
            };

            const decls: [0]Declaration = .{};

            const parser_result_type_information = TypeInfo{
                .Struct = .{
                    .layout = .Auto,
                    .fields = &fields,
                    .decls = &decls,
                    .is_tuple = false,
                },
            };

            const ParserResultT = @Type(parser_result_type_information);

            return ParserResultT;
        }

        pub const ParserResult = ParserResultFromOptionPositional();

        fn parseArgumentSlice(arguments: [][]const u8) !ParserResult {
            // Result struct
            var parsed_args: ParserResult = undefined;

            // Array for tracking required options
            var pos_opt_present = [_]bool{false} ** opt_pos.len;

            // Initialize result struct
            inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                .option => |opt| switch (opt.takes) {
                    0 => @field(parsed_args, opt.name) = false,
                    1 => @field(parsed_args, opt.name) = "",
                    else => |n| {
                        var i: usize = 0;
                        while (i < n) : (i += 1) @field(parsed_args, opt.name)[i] = "";
                    },
                },
                .positional => |pos| @field(parsed_args, pos.name) = "",
            };

            // Parse options
            var i: usize = 0;
            var current: usize = 0;
            var opt_found: bool = undefined;
            while (i < arguments.len) {
                opt_found = false;

                // Get slice from null terminated string
                const arg = arguments[i][0..len(arguments[i])];

                // Check if -h or --help is present
                if (startsWith(u8, arg, "-h") or startsWith(u8, arg, "--help")) {
                    const stdout = std.io.getStdOut().writer();
                    try displayHelpWriter(stdout);
                    std.os.exit(0);
                }

                inline for (opt_pos) |opt_pos_, j| switch (opt_pos_) {
                    .option => |opt| if (!opt_found) {
                        const short = opt.short orelse "";
                        const long = opt.long orelse "";

                        const starts_with_short = len(short) > 0 and startsWith(u8, arg, short);
                        const starts_with_long = len(long) > 0 and startsWith(u8, arg, long);

                        if (starts_with_short or starts_with_long) {
                            switch (opt.takes) {
                                0 => {
                                    @field(parsed_args, opt.name) = true;
                                    i += 1;
                                    opt_found = true;
                                    pos_opt_present[j] = true;
                                },
                                1 => {
                                    // Check if there are enough args
                                    if (i + 1 >= arguments.len) {
                                        const stderr = std.io.getStdErr().writer();
                                        try stderr.writeAll(bold ++ red ++ "Error: " ++ reset ++ "Missing arguments for option " ++ bold ++ green ++ opt.name ++ reset ++ ".\n");
                                        try stderr.writeAll("Use " ++ bold ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information.\n");
                                        std.os.exit(0);
                                    }

                                    const opt_arg = arguments[i + 1][0..len(arguments[i + 1])];
                                    @field(parsed_args, opt.name) = opt_arg;
                                    i += 2;
                                    opt_found = true;
                                    pos_opt_present[j] = true;
                                },
                                else => |n| {
                                    // Check if there are enough args
                                    if (i + n >= arguments.len) {
                                        const stderr = std.io.getStdErr().writer();
                                        try stderr.writeAll(bold ++ red ++ "Error: " ++ reset ++ "Missing arguments for option " ++ bold ++ green ++ opt.name ++ reset ++ ".\n");
                                        try stderr.writeAll("Use " ++ bold ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information.\n");
                                        std.os.exit(0);
                                    }

                                    const opt_args = arguments[i + 1 .. i + 1 + n];
                                    for (opt_args) |opt_arg, k| @field(parsed_args, opt.name)[k] = opt_arg[0..len(opt_arg)];
                                    i += n + 1;
                                    opt_found = true;
                                    pos_opt_present[j] = true;
                                },
                            }

                            current = i;
                        }
                    },
                    .positional => if (!opt_found) {
                        i += 1;
                    },
                };
            }

            // Parse positionals
            i = current;
            inline for (opt_pos) |opt_pos_, j| switch (opt_pos_) {
                .option => {},
                .positional => |pos| if (current < arguments.len) {
                    // Check if there are enough args
                    if (i >= arguments.len) {
                        const stderr = std.io.getStdErr().writer();
                        try stderr.writeAll(bold ++ red ++ "Error: " ++ reset ++ "Missing positional " ++ bold ++ green ++ pos.metavar ++ reset ++ ".\n");
                        try stderr.writeAll("Use " ++ bold ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information.\n");
                        std.os.exit(0);
                    }

                    // Get slice from null terminated string
                    const arg = arguments[i][0..len(arguments[i])];
                    @field(parsed_args, pos.name) = arg;
                    i += 1;
                    pos_opt_present[j] = true;
                },
            };

            // Check if required optionals were present
            inline for (opt_pos) |opt_pos_, j| switch (opt_pos_) {
                .option => |opt| if (opt.required) {
                    if (!pos_opt_present[j]) {
                        const stderr = std.io.getStdErr().writer();
                        try stderr.writeAll(bold ++ red ++ "Error: " ++ reset ++ "Required option " ++ bold ++ green ++ opt.name ++ reset ++ " is not present.\n");
                        try stderr.writeAll("Use " ++ bold ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information.\n");
                        std.os.exit(0);
                    }
                },
                .positional => |pos| if (!pos_opt_present[j]) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.writeAll(bold ++ red ++ "Error: " ++ reset ++ "Positional argument " ++ bold ++ green ++ pos.metavar ++ reset ++ " is not present.\n");
                    try stderr.writeAll("Use " ++ bold ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information.\n");
                    std.os.exit(0);
                },
            };

            return parsed_args;
        }

        pub fn parseArgumentsAllocator(allocator: Allocator) !ParserResult {
            var args = ArrayList([]const u8).init(allocator);
            defer args.deinit();

            var it = try std.process.argsWithAllocator(allocator);
            _ = it.skip();
            while (it.next()) |arg| try args.append(arg);

            return try parseArgumentSlice(args.items);
        }
    };
}

test "Argparse displayNameVersionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "Foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{});

    try Parser.displayNameVersionWriter(lw);
    const str = bold ++ green ++ "Foo" ++ bold ++ blue ++ " 1.2.3\n" ++ reset;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayDescriptionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "foo",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{});

    try Parser.displayDescriptionWriter(lw);
    const str = "foo\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayUsageWriter with option and positional" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .short = "-b",
                .description = "bar",
            },
        },
        .{
            .positional = .{
                .name = "baz",
                .description = "baz",
            },
        },
    });

    try Parser.displayUsageWriter(lw);
    const str = bold ++ yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION] ARG\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayUsageWriter without options nor positionals" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{});

    try Parser.displayUsageWriter(lw);
    const str = bold ++ yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION]\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayUsageWriter with only options" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .short = "-b",
                .description = "bar",
            },
        },
        .{
            .option = .{
                .name = "cux",
                .long = "--cux",
                .short = "-c",
                .description = "cux",
            },
        },
    });

    try Parser.displayUsageWriter(lw);
    const str = bold ++ yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION]\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayUsageWriter with only positionals" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .positional = .{
                .name = "x",
                .metavar = "X",
                .description = "x",
            },
        },
        .{
            .positional = .{
                .name = "y",
                .metavar = "Y",
                .description = "y",
            },
        },
        .{
            .positional = .{
                .name = "z",
                .metavar = "Z",
                .description = "z",
            },
        },
    });

    try Parser.displayUsageWriter(lw);
    const str = bold ++ yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION] X Y Z\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayPositionalWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{});

    const positional = .{
        .name = "foo",
        .metavar = "FOO",
        .description = "bar",
    };

    try Parser.displayPositionalWriter(positional, lw);
    const str = "    " ++ bold ++ green ++ "FOO" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
    };

    try Parser.displayOptionWriter(option, lw);
    const str = "    " ++ bold ++ green ++ "-f, --foo <ARG...>" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionPositionalWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
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
            .positional = .{
                .name = "bar",
                .metavar = "BAR",
                .description = "bar",
            },
        },
    });

    try Parser.displayOptionPositionalWriter(lw);

    const str1 = bold ++ yellow ++ "POSITIONALS\n" ++ reset ++ "\n";
    const str2 = "    " ++ bold ++ green ++ "BAR" ++ reset ++ "\n";
    const str3 = "        bar\n\n";
    const str4 = bold ++ yellow ++ "OPTIONS\n" ++ reset ++ "\n";
    const str5 = "    " ++ bold ++ green ++ "-f, --foo <FOO...>" ++ reset ++ "\n";
    const str6 = "        foo\n\n";
    const str7 = "    " ++ bold ++ green ++ "-h, --help" ++ reset ++ "\n";
    const str8 = "        Display this and exit\n";
    const str = str1 ++ str2 ++ str3 ++ str4 ++ str5 ++ str6 ++ str7 ++ str8;

    try testing.expectEqualStrings(list.items, str);
}

test "Argparse ParserResultTypeFromOptionPositional" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
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
            .positional = .{
                .name = "x",
                .metavar = "X",
                .description = "x",
            },
        },
        .{
            .positional = .{
                .name = "y",
                .metavar = "Y",
                .description = "y",
            },
        },
    });

    const ParserResult = Parser.ParserResultFromOptionPositional();
    const info = @typeInfo(ParserResult).Struct;

    try testing.expect(info.fields.len == 4);

    try testing.expect(info.fields[0].field_type == bool);
    try testing.expectEqualStrings(info.fields[0].name, "foo");

    try testing.expect(info.fields[1].field_type == [3][]const u8);
    try testing.expectEqualStrings(info.fields[1].name, "bar");

    try testing.expect(info.fields[2].field_type == []const u8);
    try testing.expectEqualStrings(info.fields[2].name, "x");

    try testing.expect(info.fields[3].field_type == []const u8);
    try testing.expectEqualStrings(info.fields[3].name, "y");
}

test "Argparse parseArgumentSlice option takes 0" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "foo",
                .long = "--foo",
                .short = "-f",
                .description = "",
            },
        },
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .description = "",
            },
        },
    });

    var args_1 = [_][]const u8{"-f"};
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expect(parsed_args_1.foo == true);
    try testing.expect(parsed_args_1.bar == false);

    var args_2 = [_][]const u8{"--foo"};
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expect(parsed_args_2.foo == true);
    try testing.expect(parsed_args_2.bar == false);

    var args_3 = [_][]const u8{ "-f", "--bar" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expect(parsed_args_3.foo == true);
    try testing.expect(parsed_args_3.bar == true);
}

test "Argparse parseArgumentSlice option takes 1" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "foo",
                .long = "--foo",
                .short = "-f",
                .description = "",
                .takes = 1,
            },
        },
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .description = "",
                .takes = 1,
            },
        },
    });

    var args_1 = [_][]const u8{ "-f", "abc" };
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expectEqualStrings(parsed_args_1.foo, "abc");
    try testing.expectEqualStrings(parsed_args_1.bar, "");

    var args_2 = [_][]const u8{ "--foo", "lala" };
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expectEqualStrings(parsed_args_2.foo, "lala");
    try testing.expectEqualStrings(parsed_args_2.bar, "");

    var args_3 = [_][]const u8{ "-f", "a", "--bar", "b" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expectEqualStrings(parsed_args_3.foo, "a");
    try testing.expectEqualStrings(parsed_args_3.bar, "b");

    var args_4 = [_][]const u8{ "-f", "--bar" };
    var parsed_args_4 = try Parser.parseArgumentSlice(args_4[0..]);
    try testing.expectEqualStrings(parsed_args_4.foo, "--bar");
    try testing.expectEqualStrings(parsed_args_4.bar, "");
}

test "Argparse parseArgumentSlice option takes n" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "foo",
                .long = "--foo",
                .short = "-f",
                .description = "",
                .takes = 2,
            },
        },
        .{
            .option = .{
                .name = "bar",
                .short = "-b",
                .description = "",
                .takes = 3,
            },
        },
    });

    var args_1 = [_][]const u8{ "-f", "a", "b" };
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expectEqualStrings(parsed_args_1.foo[0], "a");
    try testing.expectEqualStrings(parsed_args_1.foo[1], "b");
    try testing.expectEqualStrings(parsed_args_1.bar[0], "");
    try testing.expectEqualStrings(parsed_args_1.bar[1], "");
    try testing.expectEqualStrings(parsed_args_1.bar[2], "");

    var args_2 = [_][]const u8{ "--foo", "x", "y" };
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expectEqualStrings(parsed_args_2.foo[0], "x");
    try testing.expectEqualStrings(parsed_args_2.foo[1], "y");
    try testing.expectEqualStrings(parsed_args_2.bar[0], "");
    try testing.expectEqualStrings(parsed_args_2.bar[1], "");
    try testing.expectEqualStrings(parsed_args_2.bar[2], "");

    var args_3 = [_][]const u8{ "-b", "1", "2", "3" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expectEqualStrings(parsed_args_3.foo[0], "");
    try testing.expectEqualStrings(parsed_args_3.foo[1], "");
    try testing.expectEqualStrings(parsed_args_3.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_3.bar[1], "2");
    try testing.expectEqualStrings(parsed_args_3.bar[2], "3");

    var args_4 = [_][]const u8{ "-b", "-f", "a", "b" };
    var parsed_args_4 = try Parser.parseArgumentSlice(args_4[0..]);
    try testing.expectEqualStrings(parsed_args_4.foo[0], "");
    try testing.expectEqualStrings(parsed_args_4.foo[1], "");
    try testing.expectEqualStrings(parsed_args_4.bar[0], "-f");
    try testing.expectEqualStrings(parsed_args_4.bar[1], "a");
    try testing.expectEqualStrings(parsed_args_4.bar[2], "b");
}

test "Argparse parseArgumentSlice positional" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .positional = .{
                .name = "x",
                .metavar = "X",
                .description = "x",
            },
        },
        .{
            .positional = .{
                .name = "y",
                .metavar = "Y",
                .description = "y",
            },
        },
    });

    var args_1 = [_][]const u8{ "1", "2" };
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expectEqualStrings(parsed_args_1.x, "1");
    try testing.expectEqualStrings(parsed_args_1.y, "2");
}

test "Argparse parseArgumentSlice" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "foo",
                .short = "-f",
                .description = "",
            },
        },
        .{
            .option = .{
                .name = "bar",
                .short = "-b",
                .description = "",
                .takes = 1,
            },
        },
        .{
            .option = .{
                .name = "baz",
                .short = "-z",
                .description = "",
                .takes = 2,
            },
        },
        .{
            .positional = .{
                .name = "cux",
                .description = "",
            },
        },
    });

    var args_1 = [_][]const u8{};
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expect(parsed_args_1.foo == false);
    try testing.expectEqualStrings(parsed_args_1.bar, "");
    try testing.expectEqualStrings(parsed_args_1.baz[0], "");
    try testing.expectEqualStrings(parsed_args_1.baz[1], "");
    try testing.expectEqualStrings(parsed_args_1.cux, "");

    var args_2 = [_][]const u8{"-f"};
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expect(parsed_args_2.foo == true);
    try testing.expectEqualStrings(parsed_args_2.bar, "");
    try testing.expectEqualStrings(parsed_args_2.baz[0], "");
    try testing.expectEqualStrings(parsed_args_2.baz[1], "");
    try testing.expectEqualStrings(parsed_args_2.cux, "");

    var args_3 = [_][]const u8{ "-b", "a" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expect(parsed_args_3.foo == false);
    try testing.expectEqualStrings(parsed_args_3.bar, "a");
    try testing.expectEqualStrings(parsed_args_3.baz[0], "");
    try testing.expectEqualStrings(parsed_args_3.baz[1], "");
    try testing.expectEqualStrings(parsed_args_3.cux, "");

    var args_4 = [_][]const u8{ "-z", "a", "b" };
    var parsed_args_4 = try Parser.parseArgumentSlice(args_4[0..]);
    try testing.expect(parsed_args_4.foo == false);
    try testing.expectEqualStrings(parsed_args_4.bar, "");
    try testing.expectEqualStrings(parsed_args_4.baz[0], "a");
    try testing.expectEqualStrings(parsed_args_4.baz[1], "b");
    try testing.expectEqualStrings(parsed_args_4.cux, "");

    var args_5 = [_][]const u8{"a"};
    var parsed_args_5 = try Parser.parseArgumentSlice(args_5[0..]);
    try testing.expect(parsed_args_5.foo == false);
    try testing.expectEqualStrings(parsed_args_5.bar, "");
    try testing.expectEqualStrings(parsed_args_5.baz[0], "");
    try testing.expectEqualStrings(parsed_args_5.baz[1], "");
    try testing.expectEqualStrings(parsed_args_5.cux, "a");

    var args_6 = [_][]const u8{ "-f", "-b", "a", "-z", "b", "c", "d" };
    var parsed_args_6 = try Parser.parseArgumentSlice(args_6[0..]);
    try testing.expect(parsed_args_6.foo == true);
    try testing.expectEqualStrings(parsed_args_6.bar, "a");
    try testing.expectEqualStrings(parsed_args_6.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_6.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_6.cux, "d");

    var args_7 = [_][]const u8{ "-b", "a", "-f", "-z", "b", "c", "d" };
    var parsed_args_7 = try Parser.parseArgumentSlice(args_7[0..]);
    try testing.expect(parsed_args_7.foo == true);
    try testing.expectEqualStrings(parsed_args_7.bar, "a");
    try testing.expectEqualStrings(parsed_args_7.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_7.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_7.cux, "d");

    var args_8 = [_][]const u8{ "-z", "b", "c", "-b", "a", "-f", "d" };
    var parsed_args_8 = try Parser.parseArgumentSlice(args_8[0..]);
    try testing.expect(parsed_args_8.foo == true);
    try testing.expectEqualStrings(parsed_args_8.bar, "a");
    try testing.expectEqualStrings(parsed_args_8.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_8.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_8.cux, "d");
}

test "Argparse parseArgumentSlice option required" {
    const Parser = ArgumentParser(.{
        .app_name = "name",
        .app_description = "description",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &[_]AppOptionPositional{
        .{
            .option = .{
                .name = "foo",
                .long = "--foo",
                .short = "-f",
                .description = "description",
                .required = true,
            },
        },
    });

    var args_1 = [_][]const u8{"-f"};
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expect(parsed_args_1.foo == true);

    var args_2 = [_][]const u8{"--foo"};
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expect(parsed_args_2.foo == true);
}
