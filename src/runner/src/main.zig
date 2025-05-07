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
const clap = @import("clap.zig");
const warn = @import("shared").warn;
const coderun = @import("coderun.zig");

const stdout = std.io.getStdOut().writer();

pub fn main() void {
    // command-line flags, filenames and filepath specifications
    const flags = clap.Flags.Parse(std.heap.smp_allocator) catch {
        warn.Fatal_Error_Message("failed to parse flags.", .{});
        return;
    };
    defer flags.Deinit();
    if (flags.help == true) {
        stdout.print(clap.Flags.Help_String(), .{}) catch unreachable;
        return;
    }
    if (flags.version == true) {
        stdout.print(clap.Flags.Version_String(), .{}) catch unreachable;
        return;
    }
    if (std.mem.eql(u8, flags.input_rom_filename.?, "stdin")) {
        warn.Fatal_Error_Message("input through stdin input not implemented yet.", .{});
        return;
    }

    // init virtual machine and header
    var vm = machine.VirtualMachine.Init(flags.input_rom_filename, null) catch |err| {
        machine.Output_Error_Message(err);
        return;
    };
    const rom_header = specs.Header.Parse_From_Byte_Array(vm.rom[0..16].*);
    vm.program_counter = rom_header.entry_point;
    if (rom_header.magic_number != specs.Header.required_magic_number) {
        warn.Fatal_Error_Message("wrong ROM magic number! expected 0x{X:0>2}, got 0x{X:0>2}\n", .{ specs.Header.required_magic_number, rom_header.magic_number });
        return;
    }
    if (rom_header.language_version != specs.current_assembly_version) {
        warn.Fatal_Error_Message("outdated ROM! current version is {}, input rom is in version {}\n", .{ specs.current_assembly_version, rom_header.language_version });
        return;
    }

    // run VM loop
    var quit = false;
    while (!quit) {
        const opcode_enum: specs.Opcode = @enumFromInt(vm.rom[vm.program_counter]);
        quit = coderun.Run_Instruction(opcode_enum, &vm);
    }
}
