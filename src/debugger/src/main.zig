const std = @import("std");
const builtin = @import("builtin");
const machine = @import("shared").machine;
const emulator = @import("execution.zig");
const clap = @import("clap.zig");

pub fn main() !void {
    // use DebugAllocator on debug mode
    // use SmpAllocator on release mode
    var debug_struct_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_struct_allocator.deinit();
    const global_allocator: std.mem.Allocator = if (builtin.mode == .Debug) debug_struct_allocator.allocator() else std.heap.smp_allocator;

    // command-line flags, filenames and filepath specifications
    const flags = try clap.Flags.Parse(global_allocator);
    defer flags.Deinit();
    if (flags.help == true) {
        try std.io.getStdOut().writer().print(clap.Flags.Help_String(), .{});
        return;
    }
    if (flags.version == true) {
        try std.io.getStdOut().writer().print(clap.Flags.Version_String(), .{});
        return;
    }

    var vm = machine.State.Init(flags.input_rom_filename, null);
    try emulator.Run_Virtual_Machine(&vm, flags);
}
