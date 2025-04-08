//=============================================================//
//                                                             //
//                          MACHINE                            //
//                                                             //
//   Defines the machine state struct as well as the primitive //
//  operations available.                                      //
//                                                             //
//=============================================================//

const std = @import("std");
const builtin = @import("builtin");
const specs = @import("specifications.zig");
const utils = @import("utils.zig");

// TODO: instructions change flag bits
// TODO: unit tests
// TODO: loading and storing

pub const VirtualMachine = struct {
    /// Only meant to be used for debugging and disassembly purposes,
    /// the actual machine is not meant to know it's own size!
    original_rom_filesize: usize,

    /// hold the byte stride for indexing instructions
    index_byte_stride: u8,

    /// Read Only Memory, where the instruction data is stored.
    rom: [specs.rom_address_space]u8,
    /// Work Random Access Memory, writable memory freely available for manipulation.
    wram: [specs.wram_address_space]u8,
    /// Stack, starts at the top and grows downwards.
    stack: [specs.stack_address_space]u8,

    /// cpu registers
    accumulator: u32,
    x_index: u32,
    y_index: u32,
    program_counter: u16,
    stack_pointer: u16,

    /// processor flags
    carry_flag: bool,
    zero_flag: bool,
    overflow_flag: bool,

    /// fill determines the byte that will fill the vacant empty space,
    /// put null for it so stay undefined.
    /// only use null rom_file parameter for testing purposes
    pub fn Init(rom_filepath: ?[]const u8, fill: ?u8) VirtualMachine {
        var machine: VirtualMachine = undefined;
        // only variable harcoded to start at a given value
        machine.stack_pointer = specs.stack_address_space - 1;
        // if a fill byte was provided
        if (fill) |fill_byte| {
            @memset(&machine.rom, fill_byte);
            @memset(&machine.wram, fill_byte);
            @memset(&machine.stack, fill_byte);
            machine.index_byte_stride = fill_byte;
            machine.accumulator = fill_byte;
            machine.x_index = fill_byte;
            machine.y_index = fill_byte;
        }
        // load rom into memory
        if (rom_filepath) |filepath| {
            var filestream = std.fs.cwd().openFile(filepath, .{ .mode = .read_only }) catch
                @panic("failed to open file!");
            const rom_file_size = filestream.getEndPos() catch
                @panic("fileseek error!");
            if (rom_file_size >= (specs.rom_address_space - 1))
                @panic("ROM file larger than 0xFFFF bytes!");
            _ = filestream.readAll(&machine.rom) catch
                @panic("failed to read ROM file!");
            machine.original_rom_filesize = rom_file_size;
        }
        return machine;
    }

    /// expects input memory slice to be of size [0xFFFF + 1]u8
    /// cannot fail, wrap behavior is well defined
    /// further documentation in assembly standards (src/shared/README.md)
    pub fn Read_Address_Contents_As(memory: *const [0x10000]u8, address: u16, comptime T: type) T {
        var result_bytes: [@sizeOf(T)]u8 = undefined;
        var wrapped_index: u16 = address;
        for (0..result_bytes.len) |i| {
            result_bytes[i] = memory[wrapped_index];
            wrapped_index +%= 1;
        }
        return std.mem.readInt(T, &result_bytes, .little);
    }

    /// expects input memory slice to be of size [0xFFFF + 1]u8
    /// cannot fail, wrap behavior is well defined
    /// further documentation in assembly standards (src/shared/README.md)
    pub fn Write_Contents_Into_Memory_As(memory: *[0x10000]u8, address: u16, comptime T: type, value: T) void {
        const value_as_bytes: [@sizeOf(T)]u8 = std.mem.toBytes(value);
        var wrapped_index: u16 = address;
        for (0..value_as_bytes.len) |i| {
            memory[wrapped_index] = value_as_bytes[i];
            wrapped_index +%= 1;
        }
    }

    /// pushes generic value to the stack
    pub fn Push_To_Stack(this: *VirtualMachine, comptime T: type, value: T) !void {
        if (this.stack_pointer < @sizeOf(T))
            return error.StackOverflow;

        this.stack_pointer -= @sizeOf(T);
        const value_as_bytes: [@sizeOf(T)]u8 = std.mem.toBytes(value);
        std.mem.copyForwards(u8, this.stack[this.stack_pointer..], &value_as_bytes);
    }

    /// pops generic value from the stack
    pub fn Pop_From_Stack(this: *VirtualMachine, comptime T: type) !T {
        if ((this.stack_pointer + @sizeOf(T)) >= specs.stack_address_space)
            return error.StackUnderflow;

        const popped_value: T = std.mem.readVarInt(T, this.stack[this.stack_pointer .. this.stack_pointer + @sizeOf(T)], .little);
        this.stack_pointer += @sizeOf(T);
        return popped_value;
    }

    /// go to rom address
    pub fn Jump_To_Address(this: *VirtualMachine, address: u16) void {
        this.program_counter = address;
    }

    /// save current position to the stack, then go to rom address
    pub fn Jump_To_Subroutine(this: *VirtualMachine, address: u16) !void {
        // only save the rom address of *the next* instruction
        // harcoded to the "JSR $ADDR" opcode syntax
        const skip_amount = specs.opcode_bytelen + specs.address_bytelen;
        Push_To_Stack(this, u16, this.program_counter + skip_amount);
        Jump_To_Address(this, address);
    }

    /// activated through the RET instruction
    pub fn Return_From_Subroutine(this: *VirtualMachine) !void {
        this.program_counter = try Pop_From_Stack(this, u16);
    }

    /// sets reg to the input value
    pub fn Load_Value_Into_Reg(this: *VirtualMachine, value: u32, reg: *u32) void {
        _ = this; // processor flags modifications to be implemented later
        reg.* = value;
    }

    /// "Transfer" is a misnomer, all this does is sets reg1 to the value of reg2
    pub fn Transfer_Registers(this: *VirtualMachine, reg1: *u32, reg2: *const u32) void {
        _ = this; // processor flags modifications to be implemented later
        reg1.* = reg2.*;
    }

    /// adds two 32-bit values and modifies the processor flags accordingly
    /// cannot fail, wrap behavior is well defined
    /// further documentation in assembly standards (src/shared/README.md)
    pub fn Add(this: *VirtualMachine, a: u32, b: u32) u32 {
        const result, const overflow = @addWithOverflow(a, b);

        // TODO: accurate flag modifications to be decided
        this.carry_flag = utils.Int_To_Bool(overflow);
        this.zero_flag = (result == 0);
        return result;
    }

    /// subtracts two 32-bit values and modifies the processor flags accordingly
    /// cannot fail, wrap behavior is well defined
    /// further documentation in assembly standards (src/shared/README.md)
    pub fn Subtract(this: *VirtualMachine, a: u32, b: u32) u32 {
        const result, const underflow = @subWithOverflow(a, b);

        // TODO: accurate flag modifications to be decided
        this.overflow_flag = utils.Int_To_Bool(underflow);
        this.zero_flag = (result == 0);
        return result;
    }
};

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "Reading from ROM or WRAM" {
    var mem: [specs.rom_address_space]u8 = undefined;
    mem[0x0000] = 0x00;
    mem[0x0001] = 0x01;
    mem[0x0002] = 0x02;
    mem[0x0003] = 0x03;
    mem[0x0004] = 0x04;
    mem[0xFFFB] = 0xFB;
    mem[0xFFFC] = 0xFC;
    mem[0xFFFD] = 0xFD;
    mem[0xFFFE] = 0xFE;
    mem[0xFFFF] = 0xFF;

    try std.testing.expectEqual(0xFEFDFCFB, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFB, u32));
    try std.testing.expectEqual(0xFFFEFDFC, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFC, u32));
    try std.testing.expectEqual(0x00FFFEFD, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFD, u32));
    try std.testing.expectEqual(0x0100FFFE, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFE, u32));
    try std.testing.expectEqual(0x020100FF, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFF, u32));
    try std.testing.expectEqual(0x03020100, VirtualMachine.Read_Address_Contents_As(&mem, 0x0000, u32));
    try std.testing.expectEqual(0x04030201, VirtualMachine.Read_Address_Contents_As(&mem, 0x0001, u32));
}

test "Writing to ROM or WRAM" {
    var mem: [specs.rom_address_space]u8 = undefined;

    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0xFFFB, u32, 0xFEFDFCFB);
    try std.testing.expectEqual(0xFEFDFCFB, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFB, u32));
    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0xFFFC, u32, 0xFFFEFDFC);
    try std.testing.expectEqual(0xFFFEFDFC, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFC, u32));
    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0xFFFD, u32, 0x00FFFEFD);
    try std.testing.expectEqual(0x00FFFEFD, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFD, u32));
    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0xFFFE, u32, 0x0100FFFE);
    try std.testing.expectEqual(0x0100FFFE, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFE, u32));
    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0xFFFF, u32, 0x020100FF);
    try std.testing.expectEqual(0x020100FF, VirtualMachine.Read_Address_Contents_As(&mem, 0xFFFF, u32));
    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0x0000, u32, 0x03020100);
    try std.testing.expectEqual(0x03020100, VirtualMachine.Read_Address_Contents_As(&mem, 0x0000, u32));
    VirtualMachine.Write_Contents_Into_Memory_As(&mem, 0x0001, u32, 0x04030201);
    try std.testing.expectEqual(0x04030201, VirtualMachine.Read_Address_Contents_As(&mem, 0x0001, u32));
}

test "Live VM tests" {
    var vm = VirtualMachine.Init(null, 0x00);
    var result: u32 = undefined;

    // straight jumping
    vm.Jump_To_Address(0x0100);
    try std.testing.expectEqual(0x0100, vm.program_counter);

    // stack pushing and popping
    try vm.Push_To_Stack(u16, 0xF001);
    try vm.Push_To_Stack(u16, 0xF002);
    try vm.Push_To_Stack(u16, 0xF003);
    try vm.Push_To_Stack(u16, 0xF004);
    try vm.Push_To_Stack(u64, 0x0011223344556677);
    try vm.Push_To_Stack(u16, 0xF005);
    try std.testing.expectEqual(0xF005, try vm.Pop_From_Stack(u16));
    try std.testing.expectEqual(0x0011223344556677, try vm.Pop_From_Stack(u64));
    try std.testing.expectEqual(0xF004, try vm.Pop_From_Stack(u16));
    try std.testing.expectEqual(0xF003, try vm.Pop_From_Stack(u16));
    try std.testing.expectEqual(0xF002, try vm.Pop_From_Stack(u16));
    try std.testing.expectEqual(0xF001, try vm.Pop_From_Stack(u16));

    // addition
    result = vm.Add(0xFFFFFFFF, 1);
    try std.testing.expectEqual(0x00000000, result);
    try std.testing.expectEqual(true, vm.carry_flag);
    try std.testing.expectEqual(true, vm.zero_flag);
    result = vm.Add(0x69, 0x42);
    try std.testing.expectEqual(0x000000AB, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    result = vm.Add(0, 0);
    try std.testing.expectEqual(0x00000000, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(true, vm.zero_flag);

    // subtraction
    result = vm.Subtract(0x00000000, 1);
    try std.testing.expectEqual(0xFFFFFFFF, result);
    try std.testing.expectEqual(true, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    result = vm.Subtract(0x69, 0x42);
    try std.testing.expectEqual(0x00000027, result);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    result = vm.Subtract(0, 0);
    try std.testing.expectEqual(0x00000000, result);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(true, vm.zero_flag);
}
