const std = @import("std");
const io = std.io;
const fmt = std.fmt;
const eql = std.mem.eql;
const len = std.mem.len;
const ansi = @import("ansi-zig/src/ansi.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const WriteError = std.os.WriteError;
const TypeInfo = std.builtin.TypeInfo;
const StructField = TypeInfo.StructField;
const Declaration = TypeInfo.Declaration;

const reset = ansi.reset;
const bold = ansi.bold;
const red = ansi.fg_red_light;
const blue = ansi.fg_blue_light;
const green = ansi.fg_green_light;
const yellow = ansi.fg_yellow_light;

pub const ParserConfig = struct {
    bin_name: []const u8,
    bin_info: []const u8,
    bin_usage: []const u8,
    bin_version: struct { major: u8, minor: u8, patch: u8 },
    display_error: bool = false,
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

pub fn ArgumentParser(comptime config: ParserConfig, comptime options: []const ArgumentParserOption) type {
    return struct {
        pub const ParserError = error{
            OptionAppearsTwoTimes,
            MissingArgument,
            UnknownArgument,
            NoArgument,
        };

        pub fn displayVersion() WriteError!void {
            // Standard output writer
            const stdout = io.getStdOut().writer();

            // Binary version
            const name = config.bin_name;
            const major = config.bin_version.major;
            const minor = config.bin_version.minor;
            const patch = config.bin_version.patch;
            try stdout.print(bold ++ green ++ "{s}" ++ bold ++ blue ++ " {d}.{d}.{d}\n" ++ reset, .{ name, major, minor, patch });
        }
        pub fn displayUsage() WriteError!void {
            const stdout = io.getStdOut().writer();

            // binary version
            try displayVersion();

            // binary info
            try stdout.writeAll("\n" ++ config.bin_info ++ "\n\n");

            // bin usage
            try stdout.writeAll(bold ++ yellow ++ "USAGE\n" ++ reset);
            try stdout.writeAll("    " ++ config.bin_usage ++ "\n\n");

            // bin options
            try stdout.writeAll(bold ++ yellow ++ "OPTIONS\n" ++ reset);
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

                try stdout.writeAll(bold ++ green ++ "    " ++ short ++ separator ++ long ++ " " ++ metavar ++ reset);
                try stdout.writeAll("\n\t" ++ option.description ++ "\n\n");
            }
        }

        const ParserResult = blk: {
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

        pub fn parse(allocator: *Allocator) (ParserError || WriteError || error{OutOfMemory})!ParserResult {
            // Standard output writer
            const stdout = io.getStdOut().writer();

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

            // Get arguments
            var arguments = std.os.argv;
            if (arguments.len == 1 and options.len > 0) {
                if (comptime config.display_error) {
                    const error_fmt = bold ++ red ++ "Error:" ++ reset;
                    try stdout.writeAll(error_fmt ++ " Executed without arguments\n");
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
                    if (eql(u8, arg, option.short orelse "") or eql(u8, arg, option.long orelse "")) {
                        if (parsing_done[id]) {
                            if (comptime config.display_error) {
                                const long = option.long orelse "";
                                const short = option.short orelse "";
                                const separator = if (option.short != null) (if (option.long != null) ", " else "") else "";

                                const long_fmt = bold ++ green ++ long ++ reset;
                                const short_fmt = bold ++ green ++ short ++ reset;
                                const error_fmt = bold ++ red ++ "Error:" ++ reset;
                                try stdout.writeAll(error_fmt ++ " Option " ++ short_fmt ++ separator ++ long_fmt ++ " appears more than one time\n");
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
                                        try stdout.writeAll(error_fmt ++ " Missing argument for option " ++ short_fmt ++ separator ++ long_fmt ++ "\n");
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
                                        try stdout.writeAll(error_fmt ++ " Missing argument for option " ++ short_fmt ++ separator ++ long_fmt ++ "\n");
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
                    try stdout.print(error_fmt ++ " Unknown argument " ++ arg_fmt ++ "\n", .{arg});
                }

                return error.UnknownArgument;
            }

            return parsed_args;
        }

        pub fn deinit(args: ParserResult) void {
            inline for (options) |option| {
                switch (option.takes) {
                    .Many => @field(args, option.name).deinit(),
                    else => {},
                }
            }
        }
    };
}
