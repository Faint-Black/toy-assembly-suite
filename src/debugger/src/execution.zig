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

const stdout = std.io.getStdOut().writer();

pub fn Run_Virtual_Machine(vm: *machine.VirtualMachine, flags: clap.Flags, header: specs.Header) !void {
    // set current PC execution to the entry point
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
            stdout.print("Instruction: {s}\n", .{try opcode_enum.Instruction_String(&buf, vm.rom[vm.program_counter .. vm.program_counter + opcode_enum.Instruction_Byte_Length()])}) catch unreachable;
        }
        switch (opcode_enum) {
            // useful for debugging when fill_byte is set to zero
            .PANIC => {
                warn.Error_Message("Attempted to execute a null byte!", .{});
                break;
            },
            // perform a system call
            .SYSTEMCALL => {
                try vm.Syscall();
            },
            // set byte stride for indexing instructions
            .STRIDE_LIT => {
                const stride: u8 = vm.rom[vm.program_counter + specs.bytelen.opcode];
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before:\nByte stride = {}\n", .{vm.index_byte_stride}) catch unreachable;
                }
                vm.index_byte_stride = stride;
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After:\nByte stride = {}\n", .{vm.index_byte_stride}) catch unreachable;
                }
            },
            // graciously exit
            .BRK => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("BRK caught, exiting program.\n\n", .{}) catch unreachable;
                }
                stdout.print("Execution complete.\n", .{}) catch unreachable;
                quit = true;
            },
            // NOPs inside the debugger trigger configurable delays
            .NOP => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("NOP caught, triggering manual delay of:\n{}ms\n", .{flags.nop_delay}) catch unreachable;
                }
                if (flags.nop_delay != 0)
                    std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(flags.nop_delay));
            },
            // clear carry flag
            .CLC => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before clearing flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
                vm.Clear_Carry_Flag();
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After clearing flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
            },
            // set carry flag
            .SEC => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before setting flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
                vm.Set_Carry_Flag();
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After setting flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
            },
            // only instruction capable of returning from subroutines
            .RET => {
                try vm.Return_From_Subroutine();
            },
            // load literal into accumulator
            .LDA_LIT => {
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading literal 0x{X:0>8}:\nA = {}\n", .{ literal, vm.accumulator }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(literal, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading literal 0x{X:0>8}:\nA = {}\n", .{ literal, vm.accumulator }) catch unreachable;
                }
            },
            // load literal into X index
            .LDX_LIT => {
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading literal 0x{X:0>8}:\nX = {}\n", .{ literal, vm.x_index }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(literal, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading literal 0x{X:0>8}:\nX = {}\n", .{ literal, vm.x_index }) catch unreachable;
                }
            },
            // load literal into Y index
            .LDY_LIT => {
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading literal 0x{X:0>8}:\nY = {}\n", .{ literal, vm.y_index }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(literal, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading literal 0x{X:0>8}:\nY = {}\n", .{ literal, vm.y_index }) catch unreachable;
                }
            },
            // load address contents into accumulator
            .LDA_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading contents (0x{X:0>8}) from 0x{X:0>4}:\nA = {}\n", .{ address_contents, address, vm.accumulator }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading contents (0x{X:0>8}) from 0x{X:0>4}:\nA = {}\n", .{ address_contents, address, vm.accumulator }) catch unreachable;
                }
            },
            // load address contents into X index
            .LDX_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading (0x{X:0>8}) from 0x{X:0>4}:\nX = {}\n", .{ address_contents, address, vm.x_index }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading (0x{X:0>8}) from 0x{X:0>4}:\nX = {}\n", .{ address_contents, address, vm.x_index }) catch unreachable;
                }
            },
            // load address contents into Y index
            .LDY_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading (0x{X:0>8}) from 0x{X:0>4}:\nY = {}\n", .{ address_contents, address, vm.y_index }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading (0x{X:0>8}) from 0x{X:0>4}:\nY = {}\n", .{ address_contents, address, vm.y_index }) catch unreachable;
                }
            },
            // a = x
            .LDA_X => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering X to A:\nX = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.x_index, vm.accumulator }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.accumulator, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering X to A:\nX = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.x_index, vm.accumulator }) catch unreachable;
                }
            },
            // a = y
            .LDA_Y => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering Y to A:\nY = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.y_index, vm.accumulator }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.accumulator, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering Y to A:\nY = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.y_index, vm.accumulator }) catch unreachable;
                }
            },
            // x = a
            .LDX_A => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering A to X:\nA = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.accumulator, vm.x_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.x_index, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering A to X:\nA = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.accumulator, vm.x_index }) catch unreachable;
                }
            },
            // x = y
            .LDX_Y => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering Y to X:\nY = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.y_index, vm.x_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.y_index, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering Y to X:\nY = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.y_index, vm.x_index }) catch unreachable;
                }
            },
            // y = a
            .LDY_A => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering A to Y:\nA = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.accumulator, vm.y_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.y_index, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering A to Y:\nA = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.accumulator, vm.y_index }) catch unreachable;
                }
            },
            // y = x
            .LDY_X => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering X to Y:\nX = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.x_index, vm.y_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.y_index, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering X to Y:\nX = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.x_index, vm.y_index }) catch unreachable;
                }
            },
            // accumulator = u32 dereference of (address_ptr + (X * stride))
            .LDA_ADDR_X => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const index_addr: u16 = address +% ((@as(u16, @truncate(vm.x_index))) *% vm.index_byte_stride);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, index_addr, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading \"{}\" from 0x{X:0>4}->0x{X:0>4}:\nA = {}\n", .{ address_contents, address, index_addr, vm.accumulator }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading \"{}\" from 0x{X:0>4}->0x{X:0>4}:\nA = {}\n", .{ address_contents, address, index_addr, vm.accumulator }) catch unreachable;
                }
            },
            // accumulator = u32 dereference of (address_ptr + (Y * stride))
            .LDA_ADDR_Y => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const index_addr: u16 = address +% ((@as(u16, @truncate(vm.y_index))) *% vm.index_byte_stride);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, index_addr, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading \"{}\" from 0x{X:0>4}->0x{X:0>4}:\nA = {}\n", .{ address_contents, address, index_addr, vm.accumulator }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading \"{}\" from 0x{X:0>4}->0x{X:0>4}:\nA = {}\n", .{ address_contents, address, index_addr, vm.accumulator }) catch unreachable;
                }
            },
            // load address as a literal number, then store it in the accumulator
            .LEA_ADDR => {
                const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading effective address of 0x{X:0>4}:\nA = 0x{X:0>8} or {}\n", .{ address_literal, vm.accumulator, vm.accumulator }) catch unreachable;
                }
                vm.accumulator = @intCast(address_literal);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading effective address of 0x{X:0>4}:\nA = 0x{X:0>8} or {}\n", .{ address_literal, vm.accumulator, vm.accumulator }) catch unreachable;
                }
            },
            // load address as a literal number, then store it in the X index
            .LEX_ADDR => {
                const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading effective address of 0x{X:0>4}:\nX = 0x{X:0>8} or {}\n", .{ address_literal, vm.x_index, vm.x_index }) catch unreachable;
                }
                vm.x_index = @intCast(address_literal);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading effective address of 0x{X:0>4}:\nX = 0x{X:0>8} or {}\n", .{ address_literal, vm.x_index, vm.x_index }) catch unreachable;
                }
            },
            // load address as a literal number, then store it in the Y index
            .LEY_ADDR => {
                const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading effective address of 0x{X:0>4}:\nY = 0x{X:0>8} or {}\n", .{ address_literal, vm.y_index, vm.y_index }) catch unreachable;
                }
                vm.y_index = @intCast(address_literal);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading effective address of 0x{X:0>4}:\nY = 0x{X:0>8} or {}\n", .{ address_literal, vm.y_index, vm.y_index }) catch unreachable;
                }
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
            },
            // go to ROM address and save its position on the stack
            .JSR_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                try vm.Jump_To_Subroutine(address);
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
                vm.Branch_If_Carry_Set(address);
            },
            // branch if carry clear
            .BCC_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Carry_Clear(address);
            },
            // branch if equal (zero flag is set)
            .BEQ_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Zero_Set(address);
            },
            // branch if not equal (zero flag is clear)
            .BNE_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Zero_Clear(address);
            },
            // branch if minus (negative flag is set)
            .BMI_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Negative_Set(address);
            },
            // branch if plus (negative flag is clear)
            .BPL_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Negative_Clear(address);
            },
            // branch if overflow is set
            .BVS_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Overflow_Set(address);
            },
            // branch if overflow is clear
            .BVC_ADDR => {
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Branch_If_Overflow_Clear(address);
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
                try vm.Push_To_Stack(@TypeOf(vm.accumulator), vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Pushed the accumulator value 0x{X:0>8} to the stack\n", .{vm.accumulator}) catch unreachable;
                }
            },
            // push value of X index to stack
            .PUSH_X => {
                try vm.Push_To_Stack(@TypeOf(vm.x_index), vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Pushed the X index value 0x{X:0>8} to the stack\n", .{vm.x_index}) catch unreachable;
                }
            },
            // push value of Y index to stack
            .PUSH_Y => {
                try vm.Push_To_Stack(@TypeOf(vm.y_index), vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Pushed the Y index value 0x{X:0>8} to the stack\n", .{vm.y_index}) catch unreachable;
                }
            },
            // pops 4 bytes from the stack and store them in the accumulator
            .POP_A => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
                vm.accumulator = try vm.Pop_From_Stack(@TypeOf(vm.accumulator));
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
            },
            // pops 4 bytes from the stack and store them in the X index
            .POP_X => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
                vm.x_index = try vm.Pop_From_Stack(@TypeOf(vm.x_index));
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
            },
            // pops 4 bytes from the stack and store them in the Y index
            .POP_Y => {
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
                vm.y_index = try vm.Pop_From_Stack(@TypeOf(vm.y_index));
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
            },
            // skip execution of metadata
            .DEBUG_METADATA_SIGNAL => {
                const metadata_type: specs.DebugMetadataType = @enumFromInt(vm.rom[vm.program_counter + 1]);
                const skip_count: usize = try metadata_type.Metadata_Length(vm.rom[vm.program_counter..]);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Skipping {} bytes of ROM metadata\n", .{skip_count}) catch unreachable;
                }
                vm.program_counter += @truncate(skip_count);
                continue;
            },
        }

        // advance PC pointer
        vm.program_counter += opcode_enum.Instruction_Byte_Length();
    }
}
