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

pub fn Run_Virtual_Machine(vm: *machine.State, flags: clap.Flags, header: specs.Header) !void {
    // set current PC execution to the header entry point
    vm.program_counter = header.entry_point;

    var quit = false;
    while (!quit) {
        if (vm.program_counter >= vm.original_rom_filesize) {
            std.log.err("Program counter reached outside of original rom file's address space!\n", .{});
            break;
        }
        if (flags.instruction_delay != 0)
            std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(flags.instruction_delay));

        // skip debug metadata bytes
        if (vm.rom[vm.program_counter] == @intFromEnum(specs.Opcode.DEBUG_METADATA_SIGNAL)) {
            const metadata_type: specs.DebugMetadataType = @enumFromInt(vm.rom[vm.program_counter + 1]);
            vm.program_counter += @truncate(try metadata_type.Metadata_Length(vm.rom[vm.program_counter..]));
            continue;
        }

        const opcode_enum: specs.Opcode = @enumFromInt(vm.rom[vm.program_counter]);
        if (flags.log_instruction_opcode) {
            var buf: [utils.buffsize.medium]u8 = undefined;
            std.debug.print("Instruction: {s}\n", .{try opcode_enum.Instruction_String(&buf, vm.rom[vm.program_counter .. vm.program_counter + opcode_enum.Instruction_Byte_Length()])});
        }
        switch (opcode_enum) {
            .PANIC => {
                // useful for debugging when fill_byte is set to zero
                std.log.err("Attempted to execute a null byte!\n", .{});
                break;
            },
            .SYSTEMCALL => {
                // TODO
                std.log.err("Syscall caught! implement me dumbass!\n", .{});
                break;
            },
            .STRIDE_LIT => {
                // get char literal from following ROM byte
                const stride: u8 = vm.rom[vm.program_counter + specs.opcode_bytelen];
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before:\nByte stride = {}\n", .{vm.index_byte_stride});
                }
                vm.index_byte_stride = stride;
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After:\nByte stride = {}\n", .{vm.index_byte_stride});
                }
            },
            .BRK => {
                // graciously exit
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("BRK caught, exiting program.\n\n", .{});
                }
                std.debug.print("Execution complete.\n", .{});
                quit = true;
            },
            .NOP => {
                // NOPs inside the debugger trigger configurable delays
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("NOP caught, triggering manual delay of:\n{}ms\n", .{flags.nop_delay});
                }
                if (flags.nop_delay != 0)
                    std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(flags.nop_delay));
            },
            .CLC => {
                // clear carry flag
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before clearing flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)});
                }
                vm.carry_flag = false;
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After clearing flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)});
                }
            },
            .SEC => {
                // set carry flag
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before setting flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)});
                }
                vm.carry_flag = true;
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After setting flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)});
                }
            },
            .RET => {
                // only instruction capable of returning from subroutines
                try vm.Return_From_Subroutine();
            },
            .LDA_LIT => {
                // get literal from following ROM bytes, then put it in the accumulator
                const literal: u32 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before loading \"{}\":\nA = {}\n", .{ literal, vm.accumulator });
                }
                vm.Load_Value_Into_Reg(literal, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After loading \"{}\":\nA = {}\n", .{ literal, vm.accumulator });
                }
            },
            .LDX_LIT => {
                // get literal from following ROM bytes, then put it in the x index
                const literal: u32 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before loading \"{}\":\nX = {}\n", .{ literal, vm.x_index });
                }
                vm.Load_Value_Into_Reg(literal, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After loading \"{}\":\nX = {}\n", .{ literal, vm.x_index });
                }
            },
            .LDY_LIT => {
                // get literal from following ROM bytes, then put it in the y index
                const literal: u32 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before loading \"{}\":\nY = {}\n", .{ literal, vm.y_index });
                }
                vm.Load_Value_Into_Reg(literal, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After loading \"{}\":\nY = {}\n", .{ literal, vm.y_index });
                }
            },
            .LDA_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the accumulator
                const address: u16 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(&vm.wram, address, u32);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before loading \"{}\" from 0x{X:0>4}:\nA = {}\n", .{ address_contents, address, vm.accumulator });
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After loading \"{}\" from 0x{X:0>4}:\nA = {}\n", .{ address_contents, address, vm.accumulator });
                }
            },
            .LDX_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the x index
                const address: u16 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(&vm.wram, address, u32);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before loading \"{}\" from 0x{X:0>4}:\nX = {}\n", .{ address_contents, address, vm.x_index });
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After loading \"{}\" from 0x{X:0>4}:\nX = {}\n", .{ address_contents, address, vm.x_index });
                }
            },
            .LDY_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the y index
                const address: u16 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(&vm.wram, address, u32);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before loading \"{}\" from 0x{X:0>4}:\nY = {}\n", .{ address_contents, address, vm.y_index });
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After loading \"{}\" from 0x{X:0>4}:\nY = {}\n", .{ address_contents, address, vm.y_index });
                }
            },
            .LDA_X => {
                // a = x
                vm.Transfer_Registers(&vm.accumulator, &vm.x_index);
            },
            .LDA_Y => {
                // a = y
                vm.Transfer_Registers(&vm.accumulator, &vm.y_index);
            },
            .LDX_A => {
                // x = a
                vm.Transfer_Registers(&vm.x_index, &vm.accumulator);
            },
            .LDX_Y => {
                // x = y
                vm.Transfer_Registers(&vm.x_index, &vm.y_index);
            },
            .LDY_A => {
                // y = a
                vm.Transfer_Registers(&vm.y_index, &vm.accumulator);
            },
            .LDY_X => {
                // y = x
                vm.Transfer_Registers(&vm.y_index, &vm.x_index);
            },
            .LDA_ADDR_X => {
                // TODO: indexable address
            },
            .LDA_ADDR_Y => {
                // TODO: indexable address
            },
            .STA_ADDR => {
                // TODO
            },
            .STX_ADDR => {
                // TODO
            },
            .STY_ADDR => {
                // TODO
            },
            .JMP_ADDR => {
                // TODO
            },
            .JSR_ADDR => {
                // TODO
            },
            .CMP_A_X => {
                // TODO
            },
            .CMP_A_Y => {
                // TODO
            },
            .CMP_A_LIT => {
                // TODO
            },
            .CMP_A_ADDR => {
                // TODO
            },
            .CMP_X_A => {
                // TODO
            },
            .CMP_X_Y => {
                // TODO
            },
            .CMP_X_LIT => {
                // TODO
            },
            .CMP_X_ADDR => {
                // TODO
            },
            .CMP_Y_X => {
                // TODO
            },
            .CMP_Y_A => {
                // TODO
            },
            .CMP_Y_LIT => {
                // TODO
            },
            .CMP_Y_ADDR => {
                // TODO
            },
            .BCS_ADDR => {
                // TODO
            },
            .BCC_ADDR => {
                // TODO
            },
            .BEQ_ADDR => {
                // TODO
            },
            .BNE_ADDR => {
                // TODO
            },
            .BMI_ADDR => {
                // TODO
            },
            .BPL_ADDR => {
                // TODO
            },
            .BVS_ADDR => {
                // TODO
            },
            .BVC_ADDR => {
                // TODO
            },
            .ADD_LIT => {
                // TODO
            },
            .ADD_ADDR => {
                // TODO
            },
            .ADD_X => {
                // TODO
            },
            .ADD_Y => {
                // TODO
            },
            .SUB_LIT => {
                // TODO
            },
            .SUB_ADDR => {
                // TODO
            },
            .SUB_X => {
                // TODO
            },
            .SUB_Y => {
                // TODO
            },
            .INC_A => {
                // TODO
            },
            .INC_X => {
                // TODO
            },
            .INC_Y => {
                // TODO
            },
            .INC_ADDR => {
                // TODO
            },
            .DEC_A => {
                // TODO
            },
            .DEC_X => {
                // TODO
            },
            .DEC_Y => {
                // TODO
            },
            .DEC_ADDR => {
                // TODO
            },
            .PUSH_A => {
                // TODO
            },
            .PUSH_X => {
                // TODO
            },
            .PUSH_Y => {
                // TODO
            },
            .POP_A => {
                // TODO
            },
            .POP_X => {
                // TODO
            },
            .POP_Y => {
                // TODO
            },
            .DEBUG_METADATA_SIGNAL => {
                // anything between(inclusive) two metadata signals is
                // completely ignored during execution, it is not to be
                // dealt directly, thus the error.
                std.debug.print("Attempted to execute a debug signal byte!\n", .{});
                quit = true;
            },
        }

        // advance PC pointer
        vm.program_counter += opcode_enum.Instruction_Byte_Length();
    }
}
