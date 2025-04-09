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

pub fn Run_Virtual_Machine(vm: *machine.VirtualMachine, flags: clap.Flags, header: specs.Header) !void {
    // set current PC execution to the header entry point
    vm.program_counter = header.entry_point;

    var quit = false;
    while (!quit) {
        if (vm.program_counter >= vm.original_rom_filesize) {
            warn.Error_Message("Program counter (PC = 0x{}) reached outside of original rom file's (ROM filesize = 0x{}) address space!", .{ vm.program_counter, vm.original_rom_filesize });
            break;
        }

        if (flags.instruction_delay != 0)
            std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(flags.instruction_delay));

        const opcode_enum: specs.Opcode = @enumFromInt(vm.rom[vm.program_counter]);
        if (flags.log_instruction_opcode) {
            var buf: [utils.buffsize.medium]u8 = undefined;
            std.debug.print("Instruction: {s}\n", .{try opcode_enum.Instruction_String(&buf, vm.rom[vm.program_counter .. vm.program_counter + opcode_enum.Instruction_Byte_Length()])});
        }
        switch (opcode_enum) {
            .PANIC => {
                // useful for debugging when fill_byte is set to zero
                warn.Error_Message("Attempted to execute a null byte!", .{});
                break;
            },
            .SYSTEMCALL => {
                // TODO
                warn.Error_Message("Syscall caught! implement me dumbass!", .{});
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
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
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
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
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
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
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
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
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
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
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
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
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
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before transfering X to A:\nX = {}, A = {}\n", .{ vm.x_index, vm.accumulator });
                }
                vm.Transfer_Registers(&vm.accumulator, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After transfering X to A:\nX = {}, A = {}\n", .{ vm.x_index, vm.accumulator });
                }
            },
            .LDA_Y => {
                // a = y
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before transfering Y to A:\nY = {}, A = {}\n", .{ vm.y_index, vm.accumulator });
                }
                vm.Transfer_Registers(&vm.accumulator, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After transfering Y to A:\nY = {}, A = {}\n", .{ vm.y_index, vm.accumulator });
                }
            },
            .LDX_A => {
                // x = a
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before transfering A to X:\nA = {}, X = {}\n", .{ vm.accumulator, vm.x_index });
                }
                vm.Transfer_Registers(&vm.x_index, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After transfering A to X:\nA = {}, X = {}\n", .{ vm.accumulator, vm.x_index });
                }
            },
            .LDX_Y => {
                // x = y
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before transfering Y to X:\nY = {}, X = {}\n", .{ vm.y_index, vm.x_index });
                }
                vm.Transfer_Registers(&vm.y_index, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After transfering Y to X:\nY = {}, X = {}\n", .{ vm.y_index, vm.x_index });
                }
            },
            .LDY_A => {
                // y = a
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before transfering A to Y:\nA = {}, Y = {}\n", .{ vm.accumulator, vm.y_index });
                }
                vm.Transfer_Registers(&vm.y_index, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After transfering A to Y:\nA = {}, Y = {}\n", .{ vm.accumulator, vm.y_index });
                }
            },
            .LDY_X => {
                // y = x
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Before transfering X to Y:\nX = {}, Y = {}\n", .{ vm.x_index, vm.y_index });
                }
                vm.Transfer_Registers(&vm.y_index, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("After transfering X to Y:\nX = {}, Y = {}\n", .{ vm.x_index, vm.y_index });
                }
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
                try vm.Push_To_Stack(@TypeOf(vm.accumulator), vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Pushed the accumulator value 0x{X:0>8} to the stack\n", .{vm.accumulator});
                }
            },
            .PUSH_X => {
                try vm.Push_To_Stack(@TypeOf(vm.x_index), vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Pushed the X index value 0x{X:0>8} to the stack\n", .{vm.x_index});
                }
            },
            .PUSH_Y => {
                try vm.Push_To_Stack(@TypeOf(vm.y_index), vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Pushed the Y index value 0x{X:0>8} to the stack\n", .{vm.y_index});
                }
            },
            .POP_A => {
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator});
                }
                vm.accumulator = try vm.Pop_From_Stack(@TypeOf(vm.accumulator));
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator});
                }
            },
            .POP_X => {
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator});
                }
                vm.x_index = try vm.Pop_From_Stack(@TypeOf(vm.x_index));
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator});
                }
            },
            .POP_Y => {
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator});
                }
                vm.y_index = try vm.Pop_From_Stack(@TypeOf(vm.y_index));
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator});
                }
            },
            .DEBUG_METADATA_SIGNAL => {
                const metadata_type: specs.DebugMetadataType = @enumFromInt(vm.rom[vm.program_counter + 1]);
                const skip_count: usize = try metadata_type.Metadata_Length(vm.rom[vm.program_counter..]);
                if (flags.log_instruction_sideeffects) {
                    std.debug.print("Skipping {} bytes of ROM metadata\n", .{skip_count});
                }
                vm.program_counter += @truncate(skip_count);
                continue;
            },
        }

        // advance PC pointer
        vm.program_counter += opcode_enum.Instruction_Byte_Length();
    }
}
