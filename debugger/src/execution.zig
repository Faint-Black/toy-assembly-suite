const std = @import("std");
const specs = @import("shared").specifications;
const machine = @import("shared").machine;

pub fn Run_Virtual_Machine(vm: *machine.State) !void {
    var quit = false;
    while (!quit) {
        var opcode_enum: specs.Opcode = @enumFromInt(vm.program_counter);
        switch (opcode_enum) {
            .PANIC => {
                std.debug.print("Attempted to execute a null byte!\n", .{});
                quit = true;
            },
            .SYSTEMCALL => {},
            .BRK => {
                std.debug.print("Execution complete.\n", .{});
                quit = true;
            },
            .NOP => {},
            .CLC => {},
            .SEC => {},
            .RET => {},
            .LDA_LIT => {
                // get literal from following ROM bytes, then put it in the accumulator
                const literal: u32 = try machine.State.Read_Address_Contents_As(vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                vm.Load_Value_Into_Reg(literal, vm.accumulator);
            },
            .LDX_LIT => {
                // get literal from following ROM bytes, then put it in the x index
                const literal: u32 = try machine.State.Read_Address_Contents_As(vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                vm.Load_Value_Into_Reg(literal, vm.x_index);
            },
            .LDY_LIT => {
                // get literal from following ROM bytes, then put it in the y index
                const literal: u32 = try machine.State.Read_Address_Contents_As(vm.rom, vm.program_counter + specs.opcode_bytelen, u32);
                vm.Load_Value_Into_Reg(literal, vm.y_index);
            },
            .LDA_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the accumulator
                const address: u16 = try machine.State.Read_Address_Contents_As(vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(vm.wram, address, u32);
                vm.Load_Value_Into_Reg(address_contents, vm.accumulator);
            },
            .LDX_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the x index
                const address: u16 = try machine.State.Read_Address_Contents_As(vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(vm.wram, address, u32);
                vm.Load_Value_Into_Reg(address_contents, vm.x_index);
            },
            .LDY_ADDR => {
                // get address from following ROM bytes, then fetch address contents from RAM and put it in the y index
                const address: u16 = try machine.State.Read_Address_Contents_As(vm.rom, vm.program_counter + specs.opcode_bytelen, u16);
                const address_contents: u32 = try machine.State.Read_Address_Contents_As(vm.wram, address, u32);
                vm.Load_Value_Into_Reg(address_contents, vm.y_index);
            },
            .LDA_X => {
                // a = x
                vm.Transfer_Registers(vm.accumulator, vm.x_index);
            },
            .LDA_Y => {
                // a = y
                vm.Transfer_Registers(vm.accumulator, vm.y_index);
            },
            .LDX_A => {
                // x = a
                vm.Transfer_Registers(vm.x_index, vm.accumulator);
            },
            .LDX_Y => {
                // x = y
                vm.Transfer_Registers(vm.x_index, vm.y_index);
            },
            .LDY_A => {
                // y = a
                vm.Transfer_Registers(vm.y_index, vm.accumulator);
            },
            .LDY_X => {
                // y = x
                vm.Transfer_Registers(vm.y_index, vm.x_index);
            },
            .LDA_ADDR_X => {},
            .LDA_ADDR_Y => {},
            .STA_ADDR => {},
            .STX_ADDR => {},
            .STY_ADDR => {},
            .JMP_ADDR => {},
            .JSR_ADDR => {},
            .CMP_A_X => {},
            .CMP_A_Y => {},
            .CMP_A_LIT => {},
            .CMP_A_ADDR => {},
            .CMP_X_A => {},
            .CMP_X_Y => {},
            .CMP_X_LIT => {},
            .CMP_X_ADDR => {},
            .CMP_Y_X => {},
            .CMP_Y_A => {},
            .CMP_Y_LIT => {},
            .CMP_Y_ADDR => {},
            .BCS_ADDR => {},
            .BCC_ADDR => {},
            .BEQ_ADDR => {},
            .BNE_ADDR => {},
            .BMI_ADDR => {},
            .BPL_ADDR => {},
            .BVS_ADDR => {},
            .BVC_ADDR => {},
            .ADD_LIT => {},
            .ADD_ADDR => {},
            .ADD_X => {},
            .ADD_Y => {},
            .SUB_LIT => {},
            .SUB_ADDR => {},
            .SUB_X => {},
            .SUB_Y => {},
            .INC_A => {},
            .INC_X => {},
            .INC_Y => {},
            .INC_ADDR => {},
            .DEC_A => {},
            .DEC_X => {},
            .DEC_Y => {},
            .DEC_ADDR => {},
            .PUSH_A => {},
            .PUSH_X => {},
            .PUSH_Y => {},
            .POP_A => {},
            .POP_X => {},
            .POP_Y => {},
            .DEBUG_METADATA_SIGNAL => {},
        }
    }
}
