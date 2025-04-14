//=============================================================//
//                                                             //
//                           MAIN                              //
//                                                             //
//   Licensed under GNU General Public License version 3.      //
//                                                             //
//=============================================================//

const std = @import("std");
const builtin = @import("builtin");
const machine = @import("shared").machine;
const specs = @import("shared").specifications;
const emulator = @import("execution.zig");
const disassembler = @import("disassemble.zig");
const clap = @import("clap.zig");

const stdout = std.io.getStdOut().writer();

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
        stdout.print(clap.Flags.Help_String(), .{}) catch unreachable;
        return;
    }
    if (flags.version == true) {
        stdout.print(clap.Flags.Version_String(), .{}) catch unreachable;
        return;
    }
    if (flags.run_mode == false and flags.disassemble_mode == false) {
        stdout.print("Must specify a debugger mode! use the -h flag for more info.\n", .{}) catch unreachable;
        return;
    }

    // load and init virtual machine
    var vm = machine.VirtualMachine.Init(flags.input_rom_filename, null);
    const rom_header = specs.Header.Parse_From_Byte_Array(vm.rom[0..16].*);
    if (rom_header.magic_number != specs.Header.required_magic_number) {
        stdout.print("Wrong ROM magic number! expected 0x{X:0>2}, got 0x{X:0>2}\n", .{ specs.Header.required_magic_number, rom_header.magic_number }) catch unreachable;
        return error.BadMagicNumber;
    }
    if (rom_header.language_version != specs.current_assembly_version) {
        stdout.print("Outdated ROM! current version is {}, input rom is in version {}\n", .{ specs.current_assembly_version, rom_header.language_version }) catch unreachable;
        return error.OutdatedROM;
    }
    if (flags.log_header_info) {
        stdout.print("HEADER INFO:\n", .{}) catch unreachable;
        stdout.print("magic number: {}\n", .{rom_header.magic_number}) catch unreachable;
        stdout.print("assembly version: {}\n", .{rom_header.language_version}) catch unreachable;
        stdout.print("entry point address: 0x{X:0>4}\n", .{rom_header.entry_point}) catch unreachable;
        stdout.print("rom debug enable: {}\n\n", .{rom_header.debug_mode}) catch unreachable;
    }

    // print disassembly then exit
    if (flags.disassemble_mode) {
        try disassembler.Disassemble_Rom(global_allocator, &vm.rom, vm.original_rom_filesize, rom_header);
        return;
    }
    // begin execution then exit
    if (flags.run_mode) {
        try emulator.Run_Virtual_Machine(&vm, flags, rom_header);
        return;
    }
}
