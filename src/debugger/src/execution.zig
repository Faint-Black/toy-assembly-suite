const std = @import("std");
const specs = @import("shared").specifications;
const utils = @import("shared").utils;
const machine = @import("shared").machine;

pub fn Run_Virtual_Machine(vm: *machine.State) !void {
    // delay measures, in milliseconds
    const wait_per_instruction = 500;
    const wait_per_nop = 1000;

    // debug mode specific data
    var debug_metadata_contents = false;

    const log_operation_instruction: bool = true;
    const log_operation_sideeffects: bool = true;
    var quit = false;
    while (!quit) {
        std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(wait_per_instruction));

        if (vm.rom[vm.program_counter] == @intFromEnum(specs.Opcode.DEBUG_METADATA_SIGNAL))
            debug_metadata_contents = !debug_metadata_contents;

        const opcode_enum: specs.Opcode = @enumFromInt(vm.rom[vm.program_counter]);
        if (log_operation_instruction) {
            std.debug.print("Instruction: {s}\n", .{std.enums.tagName(specs.Opcode, opcode_enum).?});
        }
        switch (opcode_enum) {
            .PANIC => {
                // useful when fill_byte is set to zero
                std.debug.print("Attempted to execute a null byte!\n", .{});
                quit = true;
            },
            .SYSTEMCALL => {
                // TODO
                std.debug.print("Syscall! implement me dumbass!\n", .{});
            },
            .BRK => {
                // graciously exit
                std.debug.print("Execution complete.\n", .{});
                quit = true;
            },
            .NOP => {
                // NOPs in the debugger trigger delays
                std.Thread.sleep(utils.Milliseconds_To_Nanoseconds(wait_per_nop));
            },
            .CLC => {
                // clear carry flag
                vm.carry_flag = false;
            },
            .SEC => {
                // set carry flag
                vm.carry_flag = true;
            },
            .RET => {
                // only instruction capable of returning from subroutines
                try vm.Return_From_Subroutine();
            },
            .LDA_LIT => {
                // get literal from following ROM bytes, then put it in the accumulator
                const literal: u32 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                if (log_operation_sideeffects)
                    std.debug.print("Before loading \"{}\":\nA = {}\n", .{ literal, vm.accumulator });
                vm.Load_Value_Into_Reg(literal, &vm.accumulator);
                if (log_operation_sideeffects)
                    std.debug.print("After loading \"{}\":\nA = {}\n", .{ literal, vm.accumulator });
            },
            .LDX_LIT => {
                // get literal from following ROM bytes, then put it in the x index
                const literal: u32 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                vm.Load_Value_Into_Reg(literal, &vm.x_index);
            },
            .LDY_LIT => {
                // get literal from following ROM bytes, then put it in the y index
                const literal: u32 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                vm.Load_Value_Into_Reg(literal, &vm.y_index);
            },
            .LDA_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the accumulator
                const address: u16 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.Load_Value_Into_Reg(address_contents, &vm.accumulator);
            },
            .LDX_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the x index
                const address: u16 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.Load_Value_Into_Reg(address_contents, &vm.x_index);
            },
            .LDY_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the y index
                const address: u16 = try machine.State.Read_Address_Contents_As(&vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(&vm.wram, address, u32);
                vm.Load_Value_Into_Reg(address_contents, &vm.y_index);
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
    }
}
