//=============================================================//
//                                                             //
//                          MACHINE                            //
//                                                             //
//   Defines the machine state struct as well as the primitive //
//  operations available.                                      //
//                                                             //
//=============================================================//

const std = @import("std");
const specs = @import("specifications.zig");
const utils = @import("utils.zig");

// TODO: instructions change flag bits
// TODO: unit tests
// TODO: loading and storing

pub const State = struct {
    /// Only meant to be used for debugging and disassembly purposes,
    /// the actual machine is not meant to know it's own size!
    original_rom_filesize: usize,

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
    pub fn Init(rom_filepath: ?[]const u8, fill: ?u8) State {
        var machine: State = undefined;
        // only variable harcoded to start at a given value
        machine.stack_pointer = specs.stack_address_space - 1;
        // if a fill byte was provided
        if (fill) |fill_byte| {
            @memset(&machine.rom, fill_byte);
            @memset(&machine.wram, fill_byte);
            @memset(&machine.stack, fill_byte);
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

    /// may fail with error.ReadOutOfBoundsMemory
    pub fn Read_Address_Contents_As(memory: []const u8, address: u16, comptime T: type) !T {
        // Helper function for reading little endian ints from memory, example:
        //```
        //   ROM   -  VAL
        // $0x0000 - 0x00
        // $0x0001 - 0x00
        // $0x0002 - 0x11
        // $0x0003 - 0x22
        // $0x0004 - 0x33
        // $0x0005 - 0x44
        // $0x0006 - 0x00
        // $0x0007 - 0x00
        //```
        // fn(&rom, $0x0002, u32) returns 0x44332211
        // fn(&rom, $0x0003, u16) returns 0x3322
        if ((address + @sizeOf(T)) > memory.len)
            return error.ReadOutOfBoundsMemory;
        return std.mem.readVarInt(T, memory[address .. address + @sizeOf(T)], .little);
    }

    /// may fail with error.WriteIntoOutOfBoundsMemory
    pub fn Write_Contents_Into_Memory_As(memory: []u8, address: u16, comptime T: type, value: T) !void {
        // Helper function for writing little endian ints into memory, example:
        //```
        //   ROM   -  VAL
        // $0x0000 - 0x00
        // $0x0001 - 0x00
        // $0x0002 - 0x00
        // $0x0003 - 0x00
        // $0x0004 - 0x00
        // $0x0005 - 0x00
        // $0x0006 - 0x00
        // $0x0007 - 0x00
        //```
        // fn(&rom, $0x0002, u32, 0x44332211) modifies the memory to:
        //```
        // $0x0000 - 0x00
        // $0x0001 - 0x00
        // $0x0002 - 0x11
        // $0x0003 - 0x22
        // $0x0004 - 0x33
        // $0x0005 - 0x44
        // $0x0006 - 0x00
        // $0x0007 - 0x00
        //```
        if ((address + @sizeOf(T)) > memory.len)
            return error.WriteIntoOutOfBoundsMemory;
        // stinky hack since writeVarInt doesn't exist...
        @memcpy(memory[address .. address + @sizeOf(T)], &std.mem.toBytes(std.mem.nativeToLittle(T, value)));
    }

    /// pushes generic value to the stack
    pub fn Push_To_Stack(this: *State, comptime T: type, value: T) !void {
        if (this.stack_pointer > @sizeOf(T))
            return error.StackOverflow;
        this.stack_pointer -= @sizeOf(T);
        Write_Contents_Into_Memory_As(this.stack, this.stack_pointer, T, value);
    }

    /// pops generic value from the stack
    pub fn Pop_From_Stack(this: *State, comptime T: type) !T {
        if ((this.stack_pointer + @sizeOf(T)) >= specs.stack_address_space)
            return error.StackUnderflow;
        const popped_value: T = try Read_Address_Contents_As(&this.stack, this.stack_pointer, T);
        this.stack_pointer += @sizeOf(T);
        return popped_value;
    }

    /// go to rom address
    pub fn Jump_To_Address(this: *State, address: u16) void {
        this.program_counter = address;
    }

    /// save current position to the stack, then go to rom address
    pub fn Jump_To_Subroutine(this: *State, address: u16) !void {
        // only save the rom address of *the next* instruction
        // harcoded to the "JSR $ADDR" opcode syntax
        const skip_amount = specs.opcode_bytelen + specs.address_bytelen;
        Push_To_Stack(this, u16, this.program_counter + skip_amount);
        Jump_To_Address(this, address);
    }

    /// activated through the RET instruction
    pub fn Return_From_Subroutine(this: *State) !void {
        this.program_counter = try Pop_From_Stack(this, u16);
    }

    /// sets reg to the input value
    pub fn Load_Value_Into_Reg(this: *State, value: u32, reg: *u32) void {
        _ = this; // processor flags modifications to be implemented later
        reg.* = value;
    }

    /// "Transfer" is a misnomer, all this does is set reg1 to the value of reg2
    pub fn Transfer_Registers(this: *State, reg1: *u32, reg2: *const u32) void {
        _ = this; // processor flags modifications to be implemented later
        reg1.* = reg2.*;
    }

    /// add two 32-bit values and modifies the processor flags accordingly
    /// standard overflow behavior:
    /// 0xFFFFFFFF + 1 = 0x00000000
    pub fn Add(this: *State, a: u32, b: u32) u32 {
        const result, const overflow = @addWithOverflow(a, b);

        // TODO: accurate flag modifications to be decided
        this.carry_flag = utils.Int_To_Bool(overflow);
        this.zero_flag = (result == 0);
        return result;
    }

    /// subtracts two 32-bit values and modifies the processor flags accordingly
    /// standard underflow behavior:
    /// 0x00000000 - 1 = 0xFFFFFFFF
    pub fn Subtract(this: *State, a: u32, b: u32) u32 {
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
test "Reading generic ints from memoryspace" {
    var mem: [8]u8 = undefined;
    mem[0] = 0x00;
    mem[1] = 0x00;
    mem[2] = 0x11;
    mem[3] = 0x22;
    mem[4] = 0x33;
    mem[5] = 0x44;
    mem[6] = 0xCC;
    mem[7] = 0xCC;

    // ok
    try std.testing.expectEqual(0x22110000, try State.Read_Address_Contents_As(&mem, 0, u32));
    try std.testing.expectEqual(0x33221100, try State.Read_Address_Contents_As(&mem, 1, u32));
    try std.testing.expectEqual(0x44332211, try State.Read_Address_Contents_As(&mem, 2, u32));
    try std.testing.expectEqual(0xCC443322, try State.Read_Address_Contents_As(&mem, 3, u32));
    try std.testing.expectEqual(0xCCCC4433, try State.Read_Address_Contents_As(&mem, 4, u32));

    // out of bounds
    try std.testing.expectError(error.ReadOutOfBoundsMemory, State.Read_Address_Contents_As(&mem, 5, u32));
    try std.testing.expectError(error.ReadOutOfBoundsMemory, State.Read_Address_Contents_As(&mem, 6, u32));
    try std.testing.expectError(error.ReadOutOfBoundsMemory, State.Read_Address_Contents_As(&mem, 7, u32));
    try std.testing.expectError(error.ReadOutOfBoundsMemory, State.Read_Address_Contents_As(&mem, 8, u32));
    try std.testing.expectError(error.ReadOutOfBoundsMemory, State.Read_Address_Contents_As(&mem, 9, u32));
}

test "Writing generic ints into memoryspace" {
    var mem: [8]u8 = .{0} ** 8;

    const cmp_32 = [4]u8{ 0x11, 0x22, 0x33, 0x44 };
    const cmp_16 = [2]u8{ 0x11, 0x22 };

    // ok
    const addr = 4;
    try State.Write_Contents_Into_Memory_As(&mem, addr, u32, 0x44332211);
    try std.testing.expectEqualSlices(u8, mem[addr .. addr + cmp_32.len], &cmp_32);
    try std.testing.expectEqualSlices(u8, mem[addr .. addr + cmp_16.len], &cmp_16);

    // out of bounds
    try std.testing.expectError(error.WriteIntoOutOfBoundsMemory, State.Write_Contents_Into_Memory_As(&mem, 5, u32, 0xFFFFFFFF));
    try std.testing.expectError(error.WriteIntoOutOfBoundsMemory, State.Write_Contents_Into_Memory_As(&mem, 6, u32, 0xFFFFFFFF));
    try std.testing.expectError(error.WriteIntoOutOfBoundsMemory, State.Write_Contents_Into_Memory_As(&mem, 7, u16, 0xFFFF));
    try std.testing.expectError(error.WriteIntoOutOfBoundsMemory, State.Write_Contents_Into_Memory_As(&mem, 8, u8, 0xFF));
    try std.testing.expectError(error.WriteIntoOutOfBoundsMemory, State.Write_Contents_Into_Memory_As(&mem, 9, u8, 0xFF));
}

test "Live VM tests" {
    var vm = State.Init(null, 0x00);

    // straight jumping
    vm.Jump_To_Address(0x0100);
    try std.testing.expectEqual(0x0100, vm.program_counter);

    var result: u32 = undefined;
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
