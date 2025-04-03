const std = @import("std");
const builtin = @import("builtin");
const machine = @import("shared").machine;
const specs = @import("shared").specifications;
const emulator = @import("execution.zig");
const disassembler = @import("disassemble.zig");
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
    if (flags.run_mode == false and flags.disassemble_mode == false) {
        try std.io.getStdOut().writer().print("Must specify a debugger mode! use the -h flag for more info.\n", .{});
        return;
    }

    // load and init virtual machine
    var vm = machine.State.Init(flags.input_rom_filename, null);
    const rom_header = specs.Header.Parse_From_Byte_Array(vm.rom[0..16].*);
    if (rom_header.magic_number != specs.rom_magic_number) {
        std.debug.print("Wrong ROM magic number! expected 0x{X:0>2}, got 0x{X:0>2}\n", .{ specs.rom_magic_number, rom_header.magic_number });
        return error.BadMagicNumber;
    }
    if (rom_header.language_version != specs.current_assembly_version) {
        std.debug.print("Outdated ROM! current version is {}, input rom is in version {}\n", .{ specs.current_assembly_version, rom_header.language_version });
        return error.OutdatedROM;
    }
    if (flags.log_header_info) {
        std.debug.print("HEADER INFO:\n", .{});
        std.debug.print("magic number: {}\n", .{rom_header.magic_number});
        std.debug.print("assembly version: {}\n", .{rom_header.language_version});
        std.debug.print("entry point address: 0x{X:0>4}\n", .{rom_header.entry_point});
        std.debug.print("rom debug enable: {}\n\n", .{rom_header.debug_mode});
    }

    // print disassembly then exit
    if (flags.disassemble_mode) {
        try disassembler.Disassemble_Rom(&vm.rom, vm.original_rom_filesize, rom_header);
        return;
    }
    // begin execution then exit
    if (flags.run_mode) {
        try emulator.Run_Virtual_Machine(&vm, flags, rom_header);
        return;
    }
}
