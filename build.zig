const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("argparse-zig", "src/argparse.zig");
    lib.addPackagePath("ansi-zig", "ext/ansi-zig/src/ansi.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/argparse.zig");
    main_tests.addPackagePath("ansi-zig", "ext/ansi-zig/src/ansi.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
