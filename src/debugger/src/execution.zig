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
            stdout.print("Instruction: {s}\n", .{try opcode_enum.Instruction_String(&buf, vm.rom[vm.program_counter .. vm.program_counter + opcode_enum.Instruction_Byte_Length()])}) catch unreachable;
        }
        switch (opcode_enum) {
            .PANIC => {
                // useful for debugging when fill_byte is set to zero
                warn.Error_Message("Attempted to execute a null byte!", .{});
                break;
            },
            .SYSTEMCALL => {
                // perform a system call
                try vm.Syscall();
            },
            .STRIDE_LIT => {
                // set byte stride for indexing instructions
                const stride: u8 = vm.rom[vm.program_counter + specs.bytelen.opcode];
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before:\nByte stride = {}\n", .{vm.index_byte_stride}) catch unreachable;
                }
                vm.index_byte_stride = stride;
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After:\nByte stride = {}\n", .{vm.index_byte_stride}) catch unreachable;
                }
            },
            .BRK => {
                // graciously exit
                if (flags.log_instruction_sideeffects) {
                    stdout.print("BRK caught, exiting program.\n\n", .{}) catch unreachable;
                }
                stdout.print("Execution complete.\n", .{}) catch unreachable;
                quit = true;
            },
            .NOP => {
                // NOPs inside the debugger trigger configurable delays
                if (flags.log_instruction_sideeffects) {
                    stdout.print("NOP caught, triggering manual delay of:\n{}ms\n", .{flags.nop_delay}) catch unreachable;
                }
                if (flags.nop_delay != 0)
                    std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(flags.nop_delay));
            },
            .CLC => {
                // clear carry flag
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before clearing flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
                vm.carry_flag = false;
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After clearing flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
            },
            .SEC => {
                // set carry flag
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before setting flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
                vm.carry_flag = true;
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After setting flag:\nC = {}\n", .{@intFromBool(vm.carry_flag)}) catch unreachable;
                }
            },
            .RET => {
                // only instruction capable of returning from subroutines
                try vm.Return_From_Subroutine();
            },
            .LDA_LIT => {
                // load literal into accumulator
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading literal 0x{X:0>8}:\nA = {}\n", .{ literal, vm.accumulator }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(literal, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading literal 0x{X:0>8}:\nA = {}\n", .{ literal, vm.accumulator }) catch unreachable;
                }
            },
            .LDX_LIT => {
                // load literal into X index
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading literal 0x{X:0>8}:\nX = {}\n", .{ literal, vm.x_index }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(literal, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading literal 0x{X:0>8}:\nX = {}\n", .{ literal, vm.x_index }) catch unreachable;
                }
            },
            .LDY_LIT => {
                // load literal into Y index
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading literal 0x{X:0>8}:\nY = {}\n", .{ literal, vm.y_index }) catch unreachable;
                }
                vm.Load_Value_Into_Reg(literal, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading literal 0x{X:0>8}:\nY = {}\n", .{ literal, vm.y_index }) catch unreachable;
                }
            },
            .LDA_ADDR => {
                // load address contents into accumulator
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
            .LDX_ADDR => {
                // load address contents into X index
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
            .LDY_ADDR => {
                // load address contents into Y index
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
            .LDA_X => {
                // a = x
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering X to A:\nX = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.x_index, vm.accumulator }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.accumulator, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering X to A:\nX = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.x_index, vm.accumulator }) catch unreachable;
                }
            },
            .LDA_Y => {
                // a = y
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering Y to A:\nY = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.y_index, vm.accumulator }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.accumulator, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering Y to A:\nY = 0x{X:0>8}, A = 0x{X:0>8}\n", .{ vm.y_index, vm.accumulator }) catch unreachable;
                }
            },
            .LDX_A => {
                // x = a
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering A to X:\nA = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.accumulator, vm.x_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.x_index, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering A to X:\nA = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.accumulator, vm.x_index }) catch unreachable;
                }
            },
            .LDX_Y => {
                // x = y
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering Y to X:\nY = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.y_index, vm.x_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.y_index, &vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering Y to X:\nY = 0x{X:0>8}, X = 0x{X:0>8}\n", .{ vm.y_index, vm.x_index }) catch unreachable;
                }
            },
            .LDY_A => {
                // y = a
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering A to Y:\nA = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.accumulator, vm.y_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.y_index, &vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering A to Y:\nA = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.accumulator, vm.y_index }) catch unreachable;
                }
            },
            .LDY_X => {
                // y = x
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before transfering X to Y:\nX = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.x_index, vm.y_index }) catch unreachable;
                }
                vm.Transfer_Registers(&vm.y_index, &vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After transfering X to Y:\nX = 0x{X:0>8}, Y = 0x{X:0>8}\n", .{ vm.x_index, vm.y_index }) catch unreachable;
                }
            },
            .LDA_ADDR_X => {
                // accumulator = u32 dereference of (address_ptr + (X * stride))
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
            .LDA_ADDR_Y => {
                // accumulator = u32 dereference of (address_ptr + (Y * stride))
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
            .LEA_ADDR => {
                // load address as a literal number, then store it in the accumulator
                const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading effective address of 0x{X:0>4}:\nA = 0x{X:0>8} or {}\n", .{ address_literal, vm.accumulator, vm.accumulator }) catch unreachable;
                }
                vm.accumulator = @intCast(address_literal);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading effective address of 0x{X:0>4}:\nA = 0x{X:0>8} or {}\n", .{ address_literal, vm.accumulator, vm.accumulator }) catch unreachable;
                }
            },
            .LEX_ADDR => {
                // load address as a literal number, then store it in the X index
                const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading effective address of 0x{X:0>4}:\nX = 0x{X:0>8} or {}\n", .{ address_literal, vm.x_index, vm.x_index }) catch unreachable;
                }
                vm.x_index = @intCast(address_literal);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading effective address of 0x{X:0>4}:\nX = 0x{X:0>8} or {}\n", .{ address_literal, vm.x_index, vm.x_index }) catch unreachable;
                }
            },
            .LEY_ADDR => {
                // load address as a literal number, then store it in the Y index
                const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Before loading effective address of 0x{X:0>4}:\nY = 0x{X:0>8} or {}\n", .{ address_literal, vm.y_index, vm.y_index }) catch unreachable;
                }
                vm.y_index = @intCast(address_literal);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("After loading effective address of 0x{X:0>4}:\nY = 0x{X:0>8} or {}\n", .{ address_literal, vm.y_index, vm.y_index }) catch unreachable;
                }
            },
            .STA_ADDR => {
                // store value of accumulator into an address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.accumulator), vm.accumulator);
            },
            .STX_ADDR => {
                // store value of X index into an address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.x_index), vm.x_index);
            },
            .STY_ADDR => {
                // store value of Y index into an address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.y_index), vm.y_index);
            },
            .JMP_ADDR => {
                // go to ROM address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                vm.Jump_To_Address(address);
            },
            .JSR_ADDR => {
                // go to ROM address and save its position on the stack
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                try vm.Jump_To_Subroutine(address);
            },
            .CMP_A_X => {
                // modify flags by subtracting the accumulator with the X index
                _ = vm.Subtract(vm.accumulator, vm.x_index);
            },
            .CMP_A_Y => {
                // modify flags by subtracting the accumulator with the Y index
                _ = vm.Subtract(vm.accumulator, vm.y_index);
            },
            .CMP_A_LIT => {
                // modify flags by subtracting the accumulator with a literal
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                _ = vm.Subtract(vm.accumulator, literal);
            },
            .CMP_A_ADDR => {
                // modify flags by subtracting the accumulator with the contents of an address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                _ = vm.Subtract(vm.accumulator, address_contents);
            },
            .CMP_X_A => {
                // modify flags by subtracting the X index with the accumulator
                _ = vm.Subtract(vm.x_index, vm.accumulator);
            },
            .CMP_X_Y => {
                // modify flags by subtracting the X index with the Y index
                _ = vm.Subtract(vm.x_index, vm.y_index);
            },
            .CMP_X_LIT => {
                // modify flags by subtracting the X index with a literal
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                _ = vm.Subtract(vm.x_index, literal);
            },
            .CMP_X_ADDR => {
                // modify flags by subtracting the X index with the contents of an address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                _ = vm.Subtract(vm.x_index, address_contents);
            },
            .CMP_Y_X => {
                // modify flags by subtracting the Y index with the X index
                _ = vm.Subtract(vm.y_index, vm.x_index);
            },
            .CMP_Y_A => {
                // modify flags by subtracting the Y index with the accumulator
                _ = vm.Subtract(vm.y_index, vm.accumulator);
            },
            .CMP_Y_LIT => {
                // modify flags by subtracting the Y index with a literal
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                _ = vm.Subtract(vm.y_index, literal);
            },
            .CMP_Y_ADDR => {
                // modify flags by subtracting the Y index with the contents of an address
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                _ = vm.Subtract(vm.y_index, address_contents);
            },
            .BCS_ADDR => {
                // branch if carry set
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.carry_flag == true)
                    vm.Jump_To_Address(address);
            },
            .BCC_ADDR => {
                // branch if carry clear
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.carry_flag == false)
                    vm.Jump_To_Address(address);
            },
            .BEQ_ADDR => {
                // branch if equal (zero flag is set)
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.zero_flag == true)
                    vm.Jump_To_Address(address);
            },
            .BNE_ADDR => {
                // branch if not equal (zero flag is clear)
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.zero_flag == false)
                    vm.Jump_To_Address(address);
            },
            .BMI_ADDR => {
                // branch if minus (negative flag is set)
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.negative_flag == true)
                    vm.Jump_To_Address(address);
            },
            .BPL_ADDR => {
                // branch if plus (negative flag is clear)
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.negative_flag == false)
                    vm.Jump_To_Address(address);
            },
            .BVS_ADDR => {
                // branch if overflow is set
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.overflow_flag == true)
                    vm.Jump_To_Address(address);
            },
            .BVC_ADDR => {
                // branch if overflow is clear
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                if (vm.overflow_flag == false)
                    vm.Jump_To_Address(address);
            },
            .ADD_LIT => {
                // accumulator += (literal + carry)
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                vm.accumulator = vm.Add(vm.accumulator, literal);
            },
            .ADD_ADDR => {
                // accumulator += (address contents + carry)
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.accumulator = vm.Add(vm.accumulator, address_contents);
            },
            .ADD_X => {
                // accumulator += (X index value + carry)
                vm.accumulator = vm.Add(vm.accumulator, vm.x_index);
            },
            .ADD_Y => {
                // accumulator += (Y index value + carry)
                vm.accumulator = vm.Add(vm.accumulator, vm.y_index);
            },
            .SUB_LIT => {
                // accumulator -= (literal + carry - 1)
                const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
                vm.accumulator = vm.Subtract(vm.accumulator, literal);
            },
            .SUB_ADDR => {
                // accumulator -= (address contents + carry - 1)
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.accumulator = vm.Subtract(vm.accumulator, address_contents);
            },
            .SUB_X => {
                // accumulator -= (X index value + carry - 1)
                vm.accumulator = vm.Add(vm.accumulator, vm.x_index);
            },
            .SUB_Y => {
                // accumulator -= (Y index value + carry - 1)
                vm.accumulator = vm.Add(vm.accumulator, vm.x_index);
            },
            .INC_A => {
                // accumulator += 1
                vm.carry_flag = false;
                vm.accumulator = vm.Add(vm.accumulator, 1);
            },
            .INC_X => {
                // X index += 1
                vm.carry_flag = false;
                vm.x_index = vm.Add(vm.x_index, 1);
            },
            .INC_Y => {
                // Y index += 1
                vm.carry_flag = false;
                vm.y_index = vm.Add(vm.y_index, 1);
            },
            .INC_ADDR => {
                // contents of address += 1
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                var address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.carry_flag = false;
                address_contents = vm.Add(address_contents, 1);
                machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(address_contents), address_contents);
            },
            .DEC_A => {
                // accumulator -= 1
                vm.carry_flag = true;
                vm.accumulator = vm.Subtract(vm.accumulator, 1);
            },
            .DEC_X => {
                // X index -= 1
                vm.carry_flag = true;
                vm.x_index = vm.Subtract(vm.x_index, 1);
            },
            .DEC_Y => {
                // Y index -= 1
                vm.carry_flag = true;
                vm.y_index = vm.Subtract(vm.y_index, 1);
            },
            .DEC_ADDR => {
                // contents of address -= 1
                const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
                var address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.carry_flag = true;
                address_contents = vm.Subtract(address_contents, 1);
                machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(address_contents), address_contents);
            },
            .PUSH_A => {
                // push value of accumulator to stack
                try vm.Push_To_Stack(@TypeOf(vm.accumulator), vm.accumulator);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Pushed the accumulator value 0x{X:0>8} to the stack\n", .{vm.accumulator}) catch unreachable;
                }
            },
            .PUSH_X => {
                // push value of X index to stack
                try vm.Push_To_Stack(@TypeOf(vm.x_index), vm.x_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Pushed the X index value 0x{X:0>8} to the stack\n", .{vm.x_index}) catch unreachable;
                }
            },
            .PUSH_Y => {
                // push value of Y index to stack
                try vm.Push_To_Stack(@TypeOf(vm.y_index), vm.y_index);
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Pushed the Y index value 0x{X:0>8} to the stack\n", .{vm.y_index}) catch unreachable;
                }
            },
            .POP_A => {
                // pops 4 bytes from the stack and store them in the accumulator
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
                vm.accumulator = try vm.Pop_From_Stack(@TypeOf(vm.accumulator));
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
            },
            .POP_X => {
                // pops 4 bytes from the stack and store them in the X index
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
                vm.x_index = try vm.Pop_From_Stack(@TypeOf(vm.x_index));
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
            },
            .POP_Y => {
                // pops 4 bytes from the stack and store them in the Y index
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator before popping from stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
                vm.y_index = try vm.Pop_From_Stack(@TypeOf(vm.y_index));
                if (flags.log_instruction_sideeffects) {
                    stdout.print("Value of accumulator after popping 4 bytes from the stack:\nA = {}\n", .{vm.accumulator}) catch unreachable;
                }
            },
            .DEBUG_METADATA_SIGNAL => {
                // skip execution of metadata
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
