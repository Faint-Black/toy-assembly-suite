const std = @import("std");
const builtin = @import("builtin");

const project_name = "assembler";
const source_directory = "./src/";
const main_filepath = source_directory ++ "main.zig";
const tests_filepath = source_directory ++ "tests.zig";

pub fn build(b: *std.Build) void {
    // ensure Zig version compatibility
    const current_version = builtin.zig_version;
    const minimum_version = std.SemanticVersion{
        .major = 0,
        .minor = 14,
        .patch = 0,
        .build = null,
        .pre = null,
    };
    switch (std.SemanticVersion.order(current_version, minimum_version)) {
        .lt => @panic("Zig 0.14.0 or higher is required for compilation!"),
        .eq => {},
        .gt => {},
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = project_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(main_filepath),
            .target = target,
            .optimize = optimize,
        }),
        // New Zig 0.14.0 feature that drastically reduces
        //compilation times by using their own x86 backend.
        // Only used in debug mode since LLVM optimizations are still
        //much more efficient and faster for release versions.
        .use_llvm = if (optimize == .Debug) false else true,
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
