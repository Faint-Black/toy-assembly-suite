//=============================================================//
//                                                             //
//                         EXECUTION                           //
//                                                             //
//   Responsible for the run vm debugger function, which is    //
//  the same as a normal vm execution, except with extra user  //
//  features. Primarily focused on logging the effect of each  //
//  instructions on the virtual machine.                       //
//                                                             //
//=============================================================//

const std = @import("std");
const clap = @import("clap.zig");
const specs = @import("shared").specifications;
const utils = @import("shared").utils;
const machine = @import("shared").machine;
const warn = @import("shared").warn;
const coderun = @import("coderun.zig");

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

pub fn Run_Virtual_Machine(vm: *machine.VirtualMachine, flags: clap.Flags, header: specs.Header) !void {
    // set current PC execution to the entry point
    vm.program_counter = header.entry_point;

    var quit = false;
    while (!quit) {
        if (vm.program_counter >= vm.original_rom_filesize) {
            warn.Error_Message("Program counter (PC = 0x{}) reached outside of original rom file's (ROM filesize = 0x{}) address space!", .{ vm.program_counter, vm.original_rom_filesize });
            break;
        }

        if (flags.instruction_delay != 0 and flags.step_by_step == false)
            std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(flags.instruction_delay));

        if (flags.step_by_step) {
            var buf: [32]u8 = undefined;
            const slice_size = try stdin.read(&buf);
            const str = buf[0..slice_size];
            if (std.mem.eql(u8, str, "q\n")) {
                stdout.print("'q' pressed, exiting execution early.\n", .{}) catch unreachable;
                return;
            }
        }

        // get instruction enum from ROM bytes
        const opcode_enum: specs.Opcode = @enumFromInt(vm.rom[vm.program_counter]);
        if (flags.log_instruction_opcode) {
            var buf: [utils.buffsize.medium]u8 = undefined;
            const instruction_str = try opcode_enum.Instruction_String(&buf, vm.rom[vm.program_counter .. vm.program_counter + opcode_enum.Instruction_Byte_Length()]);
            stdout.print("Instruction: {s}\n", .{instruction_str}) catch unreachable;
        }

        // run instruction
        quit = try coderun.Run_Instruction(opcode_enum, vm, flags);
        vm.program_counter += opcode_enum.Instruction_Byte_Length();
    }
}
