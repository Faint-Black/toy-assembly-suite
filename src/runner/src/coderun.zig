//=============================================================//
//                                                             //
//                      BYTECODE RUNNER                        //
//                                                             //
//   Responsible for interpreting the instruction opcode.      //
//                                                             //
//=============================================================//

const std = @import("std");
const clap = @import("clap.zig");
const specs = @import("shared").specifications;
const utils = @import("shared").utils;
const machine = @import("shared").machine;
const warn = @import("shared").warn;

const stdout = std.io.getStdOut().writer();

/// return value -> bool should_quit
pub fn Run_Instruction(op: specs.Opcode, vm: *machine.VirtualMachine) bool {
    // "macros"
    const QUIT = true;
    const CONTINUE = false;

    // do not increment PC after a jump instruction
    var pc_increment: u8 = op.Instruction_Byte_Length();
    switch (op) {
        .PANIC => {
            warn.Fatal_Error_Message("Attempted to execute a null byte!", .{});
            return QUIT;
        },
        // perform a system call
        .SYSTEMCALL => {
            // no logging to not pollute the console output
            vm.Syscall() catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // set byte stride for indexing instructions
        .STRIDE_LIT => {
            const stride: u8 = vm.rom[vm.program_counter + specs.bytelen.opcode];
            vm.index_byte_stride = stride;
        },
        // graciously exit
        .BRK => {
            return QUIT;
        },
        // NOPs inside the runner trigger a 0.2s delay
        .NOP => {
            std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(200));
        },
        // clear carry flag
        .CLC => {
            vm.Clear_Carry_Flag();
        },
        // set carry flag
        .SEC => {
            vm.Set_Carry_Flag();
        },
        // only instruction capable of returning from subroutines
        .RET => {
            vm.Return_From_Subroutine() catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
            pc_increment = 0;
        },
        // load literal into accumulator
        .LDA_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.Load_Value_Into_Reg(literal, &vm.accumulator);
        },
        // load literal into X index
        .LDX_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.Load_Value_Into_Reg(literal, &vm.x_index);
        },
        // load literal into Y index
        .LDY_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.Load_Value_Into_Reg(literal, &vm.y_index);
        },
        // load address contents into accumulator
        .LDA_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
        },
        // load address contents into X index
        .LDX_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.Load_Value_Into_Reg(address_contents, &vm.x_index);
        },
        // load address contents into Y index
        .LDY_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.Load_Value_Into_Reg(address_contents, &vm.y_index);
        },
        // a = x
        .LDA_X => {
            vm.Transfer_Registers(&vm.accumulator, &vm.x_index);
        },
        // a = y
        .LDA_Y => {
            vm.Transfer_Registers(&vm.accumulator, &vm.y_index);
        },
        // x = a
        .LDX_A => {
            vm.Transfer_Registers(&vm.x_index, &vm.accumulator);
        },
        // x = y
        .LDX_Y => {
            vm.Transfer_Registers(&vm.y_index, &vm.y_index);
        },
        // y = a
        .LDY_A => {
            vm.Transfer_Registers(&vm.y_index, &vm.accumulator);
        },
        // y = x
        .LDY_X => {
            vm.Transfer_Registers(&vm.y_index, &vm.x_index);
        },
        // accumulator = u32 dereference of (address_ptr + (X * stride))
        .LDA_ADDR_X => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const index_addr: u16 = address +% ((@as(u16, @truncate(vm.x_index))) *% vm.index_byte_stride);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, index_addr, u32);
            vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
        },
        // accumulator = u32 dereference of (address_ptr + (Y * stride))
        .LDA_ADDR_Y => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const index_addr: u16 = address +% ((@as(u16, @truncate(vm.y_index))) *% vm.index_byte_stride);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, index_addr, u32);
            vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
        },
        // load address as a literal number, then store it in the accumulator
        .LEA_ADDR => {
            const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            vm.accumulator = @intCast(address_literal);
        },
        // load address as a literal number, then store it in the X index
        .LEX_ADDR => {
            const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            vm.x_index = @intCast(address_literal);
        },
        // load address as a literal number, then store it in the Y index
        .LEY_ADDR => {
            const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            vm.y_index = @intCast(address_literal);
        },
        // store value of accumulator into an address
        .STA_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.accumulator), vm.accumulator);
        },
        // store value of X index into an address
        .STX_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.x_index), vm.x_index);
        },
        // store value of Y index into an address
        .STY_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.y_index), vm.y_index);
        },
        // go to ROM address
        .JMP_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            vm.Jump_To_Address(address);
            pc_increment = 0;
        },
        // go to ROM address and save its position on the stack
        .JSR_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            vm.Jump_To_Subroutine(address) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
            pc_increment = 0;
        },
        // modify flags by subtracting the accumulator with the X index
        .CMP_A_X => {
            vm.Compare(vm.accumulator, vm.x_index);
        },
        // modify flags by subtracting the accumulator with the Y index
        .CMP_A_Y => {
            vm.Compare(vm.accumulator, vm.y_index);
        },
        // modify flags by subtracting the accumulator with a literal
        .CMP_A_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.Compare(vm.accumulator, literal);
        },
        // modify flags by subtracting the accumulator with the contents of an address
        .CMP_A_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.Compare(vm.accumulator, address_contents);
        },
        // modify flags by subtracting the X index with the accumulator
        .CMP_X_A => {
            vm.Compare(vm.x_index, vm.accumulator);
        },
        // modify flags by subtracting the X index with the Y index
        .CMP_X_Y => {
            vm.Compare(vm.x_index, vm.y_index);
        },
        // modify flags by subtracting the X index with a literal
        .CMP_X_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.Compare(vm.x_index, literal);
        },
        // modify flags by subtracting the X index with the contents of an address
        .CMP_X_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.Compare(vm.x_index, address_contents);
        },
        // modify flags by subtracting the Y index with the X index
        .CMP_Y_X => {
            vm.Compare(vm.y_index, vm.x_index);
        },
        // modify flags by subtracting the Y index with the accumulator
        .CMP_Y_A => {
            vm.Compare(vm.y_index, vm.accumulator);
        },
        // modify flags by subtracting the Y index with a literal
        .CMP_Y_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.Compare(vm.y_index, literal);
        },
        // modify flags by subtracting the Y index with the contents of an address
        .CMP_Y_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.Compare(vm.y_index, address_contents);
        },
        // branch if carry set
        .BCS_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Carry_Set(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if carry clear
        .BCC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Carry_Clear(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if equal (zero flag is set)
        .BEQ_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Zero_Set(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if not equal (zero flag is clear)
        .BNE_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Zero_Clear(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if minus (negative flag is set)
        .BMI_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Negative_Set(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if plus (negative flag is clear)
        .BPL_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Negative_Clear(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if overflow is set
        .BVS_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Overflow_Set(vm, address)) {
                pc_increment = 0;
            }
        },
        // branch if overflow is clear
        .BVC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (machine.VirtualMachine.BranchIf.Overflow_Clear(vm, address)) {
                pc_increment = 0;
            }
        },
        // accumulator += (literal + carry)
        .ADD_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, literal, @intFromBool(vm.carry_flag));
        },
        // accumulator += (address contents + carry)
        .ADD_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, address_contents, @intFromBool(vm.carry_flag));
        },
        // accumulator += (X index value + carry)
        .ADD_X => {
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.x_index, @intFromBool(vm.carry_flag));
        },
        // accumulator += (Y index value + carry)
        .ADD_Y => {
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.y_index, @intFromBool(vm.carry_flag));
        },
        // accumulator -= (literal + carry - 1)
        .SUB_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            vm.accumulator = vm.Sub_With_Carry(vm.accumulator, literal, @intFromBool(vm.carry_flag));
        },
        // accumulator -= (address contents + carry - 1)
        .SUB_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            vm.accumulator = vm.Sub_With_Carry(vm.accumulator, address_contents, @intFromBool(vm.carry_flag));
        },
        // accumulator -= (X index value + carry - 1)
        .SUB_X => {
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.x_index, @intFromBool(vm.carry_flag));
        },
        // accumulator -= (Y index value + carry - 1)
        .SUB_Y => {
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.x_index, @intFromBool(vm.carry_flag));
        },
        // accumulator += 1
        .INC_A => {
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, 1, 0);
        },
        // X index += 1
        .INC_X => {
            vm.x_index = vm.Add_With_Carry(vm.x_index, 1, 0);
        },
        // Y index += 1
        .INC_Y => {
            vm.y_index = vm.Add_With_Carry(vm.y_index, 1, 0);
        },
        // contents of address += 1
        .INC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            var address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            address_contents = vm.Add_With_Carry(address_contents, 1, 0);
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(address_contents), address_contents);
        },
        // accumulator -= 1
        .DEC_A => {
            vm.accumulator = vm.Sub_With_Carry(vm.accumulator, 1, 1);
        },
        // X index -= 1
        .DEC_X => {
            vm.x_index = vm.Sub_With_Carry(vm.x_index, 1, 1);
        },
        // Y index -= 1
        .DEC_Y => {
            vm.y_index = vm.Sub_With_Carry(vm.y_index, 1, 1);
        },
        // contents of address -= 1
        .DEC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            var address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            address_contents = vm.Sub_With_Carry(address_contents, 1, 1);
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(address_contents), address_contents);
        },
        // push value of accumulator to stack
        .PUSH_A => {
            vm.Push_To_Stack(@TypeOf(vm.accumulator), vm.accumulator) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // push value of X index to stack
        .PUSH_X => {
            vm.Push_To_Stack(@TypeOf(vm.x_index), vm.x_index) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // push value of Y index to stack
        .PUSH_Y => {
            vm.Push_To_Stack(@TypeOf(vm.y_index), vm.y_index) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // pops 4 bytes from the stack and store them in the accumulator
        .POP_A => {
            vm.accumulator = vm.Pop_From_Stack(@TypeOf(vm.accumulator)) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // pops 4 bytes from the stack and store them in the X index
        .POP_X => {
            vm.x_index = vm.Pop_From_Stack(@TypeOf(vm.x_index)) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // pops 4 bytes from the stack and store them in the Y index
        .POP_Y => {
            vm.y_index = vm.Pop_From_Stack(@TypeOf(vm.y_index)) catch |err| {
                machine.Output_Error_Message(err);
                return QUIT;
            };
        },
        // skip execution of metadata
        .DEBUG_METADATA_SIGNAL => {
            const metadata_type: specs.DebugMetadataType = @enumFromInt(vm.rom[vm.program_counter + 1]);
            const skip_count: usize = metadata_type.Metadata_Length(vm.rom[vm.program_counter..]) catch {
                warn.Fatal_Error_Message("Bad metadata!", .{});
                return QUIT;
            };
            vm.program_counter += @truncate(skip_count);
        },
    }

    vm.program_counter += pc_increment;
    return CONTINUE;
}
