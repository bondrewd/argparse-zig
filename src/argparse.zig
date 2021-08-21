// Libraries
const std = @import("std");
const ansi = @import("ansi-zig/src/ansi.zig");

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
const reset = ansi.reset;
const bold = ansi.bold_on;
const red = ansi.fg_light_red;
const blue = ansi.fg_light_blue;
const green = ansi.fg_light_green;
const yellow = ansi.fg_light_yellow;

pub const ParserConfig = struct {
    bin_name: []const u8,
    bin_info: []const u8,
    bin_usage: []const u8,
    bin_version: struct { major: u8, minor: u8, patch: u8 },
    display_error: bool = false,
    default_version: bool = true,
    default_help: bool = true,
};

pub const ArgumentParserOption = struct {
    name: []const u8,
    long: ?[]const u8 = null,
    short: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    description: []const u8,
    argument_type: type = bool,
    takes: enum { None, One, Many } = .None,
};

pub fn ArgumentParser(comptime config: ParserConfig, comptime options: anytype) type {
    return struct {
        pub const ParserError = error{
            OptionAppearsTwoTimes,
            MissingArgument,
            UnknownArgument,
            NoArgument,
        };

        pub fn displayVersionWriter(writer: anytype) !void {
            // Binary version
            const name = config.bin_name;
            const major = config.bin_version.major;
            const minor = config.bin_version.minor;
            const patch = config.bin_version.patch;
            try writer.print(bold ++ green ++ "{s}" ++ bold ++ blue ++ " {d}.{d}.{d}\n" ++ reset, .{ name, major, minor, patch });
        }

        pub fn displayVersion() !void {
            // Standard output writer
            const stdout = io.getStdOut().writer();

            // Binary version
            try printVersionWriter(stdout);
        }

        pub fn displayInfoWriter(writer: anytype) !void {
            // Binary info
            try writer.writeAll(config.bin_info ++ "\n");
        }

        pub fn displayInfo() !void {
            // Standard output writer
            const stdout = io.getStdOut().writer();

            // Binary info
            try displayInfoWriter(stdout);
        }

        pub fn displayUsageWriter(writer: anytype) !void {
            // Bin usage
            try writer.writeAll(bold ++ yellow ++ "USAGE\n" ++ reset);
            try writer.writeAll("    " ++ config.bin_usage ++ "\n");
        }

        pub fn displayUsage() !void {
            // Standard output writer
            const stdout = io.getStdOut().writer();

            // Bin usage
            try displayUsageWriter(stdout);
        }

        pub fn displayOptionsWriter(writer: anytype) !void {
            // Bin options
            try writer.writeAll(bold ++ yellow ++ "OPTIONS\n" ++ reset);
            inline for (options) |option| {
                const long = option.long orelse "";
                const short = option.short orelse "  ";
                const metavar = option.metavar orelse switch (option.takes) {
                    .None => "",
                    .One => "<ARG>",
                    .Many => "<ARG> [ARG...]",
                };
                const separator = if (option.short != null) (if (option.long != null) ", " else "") else "  ";
                if (option.short == null and option.long == null) @compileError("Option must have defined at least short or long");

                try writer.writeAll(bold ++ green ++ "    " ++ short ++ separator ++ long ++ " " ++ metavar ++ reset);
                try writer.writeAll("\n\t" ++ option.description ++ "\n\n");
            }

            if (config.default_version) {
                try writer.writeAll(bold ++ green ++ "    -v, --version" ++ reset);
                try writer.writeAll("\n\tPrint version and exit\n\n");
            }

            if (config.default_help) {
                try writer.writeAll(bold ++ green ++ "    -h, --help" ++ reset);
                try writer.writeAll("\n\tDisplay this and exit\n\n");
            }
        }

        pub fn displayOptions() !void {
            // Standard output writer
            const stdout = io.getStdOut().writer();

            // Bin options
            try displayOptionsWriter(stdout);
        }

        pub const ParserResult = blk: {
            // Struct fields
            var fields: [options.len]StructField = undefined;
            inline for (options) |option, i| {
                fields[i] = .{
                    .name = option.name,
                    .field_type = switch (option.takes) {
                        .None => bool,
                        .One => ?option.argument_type,
                        .Many => ArrayList(option.argument_type),
                    },
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(option.argument_type),
                };
            }

            // Struct declarations
            var decls: [0]Declaration = .{};

            break :blk @Type(TypeInfo{ .Struct = .{
                .layout = .Auto,
                .fields = &fields,
                .decls = &decls,
                .is_tuple = false,
            } });
        };

        pub fn parseArgumentsWriter(allocator: *Allocator, arguments: [][*:0]u8, comptime writer: anytype) !ParserResult {
            // Initialize parser result
            var parsed_args: ParserResult = undefined;
            inline for (options) |option| {
                @field(parsed_args, option.name) = switch (option.takes) {
                    .None => false,
                    .One => null,
                    .Many => ArrayList(option.argument_type).init(allocator),
                };
            }

            // Initialize argument parser flags
            var parsing_done = [_]bool{false} ** options.len;

            // Check arguments
            if (arguments.len == 1 and options.len > 0) {
                if (comptime config.display_error) {
                    const error_fmt = bold ++ red ++ "Error:" ++ reset;
                    try writer.writeAll(error_fmt ++ " Executed without arguments\n\n");
                    try displayUsage();
                    try writer.writeAll("\n");
                    try displayOptions();
                }

                return error.NoArgument;
            }

            // Parse arguments
            var i: usize = 1;
            argument_loop: while (i < arguments.len) : (i += 1) {
                // Get slice from null terminated string
                const arg = arguments[i][0..len(arguments[i])];

                // Iterate over all the options
                inline for (options) |option, id| {
                    if (config.default_version) {
                        if (eql(u8, arg, "-v") or eql(u8, arg, "--version")) {
                            try displayVersion();
                            std.os.exit(0);
                        }
                    }

                    if (config.default_help) {
                        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
                            try displayOptions();
                            std.os.exit(0);
                        }
                    }

                    if (eql(u8, arg, option.short orelse "") or eql(u8, arg, option.long orelse "")) {
                        if (parsing_done[id]) {
                            if (comptime config.display_error) {
                                const long = option.long orelse "";
                                const short = option.short orelse "";
                                const separator = if (option.short != null) (if (option.long != null) ", " else "") else "";

                                const long_fmt = bold ++ green ++ long ++ reset;
                                const short_fmt = bold ++ green ++ short ++ reset;
                                const error_fmt = bold ++ red ++ "Error:" ++ reset;
                                try writer.writeAll(error_fmt ++ " Option " ++ short_fmt ++ separator ++ long_fmt ++ " appears more than one time\n");
                            }

                            return error.OptionAppearsTwoTimes;
                        }
                        switch (option.takes) {
                            .None => @field(parsed_args, option.name) = true,
                            .One => {
                                if (arguments.len <= i + 1) {
                                    if (comptime config.display_error) {
                                        const long = option.long orelse "";
                                        const short = option.short orelse "";
                                        const separator = if (option.short != null) (if (option.long != null) ", " else "") else "";

                                        const long_fmt = bold ++ green ++ long ++ reset;
                                        const short_fmt = bold ++ green ++ short ++ reset;
                                        const error_fmt = bold ++ red ++ "Error:" ++ reset;
                                        try writer.writeAll(error_fmt ++ " Missing argument for option " ++ short_fmt ++ separator ++ long_fmt ++ "\n");
                                    }

                                    return error.MissingArgument;
                                }
                                const next_arg = arguments[i + 1][0..len(arguments[i + 1])];
                                switch (@typeInfo(option.argument_type)) {
                                    .Int => @field(parsed_args, option.name) = try fmt.parseInt(option.argument_type, next_arg),
                                    .Float => @field(parsed_args, option.name) = try fmt.parseFloat(option.argument_type, next_arg),
                                    .Pointer => @field(parsed_args, option.name) = next_arg,
                                    else => unreachable,
                                }
                                i += 1;
                            },
                            .Many => {
                                if (arguments.len <= i + 1) {
                                    if (comptime config.display_error) {
                                        const long = option.long orelse "";
                                        const short = option.short orelse "";
                                        const separator = if (option.short != null) (if (option.long != null) ", " else "") else "";

                                        const long_fmt = bold ++ green ++ long ++ reset;
                                        const short_fmt = bold ++ green ++ short ++ reset;
                                        const error_fmt = bold ++ red ++ "Error:" ++ reset;
                                        try writer.writeAll(error_fmt ++ " Missing argument for option " ++ short_fmt ++ separator ++ long_fmt ++ "\n");
                                    }

                                    return error.MissingArgument;
                                }
                                var j: usize = 1;
                                search_loop: while (arguments.len > i + j) : (j += 1) {
                                    const next_arg = arguments[i + j][0..len(arguments[i + j])];
                                    inline for (options) |opt| {
                                        if (eql(u8, next_arg, opt.short orelse "") or eql(u8, next_arg, opt.long orelse "")) break :search_loop;
                                    }
                                    switch (@typeInfo(option.argument_type)) {
                                        .Int => try @field(parsed_args, option.name).append(try fmt.parseInt(option.argument_type, next_arg)),
                                        .Float => try @field(parsed_args, option.name).append(try fmt.parseFloat(option.argument_type, next_arg)),
                                        .Pointer => try @field(parsed_args, option.name).append(next_arg),
                                        else => unreachable,
                                    }
                                }
                                i = i + j - 1;
                            },
                        }
                        parsing_done[id] = true;
                        continue :argument_loop;
                    }
                }

                if (comptime config.display_error) {
                    const arg_fmt = bold ++ green ++ "{s}" ++ reset;
                    const error_fmt = bold ++ red ++ "Error:" ++ reset;
                    try writer.print(error_fmt ++ " Unknown argument " ++ arg_fmt ++ "\n", .{arg});
                }

                return error.UnknownArgument;
            }

            return parsed_args;
        }

        pub fn parse(allocator: *Allocator) !ParserResult {
            // Get arguments
            const arguments = std.os.argv;

            // Standard output writer
            const stdout = io.getStdOut().writer();

            // Parse arguments
            return try parseArgumentsWriter(allocator, arguments, stdout);
        }

        pub fn deinitArgs(args: ParserResult) void {
            inline for (options) |option| {
                switch (option.takes) {
                    .Many => @field(args, option.name).deinit(),
                    else => {},
                }
            }
        }
    };
}

test "Argparse displayVersionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "Foo",
        .bin_info = "",
        .bin_usage = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, .{});

    try Parser.displayVersionWriter(w);
    const str = bold ++ green ++ "Foo" ++ bold ++ blue ++ " 1.2.3\n" ++ reset;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayInfoWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "Foo",
        .bin_usage = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, .{});

    try Parser.displayInfoWriter(w);
    const str = "Foo\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayUsageWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_usage = "Foo",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, .{});

    try Parser.displayUsageWriter(w);
    const str = bold ++ yellow ++ "USAGE\n" ++ reset ++ "    Foo" ++ "\n";
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionsWriter 1" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_usage = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, .{});

    try Parser.displayOptionsWriter(w);
    const line1 = bold ++ yellow ++ "OPTIONS\n" ++ reset;
    const line2 = bold ++ green ++ "    -v, --version" ++ reset;
    const line3 = "\n\tPrint version and exit\n\n";
    const line4 = bold ++ green ++ "    -h, --help" ++ reset;
    const line5 = "\n\tDisplay this and exit\n\n";
    const str = line1 ++ line2 ++ line3 ++ line4 ++ line5;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionsWriter 2" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_usage = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
        .default_version = false,
        .default_help = false,
    }, [_]ArgumentParserOption{
        .{
            .name = "foo",
            .short = "-f",
            .description = "bar",
        },
    });

    try Parser.displayOptionsWriter(w);
    const line1 = bold ++ yellow ++ "OPTIONS\n" ++ reset;
    const line2 = bold ++ green ++ "    -f" ++ " " ++ reset;
    const line3 = "\n\t" ++ "bar" ++ "\n\n";
    const str = line1 ++ line2 ++ line3;
    try testing.expectEqualStrings(list.items, str);
}

test "Argparse displayOptionsWriter 3" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const w = list.writer();

    const Parser = ArgumentParser(.{
        .bin_name = "",
        .bin_info = "",
        .bin_usage = "",
        .bin_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, [_]ArgumentParserOption{
        .{
            .name = "foo",
            .short = "-f",
            .description = "bar",
        },
    });

    try Parser.displayOptionsWriter(w);
    const line1 = bold ++ yellow ++ "OPTIONS\n" ++ reset;
    const line2 = bold ++ green ++ "    -f" ++ " " ++ reset;
    const line3 = "\n\t" ++ "bar" ++ "\n\n";
    const line4 = bold ++ green ++ "    -v, --version" ++ reset;
    const line5 = "\n\tPrint version and exit\n\n";
    const line6 = bold ++ green ++ "    -h, --help" ++ reset;
    const line7 = "\n\tDisplay this and exit\n\n";
    const str = line1 ++ line2 ++ line3 ++ line4 ++ line5 ++ line6 ++ line7;
    try testing.expectEqualStrings(list.items, str);
}
