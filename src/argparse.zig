// Libraries
const std = @import("std");

// Modules
const io = std.io;
const fmt = std.fmt;
const eql = std.mem.eql;
const len = std.mem.len;
const copy = std.mem.copy;
const testing = std.testing;
const indexOf = std.mem.indexOf;
const startsWith = std.mem.startsWith;

// Types
const File = std.fs.File;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;
const EnumField = TypeInfo.EnumField;
const StructField = TypeInfo.StructField;
const Declaration = TypeInfo.Declaration;

// Ansi format
const reset = "\x1b[000m";
const bold = "\x1b[001m";
const red = bold ++ "\x1b[091m";
const blue = bold ++ "\x1b[094m";
const green = bold ++ "\x1b[092m";
const yellow = bold ++ "\x1b[093m";

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
    default: ?[]const []const u8 = null,
    possible_values: ?[]const []const u8 = null,
};

pub const AppPositional = struct {
    name: []const u8,
    metavar: []const u8,
    description: []const u8,
};

pub const AppOptionPositional = union(enum) {
    option: AppOption,
    positional: AppPositional,
};

pub fn ArgumentParser(comptime info: AppInfo, comptime opt_pos: []const AppOptionPositional) type {
    // Validate opt_pos
    inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
        .option => |opt| {
            if (opt.name.len == 0) @compileError("Option name can't be an empty string");
            if (indexOf(u8, opt.name, " ") != null) @compileError("Option name can't contain blank spaces");
            if (opt.short == null and opt.long == null) @compileError("Option short and long can't both be empty");
            if (opt.required and opt.default != null) @compileError("Required option can't have default values");
            switch (opt.takes) {
                0 => {
                    if (opt.default != null) @compileError("Option with 0 arguments can't have default values");
                    if (opt.possible_values != null) @compileError("Option with 0 arguments can't have possible values");
                },
                1 => if (opt.default) |default| {
                    if (default.len != 1) @compileError("Default value for option with 1 argument can only be a single string");
                    if (opt.possible_values) |possible_values| {
                        var found_valid_value = false;
                        for (possible_values) |possible_value| {
                            if (eql(u8, default[0], possible_value)) found_valid_value = true;
                        }
                        if (!found_valid_value) @compileError("Invalid default value for option with possible values");
                    }
                },
                else => |n| if (opt.default) |defaults| {
                    if (defaults.len != n) @compileError("Number of default values for option with many arguments need to the same as the number of taken arguments");
                    if (opt.possible_values) |possible_values| {
                        for (defaults) |default| {
                            var found_valid_value = false;
                            for (possible_values) |possible_value| {
                                if (eql(u8, default, possible_value)) found_valid_value = true;
                            }
                            if (!found_valid_value) @compileError("Invalid default value for option with possible values");
                        }
                    }
                },
            }
            if (opt.possible_values) |possible_values| {
                for (possible_values) |possible_value| {
                    if (possible_value.len == 0) @compileError("Possible value can't be an empty string");
                    if (indexOf(u8, possible_value, " ") != null) @compileError("Possible value can't contain blank spaces");
                }
            }
        },
        .positional => |pos| {
            if (pos.name.len == 0) @compileError("Positional name can't be an empty string");
            if (indexOf(u8, pos.name, " ") != null) @compileError("Positional name can't contain blank spaces");
        },
    };

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

            try writer.print(green ++ "{s}" ++ blue ++ " {d}.{d}.{d}\n" ++ reset, .{ name, major, minor, patch });
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
            try writer.print("{s}", .{yellow ++ "USAGE\n" ++ reset});
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
            const metavar = switch (option.takes) {
                0 => "",
                1 => " <" ++ option.metavar ++ ">",
                else => " <" ++ option.metavar ++ "...>",
            };
            const description = option.description;

            try writer.print("    {s}", .{green ++ short ++ sep ++ long ++ metavar ++ reset});

            if (option.default) |default| {
                try writer.writeAll(green ++ " (default:" ++ reset);
                for (default) |val| try writer.print(blue ++ " {s}" ++ reset, .{val});
                try writer.writeAll(green ++ ")" ++ reset);
            }

            if (option.possible_values) |possible_values| {
                try writer.writeAll(green ++ " (possible values:" ++ reset);
                for (possible_values) |possible_value, i| {
                    const comma = if (i == 0) " " else ", ";
                    try writer.print(green ++ "{s}" ++ reset ++ blue ++ "{s}" ++ reset, .{ comma, possible_value });
                }
                try writer.writeAll(green ++ ")" ++ reset);
            }

            if (option.required) {
                try writer.writeAll(green ++ " (required)" ++ reset);
            }

            try writer.writeAll("\n");

            try writer.print("        {s}\n", .{description});
        }

        fn displayPositionalWriter(comptime positional: AppPositional, writer: anytype) !void {
            const metavar = positional.metavar;
            const description = positional.description;

            try writer.print("    {s}\n", .{green ++ metavar ++ reset});
            try writer.print("        {s}\n", .{description});
        }

        fn displayOptionPositionalWriter(writer: anytype) !void {
            var n_pos: usize = 0;

            inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                .positional => n_pos += 1,
                else => {},
            };

            if (comptime n_pos > 0) {
                try writer.print("{s}", .{yellow ++ "ARGUMENTS\n" ++ reset});
                inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                    .positional => |pos| {
                        try writer.print("\n", .{});
                        try displayPositionalWriter(pos, writer);
                    },
                    else => continue,
                };
                try writer.print("\n", .{});
            }

            try writer.print("{s}", .{yellow ++ "OPTIONS\n" ++ reset});
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

            // Initialize result struct with default values
            inline for (opt_pos) |opt_pos_| switch (opt_pos_) {
                .option => |opt| switch (opt.takes) {
                    0 => if (opt.default) |default| {
                        if (eql(u8, default[0], "on")) @field(parsed_args, opt.name) = true;
                        if (eql(u8, default[0], "off")) @field(parsed_args, opt.name) = false;
                    } else {
                        @field(parsed_args, opt.name) = false;
                    },
                    1 => if (opt.default) |default| {
                        @field(parsed_args, opt.name) = default[0];
                    } else {
                        @field(parsed_args, opt.name) = "";
                    },
                    else => |n| {
                        if (opt.default) |default| {
                            for (default) |val, i| @field(parsed_args, opt.name)[i] = val;
                        } else {
                            var i: usize = 0;
                            while (i < n) : (i += 1) @field(parsed_args, opt.name)[i] = "";
                        }
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

                // Check if -h or --help is present
                if (startsWith(u8, arguments[i], "-h") or startsWith(u8, arguments[i], "--help")) {
                    const stdout = std.io.getStdOut().writer();
                    try displayHelpWriter(stdout);
                    return error.FoundHelpOption;
                }

                inline for (opt_pos) |opt_pos_, j| switch (opt_pos_) {
                    .option => |opt| if (!opt_found) {
                        const short = opt.short orelse "";
                        const long = opt.long orelse "";

                        const starts_with_short = len(short) > 0 and startsWith(u8, arguments[i], short);
                        const starts_with_long = len(long) > 0 and startsWith(u8, arguments[i], long);

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
                                        const opt_display_name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;
                                        try stderr.writeAll(red ++ "Error: " ++ reset ++ "Missing arguments for option " ++ green ++ opt_display_name ++ reset ++ "\n");
                                        try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                                        return error.MissingOptionArgument;
                                    }

                                    const arg = arguments[i + 1];
                                    if (opt.possible_values) |possible_values| {
                                        var found_valid_value = false;
                                        for (possible_values) |possible_value| {
                                            if (eql(u8, arg, possible_value)) {
                                                @field(parsed_args, opt.name) = arg;
                                                found_valid_value = true;
                                            }
                                        }

                                        if (!found_valid_value) {
                                            const stderr = std.io.getStdErr().writer();
                                            const opt_display_name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;
                                            try stderr.print(red ++ "Error: " ++ reset ++ "Invalid argument " ++ green ++ "{s}" ++ reset ++ " for option " ++ green ++ opt_display_name ++ reset ++ "\n", .{arg});
                                            try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                                            return error.InvalidOptionArgument;
                                        }
                                    } else {
                                        @field(parsed_args, opt.name) = arg;
                                    }

                                    i += 2;
                                    opt_found = true;
                                    pos_opt_present[j] = true;
                                },
                                else => |n| {
                                    // Check if there are enough args
                                    if (i + n >= arguments.len) {
                                        const stderr = std.io.getStdErr().writer();
                                        const opt_display_name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;
                                        try stderr.writeAll(red ++ "Error: " ++ reset ++ "Missing arguments for option " ++ green ++ opt_display_name ++ reset ++ "\n");
                                        try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                                        return error.MissingOptionArgument;
                                    }

                                    const args = arguments[i + 1 .. i + 1 + n];
                                    for (args) |arg, k| {
                                        if (opt.possible_values) |possible_values| {
                                            var found_valid_value = false;
                                            for (possible_values) |possible_value| {
                                                if (eql(u8, arg, possible_value)) {
                                                    @field(parsed_args, opt.name)[k] = arg;
                                                    found_valid_value = true;
                                                }
                                            }

                                            if (!found_valid_value) {
                                                const stderr = std.io.getStdErr().writer();
                                                const opt_display_name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;
                                                try stderr.print(red ++ "Error: " ++ reset ++ "Invalid argument " ++ green ++ "{s}" ++ reset ++ " for option " ++ green ++ opt_display_name ++ reset ++ "\n", .{arg});
                                                try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                                                return error.InvalidOptionArgument;
                                            }
                                        } else {
                                            @field(parsed_args, opt.name)[k] = arg;
                                        }
                                    }

                                    i += n + 1;
                                    opt_found = true;
                                    pos_opt_present[j] = true;
                                },
                            }

                            current = i;
                        }
                    },
                    .positional => {},
                };

                if (!opt_found) i += 1;
            }

            // Parse positionals
            inline for (opt_pos) |opt_pos_, j| switch (opt_pos_) {
                .option => {},
                .positional => |pos| if (current < arguments.len) {
                    // Check if there are enough args
                    if (current >= arguments.len) {
                        const stderr = std.io.getStdErr().writer();
                        try stderr.writeAll(red ++ "Error: " ++ reset ++ "Missing positional " ++ green ++ pos.metavar ++ reset ++ "\n");
                        try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                        return error.MissingPositionalArgument;
                    }

                    // Store argument
                    @field(parsed_args, pos.name) = arguments[current];
                    pos_opt_present[j] = true;
                    current += 1;
                },
            };

            // Check if required optionals were present
            inline for (opt_pos) |opt_pos_, j| switch (opt_pos_) {
                .option => |opt| if (opt.required) {
                    if (!pos_opt_present[j]) {
                        const stderr = std.io.getStdErr().writer();
                        const opt_display_name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;
                        try stderr.writeAll(red ++ "Error: " ++ reset ++ "Required option " ++ green ++ opt_display_name ++ reset ++ " is not present\n");
                        try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                        return error.MissingRequiredOption;
                    }
                },
                .positional => |pos| if (!pos_opt_present[j]) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.writeAll(red ++ "Error: " ++ reset ++ "Missing positional " ++ green ++ pos.metavar ++ reset ++ "\n");
                    try stderr.writeAll("Use " ++ green ++ info.app_name ++ " --help" ++ reset ++ " for more information\n");
                    return error.MissingPositionalArgument;
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
    const str = green ++ "Foo" ++ blue ++ " 1.2.3\n" ++ reset;
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
                .metavar = "BAZ",
            },
        },
    });

    try Parser.displayUsageWriter(lw);
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION] BAZ\n";
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
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION]\n";
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
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION]\n";
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
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION] X Y Z\n";
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
    const str = "    " ++ green ++ "FOO" ++ reset ++ "\n        bar\n";
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
    const str = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionWriter with metavar" {
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
        .metavar = "FOO",
    };

    try Parser.displayOptionWriter(option, lw);
    const str = "    " ++ green ++ "-f, --foo <FOO...>" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionWriter required" {
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
        .metavar = "FOO",
        .required = true,
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <FOO...>" ++ reset;
    const str2 = green ++ " (required)" ++ reset;
    const str3 = "\n        bar\n";
    const str = str1 ++ str2 ++ str3;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionWriter with default value" {
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
        .default = &.{ "x", "y" },
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset;
    const str2 = green ++ " (default:" ++ reset;
    const str3 = blue ++ " x" ++ reset;
    const str4 = blue ++ " y" ++ reset;
    const str5 = green ++ ")" ++ reset;
    const str6 = "\n        bar\n";
    const str = str1 ++ str2 ++ str3 ++ str4 ++ str5 ++ str6;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionWriter with possible values" {
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
        .default = &.{ "x", "y" },
        .possible_values = &.{ "x", "y", "z" },
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset;
    const str2 = green ++ " (default:" ++ reset;
    const str3 = blue ++ " x" ++ reset;
    const str4 = blue ++ " y" ++ reset;
    const str5 = green ++ ")" ++ reset;
    const str6 = green ++ " (possible values:" ++ reset;
    const str7 = green ++ " " ++ reset ++ blue ++ "x" ++ reset;
    const str8 = green ++ ", " ++ reset ++ blue ++ "y" ++ reset;
    const str9 = green ++ ", " ++ reset ++ blue ++ "z" ++ reset;
    const str10 = green ++ ")" ++ reset;
    const str11 = "\n        bar\n";
    const str_a = str1 ++ str2 ++ str3 ++ str4 ++ str5;
    const str_b = str6 ++ str7 ++ str8 ++ str9 ++ str10;
    const str_c = str11;
    const str = str_a ++ str_b ++ str_c;
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

    const str1 = yellow ++ "ARGUMENTS\n" ++ reset ++ "\n";
    const str2 = "    " ++ green ++ "BAR" ++ reset ++ "\n";
    const str3 = "        bar\n\n";
    const str4 = yellow ++ "OPTIONS\n" ++ reset ++ "\n";
    const str5 = "    " ++ green ++ "-f, --foo <FOO...>" ++ reset ++ "\n";
    const str6 = "        foo\n\n";
    const str7 = "    " ++ green ++ "-h, --help" ++ reset ++ "\n";
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

test "Argparse parseArgumentSlice option with possible values" {
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
                .possible_values = &.{ "a", "b", "c" },
            },
        },
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .description = "",
                .takes = 2,
                .possible_values = &.{ "1", "2", "3" },
            },
        },
    });

    var args_1 = [_][]const u8{ "-f", "a" };
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expectEqualStrings(parsed_args_1.foo, "a");
    try testing.expectEqualStrings(parsed_args_1.bar[0], "");
    try testing.expectEqualStrings(parsed_args_1.bar[1], "");

    var args_2 = [_][]const u8{ "--foo", "b" };
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expectEqualStrings(parsed_args_2.foo, "b");
    try testing.expectEqualStrings(parsed_args_2.bar[0], "");
    try testing.expectEqualStrings(parsed_args_2.bar[1], "");

    var args_3 = [_][]const u8{ "-f", "a", "--bar", "1", "2" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expectEqualStrings(parsed_args_3.foo, "a");
    try testing.expectEqualStrings(parsed_args_3.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_3.bar[1], "2");
}

test "Argparse parseArgumentSlice option with possible values and default value" {
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
                .possible_values = &.{ "a", "b", "c" },
                .default = &.{"b"},
            },
        },
        .{
            .option = .{
                .name = "bar",
                .long = "--bar",
                .description = "",
                .takes = 2,
                .possible_values = &.{ "1", "2", "3" },
                .default = &.{ "1", "3" },
            },
        },
    });

    var args_1 = [_][]const u8{ "-f", "a" };
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expectEqualStrings(parsed_args_1.foo, "a");
    try testing.expectEqualStrings(parsed_args_1.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_1.bar[1], "3");

    var args_2 = [_][]const u8{ "--foo", "b" };
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expectEqualStrings(parsed_args_2.foo, "b");
    try testing.expectEqualStrings(parsed_args_2.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_2.bar[1], "3");

    var args_3 = [_][]const u8{ "-f", "a", "--bar", "1", "2" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expectEqualStrings(parsed_args_3.foo, "a");
    try testing.expectEqualStrings(parsed_args_3.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_3.bar[1], "2");

    var args_4 = [_][]const u8{};
    var parsed_args_4 = try Parser.parseArgumentSlice(args_4[0..]);
    try testing.expectEqualStrings(parsed_args_4.foo, "b");
    try testing.expectEqualStrings(parsed_args_4.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_4.bar[1], "3");
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
                .metavar = "CUX",
            },
        },
    });

    var args_1 = [_][]const u8{"a"};
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expect(parsed_args_1.foo == false);
    try testing.expectEqualStrings(parsed_args_1.bar, "");
    try testing.expectEqualStrings(parsed_args_1.baz[0], "");
    try testing.expectEqualStrings(parsed_args_1.baz[1], "");
    try testing.expectEqualStrings(parsed_args_1.cux, "a");

    var args_2 = [_][]const u8{ "-f", "a" };
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expect(parsed_args_2.foo == true);
    try testing.expectEqualStrings(parsed_args_2.bar, "");
    try testing.expectEqualStrings(parsed_args_2.baz[0], "");
    try testing.expectEqualStrings(parsed_args_2.baz[1], "");
    try testing.expectEqualStrings(parsed_args_2.cux, "a");

    var args_3 = [_][]const u8{ "-b", "a", "b" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expect(parsed_args_3.foo == false);
    try testing.expectEqualStrings(parsed_args_3.bar, "a");
    try testing.expectEqualStrings(parsed_args_3.baz[0], "");
    try testing.expectEqualStrings(parsed_args_3.baz[1], "");
    try testing.expectEqualStrings(parsed_args_3.cux, "b");

    var args_4 = [_][]const u8{ "-z", "a", "b", "c" };
    var parsed_args_4 = try Parser.parseArgumentSlice(args_4[0..]);
    try testing.expect(parsed_args_4.foo == false);
    try testing.expectEqualStrings(parsed_args_4.bar, "");
    try testing.expectEqualStrings(parsed_args_4.baz[0], "a");
    try testing.expectEqualStrings(parsed_args_4.baz[1], "b");
    try testing.expectEqualStrings(parsed_args_4.cux, "c");

    var args_5 = [_][]const u8{ "-f", "-b", "a", "-z", "b", "c", "d" };
    var parsed_args_5 = try Parser.parseArgumentSlice(args_5[0..]);
    try testing.expect(parsed_args_5.foo == true);
    try testing.expectEqualStrings(parsed_args_5.bar, "a");
    try testing.expectEqualStrings(parsed_args_5.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_5.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_5.cux, "d");

    var args_6 = [_][]const u8{ "-b", "a", "-f", "-z", "b", "c", "d" };
    var parsed_args_6 = try Parser.parseArgumentSlice(args_6[0..]);
    try testing.expect(parsed_args_6.foo == true);
    try testing.expectEqualStrings(parsed_args_6.bar, "a");
    try testing.expectEqualStrings(parsed_args_6.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_6.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_6.cux, "d");

    var args_7 = [_][]const u8{ "-z", "b", "c", "-b", "a", "-f", "d" };
    var parsed_args_7 = try Parser.parseArgumentSlice(args_7[0..]);
    try testing.expect(parsed_args_7.foo == true);
    try testing.expectEqualStrings(parsed_args_7.bar, "a");
    try testing.expectEqualStrings(parsed_args_7.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_7.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_7.cux, "d");
}

test "Argparse parseArgumentSlice with default values" {
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
                .default = &.{"a"},
            },
        },
        .{
            .option = .{
                .name = "baz",
                .short = "-z",
                .description = "",
                .takes = 2,
                .default = &.{ "b", "c" },
            },
        },
        .{
            .positional = .{
                .name = "cux",
                .description = "",
                .metavar = "CUX",
            },
        },
    });

    var args_1 = [_][]const u8{"alpha"};
    var parsed_args_1 = try Parser.parseArgumentSlice(args_1[0..]);
    try testing.expect(parsed_args_1.foo == false);
    try testing.expectEqualStrings(parsed_args_1.bar, "a");
    try testing.expectEqualStrings(parsed_args_1.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_1.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_1.cux, "alpha");

    var args_2 = [_][]const u8{ "-f", "alpha" };
    var parsed_args_2 = try Parser.parseArgumentSlice(args_2[0..]);
    try testing.expect(parsed_args_2.foo == true);
    try testing.expectEqualStrings(parsed_args_2.bar, "a");
    try testing.expectEqualStrings(parsed_args_2.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_2.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_2.cux, "alpha");

    var args_3 = [_][]const u8{ "-b", "x", "alpha" };
    var parsed_args_3 = try Parser.parseArgumentSlice(args_3[0..]);
    try testing.expect(parsed_args_3.foo == false);
    try testing.expectEqualStrings(parsed_args_3.bar, "x");
    try testing.expectEqualStrings(parsed_args_3.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_3.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_3.cux, "alpha");

    var args_4 = [_][]const u8{ "-z", "x", "y", "alpha" };
    var parsed_args_4 = try Parser.parseArgumentSlice(args_4[0..]);
    try testing.expect(parsed_args_4.foo == false);
    try testing.expectEqualStrings(parsed_args_4.bar, "a");
    try testing.expectEqualStrings(parsed_args_4.baz[0], "x");
    try testing.expectEqualStrings(parsed_args_4.baz[1], "y");
    try testing.expectEqualStrings(parsed_args_4.cux, "alpha");

    var args_5 = [_][]const u8{ "-f", "-b", "x", "-z", "y", "z", "alpha" };
    var parsed_args_5 = try Parser.parseArgumentSlice(args_5[0..]);
    try testing.expect(parsed_args_5.foo == true);
    try testing.expectEqualStrings(parsed_args_5.bar, "x");
    try testing.expectEqualStrings(parsed_args_5.baz[0], "y");
    try testing.expectEqualStrings(parsed_args_5.baz[1], "z");
    try testing.expectEqualStrings(parsed_args_5.cux, "alpha");

    var args_6 = [_][]const u8{ "-b", "x", "-f", "-z", "y", "z", "alpha" };
    var parsed_args_6 = try Parser.parseArgumentSlice(args_6[0..]);
    try testing.expect(parsed_args_6.foo == true);
    try testing.expectEqualStrings(parsed_args_6.bar, "x");
    try testing.expectEqualStrings(parsed_args_6.baz[0], "y");
    try testing.expectEqualStrings(parsed_args_6.baz[1], "z");
    try testing.expectEqualStrings(parsed_args_6.cux, "alpha");

    var args_7 = [_][]const u8{ "-z", "x", "y", "-b", "z", "-f", "alpha" };
    var parsed_args_7 = try Parser.parseArgumentSlice(args_7[0..]);
    try testing.expect(parsed_args_7.foo == true);
    try testing.expectEqualStrings(parsed_args_7.bar, "z");
    try testing.expectEqualStrings(parsed_args_7.baz[0], "x");
    try testing.expectEqualStrings(parsed_args_7.baz[1], "y");
    try testing.expectEqualStrings(parsed_args_7.cux, "alpha");
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
