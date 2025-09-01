const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    Ensure_Zig_Version() catch @panic("Zig 0.15.1 is required for compilation!");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared_module = b.addModule("shared", .{
        .root_source_file = b.path("src/shared/src/shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shared_module_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shared/src/shared.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const performStep_shared_test = b.addRunArtifact(shared_module_tests);
    b.default_step.dependOn(&performStep_shared_test.step);

    inline for ([_][]const u8{
        "assembler",
        "debugger",
        "disassembler",
        "runner",
    }) |project_name| {
        Add_Executable_Module(b, project_name, target, optimize, shared_module);
    }

    const format_options = std.Build.Step.Fmt.Options{ .paths = &.{"src/"} };
    const performStep_format = b.addFmt(format_options);
    b.default_step.dependOn(&performStep_format.step);
}

/// Automate multi-project binaries compilation
pub fn Add_Executable_Module(
    b: *std.Build,
    comptime name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shared: *std.Build.Module,
) void {
    const main_filepath = "src/" ++ name ++ "/src/main.zig";
    const tests_filepath = "src/" ++ name ++ "/src/tests.zig";

    // add executable
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(main_filepath),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("shared", shared);

    b.installArtifact(exe);

    // unit testing
    const added_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(tests_filepath),
            .target = target,
            .optimize = .Debug,
        }),
    });
    added_tests.root_module.addImport("shared", shared);
    const performStep_test = b.addRunArtifact(added_tests);
    b.default_step.dependOn(&performStep_test.step);

    // run executable
    var run_step = b.step("run_" ++ name, "Run the " ++ name ++ " executable");
    const performStep_run = b.addRunArtifact(exe);
    if (b.args) |args|
        performStep_run.addArgs(args);
    run_step.dependOn(&performStep_run.step);
}

/// Requires exactly Zig 0.15.1
pub fn Ensure_Zig_Version() !void {
    const current_version = builtin.zig_version;
    const required_version = std.SemanticVersion{
        .major = 0,
        .minor = 15,
        .patch = 1,
        .build = null,
        .pre = null,
    };
    switch (std.SemanticVersion.order(current_version, required_version)) {
        .lt => return error.OutdatedVersion,
        .eq => {},
        .gt => return error.FutureDatedVersion,
    }
}
