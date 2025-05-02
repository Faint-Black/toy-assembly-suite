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
pub fn Run_Instruction(op: specs.Opcode, vm: *machine.VirtualMachine, flags: clap.Flags) !bool {
    // "macros"
    const QUIT = true;
    const CONTINUE = false;
    // for storing the bufprints
    var bufs: [4][utils.buffsize.large]u8 = undefined;

    // do not increment PC after a jump instruction
    var pc_increment: u8 = op.Instruction_Byte_Length();
    switch (op) {
        // useful for debugging when fill_byte is set to zero
        .PANIC => {
            warn.Error_Message("Attempted to execute a null byte!", .{});
            return QUIT;
        },
        // perform a system call
        .SYSTEMCALL => {
            // no logging to not pollute the console output
            try vm.Syscall();
        },
        // set byte stride for indexing instructions
        .STRIDE_LIT => {
            const stride: u8 = vm.rom[vm.program_counter + specs.bytelen.opcode];
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before setting stride:\nByte stride = {}\n", .{vm.index_byte_stride}) catch unreachable;
            }
            vm.index_byte_stride = stride;
            if (flags.log_instruction_sideeffects) {
                stdout.print("After setting stride:\nByte stride = {}\n", .{vm.index_byte_stride}) catch unreachable;
            }
        },
        // graciously exit
        .BRK => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("BRK caught, exiting program.\n\n", .{}) catch unreachable;
            }
            stdout.print("Execution complete.\n", .{}) catch unreachable;
            return QUIT;
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
                stdout.print("Before clearing flag:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Clear_Carry_Flag();
            if (flags.log_instruction_sideeffects) {
                stdout.print("After clearing flag:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // set carry flag
        .SEC => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before setting flag:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Set_Carry_Flag();
            if (flags.log_instruction_sideeffects) {
                stdout.print("After setting flag:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // only instruction capable of returning from subroutines
        .RET => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before returning from subroutine:\n{s}\n", .{Bp_PC(vm, &bufs[0])}) catch unreachable;
            }
            try vm.Return_From_Subroutine();
            if (flags.log_instruction_sideeffects) {
                stdout.print("After returning from subroutine:\n{s}\n", .{Bp_PC(vm, &bufs[0])}) catch unreachable;
            }
            pc_increment = 0;
        },
        // load literal into accumulator
        .LDA_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading the literal {s} into accumulator:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(literal, &vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading the literal {s} into accumulator:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // load literal into X index
        .LDX_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading the literal {s} into X index:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(literal, &vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading the literal {s} into X index:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // load literal into Y index
        .LDY_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading the literal {s} into X index:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(literal, &vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading the literal {s} into X index:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // load address contents into accumulator
        .LDA_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading {s} from address {s} into the Accumulator:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading {s} from address {s} into the Accumulator:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // load address contents into X index
        .LDX_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading {s} from address {s} into the X index:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(address_contents, &vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading {s} from address {s} into the X index:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // load address contents into Y index
        .LDY_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading {s} from address {s} into the Y index:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(address_contents, &vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading {s} from address {s} into the Y index:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // a = x
        .LDA_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before transfering X to A:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
            vm.Transfer_Registers(&vm.accumulator, &vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After transfering X to A:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
        },
        // a = y
        .LDA_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before transfering Y to A:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
            vm.Transfer_Registers(&vm.accumulator, &vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After transfering Y to A:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
        },
        // x = a
        .LDX_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before transfering A to X:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
            vm.Transfer_Registers(&vm.x_index, &vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After transfering A to X:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
        },
        // x = y
        .LDX_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before transfering Y to X:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
            vm.Transfer_Registers(&vm.y_index, &vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After transfering Y to X:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
        },
        // y = a
        .LDY_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before transfering A to Y:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
            vm.Transfer_Registers(&vm.y_index, &vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After transfering A to Y:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
        },
        // y = x
        .LDY_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before transfering X to Y:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
            vm.Transfer_Registers(&vm.y_index, &vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After transfering X to Y:\n{s}\n", .{Bp_Regs(vm, &bufs[0])}) catch unreachable;
            }
        },
        // accumulator = u32 dereference of (address_ptr + (X * stride))
        .LDA_ADDR_X => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const index_addr: u16 = address +% ((@as(u16, @truncate(vm.x_index))) *% vm.index_byte_stride);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, index_addr, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading {s} from X indexed address {s}+{}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), index_addr - address, Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading {s} from X indexed address {s}+{}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), index_addr - address, Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // accumulator = u32 dereference of (address_ptr + (Y * stride))
        .LDA_ADDR_Y => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const index_addr: u16 = address +% ((@as(u16, @truncate(vm.y_index))) *% vm.index_byte_stride);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, index_addr, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading {s} from Y indexed address {s}+{}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), index_addr - address, Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading {s} from Y indexed address {s}+{}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), index_addr - address, Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // load address as a literal number, then store it in the accumulator
        .LEA_ADDR => {
            const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading effective address of {s} into Accumulator:\n{s}\n", .{ Bp_Addr(&bufs[0], address_literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = @intCast(address_literal);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading effective address of {s} into Accumulator:\n{s}\n", .{ Bp_Addr(&bufs[0], address_literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // load address as a literal number, then store it in the X index
        .LEX_ADDR => {
            const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading effective address of {s} into X index:\n{s}\n", .{ Bp_Addr(&bufs[0], address_literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.x_index = @intCast(address_literal);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading effective address of {s} into X index:\n{s}\n", .{ Bp_Addr(&bufs[0], address_literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // load address as a literal number, then store it in the Y index
        .LEY_ADDR => {
            const address_literal: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before loading effective address of {s} into Y index:\n{s}\n", .{ Bp_Addr(&bufs[0], address_literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.y_index = @intCast(address_literal);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After loading effective address of {s} into Y index:\n{s}\n", .{ Bp_Addr(&bufs[0], address_literal), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // store value of accumulator into an address
        .STA_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Storing Accumulator with value {s} into RAM address {s}\n", .{ Bp_Lit(&bufs[0], vm.accumulator), Bp_Addr(&bufs[1], address) }) catch unreachable;
            }
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.accumulator), vm.accumulator);
        },
        // store value of X index into an address
        .STX_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Storing X index with value {s} into RAM address {s}\n", .{ Bp_Lit(&bufs[0], vm.x_index), Bp_Addr(&bufs[1], address) }) catch unreachable;
            }
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.x_index), vm.x_index);
        },
        // store value of Y index into an address
        .STY_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Storing Y index with value {s} into RAM address {s}\n", .{ Bp_Lit(&bufs[0], vm.y_index), Bp_Addr(&bufs[1], address) }) catch unreachable;
            }
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(vm.y_index), vm.y_index);
        },
        // go to ROM address
        .JMP_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before jumping to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Jump_To_Address(address);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After jumping to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            pc_increment = 0;
        },
        // go to ROM address and save its position on the stack
        .JSR_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before jumping to subroutine at address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            try vm.Jump_To_Subroutine(address);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After jumping to subroutine at address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            pc_increment = 0;
        },
        // modify flags by subtracting the accumulator with the X index
        .CMP_A_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing A with X:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Compare(vm.accumulator, vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing A with X:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // modify flags by subtracting the accumulator with the Y index
        .CMP_A_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing A with Y:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Compare(vm.accumulator, vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing A with Y:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // modify flags by subtracting the accumulator with a literal
        .CMP_A_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing A with the literal {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Compare(vm.accumulator, literal);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing A with the literal {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // modify flags by subtracting the accumulator with the contents of an address
        .CMP_A_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing A with the value {s} inside address {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Compare(vm.accumulator, address_contents);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing A with the value {s} inside address {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // modify flags by subtracting the X index with the accumulator
        .CMP_X_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing X with A:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Compare(vm.x_index, vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing X with A:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // modify flags by subtracting the X index with the Y index
        .CMP_X_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing X with Y:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Compare(vm.x_index, vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing X with Y:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // modify flags by subtracting the X index with a literal
        .CMP_X_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing X with the literal {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Compare(vm.x_index, literal);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing X with the literal {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // modify flags by subtracting the X index with the contents of an address
        .CMP_X_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing X with the value {s} inside address {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Compare(vm.x_index, address_contents);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing X with the value {s} inside address {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // modify flags by subtracting the Y index with the X index
        .CMP_Y_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing Y with X:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Compare(vm.y_index, vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing Y with X:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // modify flags by subtracting the Y index with the accumulator
        .CMP_Y_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing Y with A:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
            vm.Compare(vm.y_index, vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing Y with A:\n{s}\n", .{Bp_Flags(vm, &bufs[0])}) catch unreachable;
            }
        },
        // modify flags by subtracting the Y index with a literal
        .CMP_Y_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing Y with the literal {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]) }) catch unreachable;
            }
            vm.Compare(vm.y_index, literal);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing Y with the literal {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // modify flags by subtracting the Y index with the contents of an address
        .CMP_Y_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before comparing Y with the value {s} inside address {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]) }) catch unreachable;
            }
            vm.Compare(vm.y_index, address_contents);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After comparing Y with the value {s} inside address {s}:\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // branch if carry set
        .BCS_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Carry=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Carry_Set(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Carry=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if carry clear
        .BCC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Carry=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Carry_Clear(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Carry=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if equal (zero flag is set)
        .BEQ_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Zero=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Zero_Set(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Zero=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if not equal (zero flag is clear)
        .BNE_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Zero=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Zero_Clear(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Zero=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if minus (negative flag is set)
        .BMI_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Negative=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Negative_Set(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Negative=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if plus (negative flag is clear)
        .BPL_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Negative=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Negative_Clear(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Negative=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if overflow is set
        .BVS_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Overflow=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Overflow_Set(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Overflow=1 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // branch if overflow is clear
        .BVC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before branching if Overflow=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
            if (machine.VirtualMachine.BranchIf.Overflow_Clear(vm, address)) {
                pc_increment = 0;
            }
            if (flags.log_instruction_sideeffects) {
                stdout.print("After branching if Overflow=0 to address {s}:\n{s}\n", .{ Bp_Addr(&bufs[0], address), Bp_PC(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // accumulator += (literal + carry)
        .ADD_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before adding the literal {s} to the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, literal, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After adding the literal {s} to the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // accumulator += (address contents + carry)
        .ADD_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before adding {s} from address {s} to the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]), Bp_Regs(vm, &bufs[3]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, address_contents, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After adding {s} from address {s} to the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]), Bp_Regs(vm, &bufs[3]) }) catch unreachable;
            }
        },
        // accumulator += (X index value + carry)
        .ADD_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before adding the X index to the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.x_index, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After adding the X index to the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // accumulator += (Y index value + carry)
        .ADD_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before adding the Y index to the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.y_index, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After adding the X index to the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // accumulator -= (literal + carry - 1)
        .SUB_LIT => {
            const literal: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before subtracting the literal {s} from the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
            vm.accumulator = vm.Sub_With_Carry(vm.accumulator, literal, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After subtracting the literal {s} from the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], literal), Bp_Flags(vm, &bufs[1]), Bp_Regs(vm, &bufs[2]) }) catch unreachable;
            }
        },
        // accumulator -= (address contents + carry - 1)
        .SUB_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            const address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before subtracting {s} from address {s} from the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]), Bp_Regs(vm, &bufs[3]) }) catch unreachable;
            }
            vm.accumulator = vm.Sub_With_Carry(vm.accumulator, address_contents, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After subtracting {s} from address {s} from the Accumulator:\n{s}\n{s}\n", .{ Bp_Lit(&bufs[0], address_contents), Bp_Addr(&bufs[1], address), Bp_Flags(vm, &bufs[2]), Bp_Regs(vm, &bufs[3]) }) catch unreachable;
            }
        },
        // accumulator -= (X index value + carry - 1)
        .SUB_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before subtracting the X index from the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.x_index, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After subtracting the X index from the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // accumulator -= (Y index value + carry - 1)
        .SUB_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before subtracting the Y index from the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, vm.x_index, @intFromBool(vm.carry_flag));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After subtracting the Y index from the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // accumulator += 1
        .INC_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before incrementing the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = vm.Add_With_Carry(vm.accumulator, 1, 0);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After incrementing the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // X index += 1
        .INC_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before incrementing the X index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.x_index = vm.Add_With_Carry(vm.x_index, 1, 0);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After incrementing the X index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // Y index += 1
        .INC_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before incrementing the Y index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.y_index = vm.Add_With_Carry(vm.y_index, 1, 0);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After incrementing the Y index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // contents of address += 1
        .INC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            var address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before incrementing the value inside the address {s}:\n{s}\nValue = {s}\n", .{ Bp_Addr(&bufs[0], address), Bp_Flags(vm, &bufs[1]), Bp_Lit(&bufs[2], address_contents) }) catch unreachable;
            }
            address_contents = vm.Add_With_Carry(address_contents, 1, 0);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After incrementing the value inside the address {s}:\n{s}\nValue = {s}\n", .{ Bp_Addr(&bufs[0], address), Bp_Flags(vm, &bufs[1]), Bp_Lit(&bufs[2], address_contents) }) catch unreachable;
            }
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(address_contents), address_contents);
        },
        // accumulator -= 1
        .DEC_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before decrementing the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = vm.Sub_With_Carry(vm.accumulator, 1, 1);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After decrementing the Accumulator:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // X index -= 1
        .DEC_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before decrementing the X index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.x_index = vm.Sub_With_Carry(vm.x_index, 1, 1);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After decrementing the X index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // Y index -= 1
        .DEC_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before decrementing the Y index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.y_index = vm.Sub_With_Carry(vm.y_index, 1, 1);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After decrementing the Y index:\n{s}\n{s}\n", .{ Bp_Flags(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // contents of address -= 1
        .DEC_ADDR => {
            const address: u16 = machine.VirtualMachine.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.bytelen.opcode, u16);
            var address_contents: u32 = machine.VirtualMachine.Read_Address_Contents_As(&vm.wram, address, u32);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before decrementing the value inside the address {s}:\n{s}\nValue = {s}\n", .{ Bp_Addr(&bufs[0], address), Bp_Flags(vm, &bufs[1]), Bp_Lit(&bufs[2], address_contents) }) catch unreachable;
            }
            address_contents = vm.Sub_With_Carry(address_contents, 1, 1);
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before decrementing the value inside the address {s}:\n{s}\nValue = {s}\n", .{ Bp_Addr(&bufs[0], address), Bp_Flags(vm, &bufs[1]), Bp_Lit(&bufs[2], address_contents) }) catch unreachable;
            }
            machine.VirtualMachine.Write_Contents_Into_Memory_As(&vm.wram, address, @TypeOf(address_contents), address_contents);
        },
        // push value of accumulator to stack
        .PUSH_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before pushing the Accumulator value to the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            try vm.Push_To_Stack(@TypeOf(vm.accumulator), vm.accumulator);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After pushing the Accumulator value to the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // push value of X index to stack
        .PUSH_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before pushing the X index value to the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            try vm.Push_To_Stack(@TypeOf(vm.x_index), vm.x_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After pushing the X index value to the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // push value of Y index to stack
        .PUSH_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before pushing the Y index value to the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            try vm.Push_To_Stack(@TypeOf(vm.y_index), vm.y_index);
            if (flags.log_instruction_sideeffects) {
                stdout.print("After pushing the Y index value to the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // pops 4 bytes from the stack and store them in the accumulator
        .POP_A => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before popping Accumulator value from the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.accumulator = try vm.Pop_From_Stack(@TypeOf(vm.accumulator));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After popping Accumulator value from the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // pops 4 bytes from the stack and store them in the X index
        .POP_X => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before popping X index value from the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.x_index = try vm.Pop_From_Stack(@TypeOf(vm.x_index));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After popping X index value from the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
        },
        // pops 4 bytes from the stack and store them in the Y index
        .POP_Y => {
            if (flags.log_instruction_sideeffects) {
                stdout.print("Before popping Y index value from the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
            }
            vm.y_index = try vm.Pop_From_Stack(@TypeOf(vm.y_index));
            if (flags.log_instruction_sideeffects) {
                stdout.print("After popping Y index value from the stack:\n{s}\n{s}\n", .{ Bp_SP(vm, &bufs[0]), Bp_Regs(vm, &bufs[1]) }) catch unreachable;
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
        },
    }

    vm.program_counter += pc_increment;
    return CONTINUE;
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

/// Bufprint the processor flags
fn Bp_Flags(vm: *machine.VirtualMachine, buf: []u8) []const u8 {
    const c: u1 = @intFromBool(vm.carry_flag);
    const z: u1 = @intFromBool(vm.zero_flag);
    const n: u1 = @intFromBool(vm.negative_flag);
    const v: u1 = @intFromBool(vm.overflow_flag);
    return std.fmt.bufPrint(buf, "C={}, Z={}, N={}, V={}", .{ c, z, n, v }) catch unreachable;
}

/// Bufprint the Accumulator register
fn Bp_A(vm: *machine.VirtualMachine, buf: []u8) []u8 {
    return std.fmt.bufPrint(buf, "A = 0x{X:0>8} ({})", .{ vm.accumulator, vm.accumulator }) catch unreachable;
}

/// Bufprint the X index register
fn Bp_X(vm: *machine.VirtualMachine, buf: []u8) []u8 {
    return std.fmt.bufPrint(buf, "X = 0x{X:0>8} ({})", .{ vm.x_index, vm.x_index }) catch unreachable;
}

/// Bufprint the Y index register
fn Bp_Y(vm: *machine.VirtualMachine, buf: []u8) []u8 {
    return std.fmt.bufPrint(buf, "Y = 0x{X:0>8} ({})", .{ vm.y_index, vm.y_index }) catch unreachable;
}

/// Bufprint the Accumulator, X index and Y index registers
fn Bp_Regs(vm: *machine.VirtualMachine, buf: []u8) []u8 {
    var bufsize: usize = 0;
    var tmp_buffer: [utils.buffsize.large]u8 = undefined;
    const A_str = Bp_A(vm, tmp_buffer[bufsize..]);
    bufsize += A_str.len;
    const X_str = Bp_X(vm, tmp_buffer[bufsize..]);
    bufsize += X_str.len;
    const Y_str = Bp_Y(vm, tmp_buffer[bufsize..]);
    return std.fmt.bufPrint(buf, "{s}\n{s}\n{s}", .{ A_str, X_str, Y_str }) catch unreachable;
}

/// Bufprint the Program Counter register
fn Bp_PC(vm: *machine.VirtualMachine, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "PC = $0x{x:0>4}", .{vm.program_counter}) catch unreachable;
}

/// Bufprint the Stack Pointer register
fn Bp_SP(vm: *machine.VirtualMachine, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "SP = 0x{x:0>4}", .{vm.stack_pointer}) catch unreachable;
}

/// Bufprint a u32 number
fn Bp_Lit(buf: []u8, literal: u32) []const u8 {
    return std.fmt.bufPrint(buf, "{} (0x{X:0>8})", .{ @as(i32, @bitCast(literal)), literal }) catch unreachable;
}

/// Bufprint a u16 number
fn Bp_Addr(buf: []u8, address: u16) []const u8 {
    return std.fmt.bufPrint(buf, "$0x{X:0>4}", .{address}) catch unreachable;
}
