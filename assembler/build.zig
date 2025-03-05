// CAUTION! zig version may be outdated during your compilation
// zig version 0.14.0-dev.2627+6a21d18ad (EXPERIMENTAL DEV BUILD)
// January 2025

const std = @import("std");

const project_name = "assembler";
const source_directory = "./src/";
const main_filepath = source_directory ++ "main.zig";
const tests_filepath = source_directory ++ "tests.zig";

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = project_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(main_filepath),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
        // EXPERIMENTAL OPTION!
        // new zig 0.14.0 feature that supposedly drastically reduces
        // compilation times by using their own x86 backend.
        .use_llvm = false,
    });
    b.installArtifact(exe);

    // formatting
    const format_options = std.Build.Step.Fmt.Options{
        .paths = &.{source_directory}, //where to look for source files
        .check = false, //format files in-place
    };
    const performStep_format = b.addFmt(format_options);
    b.default_step.dependOn(&performStep_format.step);

    // unit testing
    const added_tests = b.addTest(.{ .root_source_file = b.path(tests_filepath) });
    const performStep_test = b.addRunArtifact(added_tests);
    b.default_step.dependOn(&performStep_test.step);

    // (optional step) run executable
    var run_step = b.step("run", "Run the executable");
    const performStep_run = b.addRunArtifact(exe);
    if (b.args) |args|
        performStep_run.addArgs(args);
    run_step.dependOn(&performStep_run.step);
}
