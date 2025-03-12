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

// TODO: instructions change flag bits
// TODO: unit tests
// TODO: loading and storing

pub const State = struct {
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
    carry_flag: u1,
    zero_flag: u1,
    overflow_flag: u1,

    /// fill determines the byte that will fill the vacant empty space,
    /// put null for it so stay undefined.
    pub fn Init(rom_file: std.fs.File, fill: ?u8) State {
        var machine = State{};
        // only variable harcoded to start at a given value
        machine.stack_pointer = specs.stack_address_space - 1;
        // if a fill byte was provided
        if (fill) |fill_byte| {
            @memset(machine.rom, fill_byte);
            @memset(machine.wram, fill_byte);
            @memset(machine.stack, fill_byte);
            machine.accumulator = fill_byte;
            machine.x_index = fill_byte;
            machine.y_index = fill_byte;
        }
        // load rom into memory
        const rom_file_size = rom_file.getEndPos() catch @panic("fileseek error!");
        if (rom_file_size >= specs.rom_address_space) @panic("ROM file larger than 0xFFFF bytes!");
        rom_file.readAll(machine.rom) catch @panic("failed to read ROM file!");
        return machine;
    }

    /// pushes generic value to the stack
    pub fn Push_To_Stack(this: *State, comptime T: type, value: T) !void {
        if (this.stack_pointer > @sizeOf(T))
            return error.StackOverflow;
        this.stack_pointer -= @sizeOf(T);
        std.mem.writeInt(T, this.stack[this.stack_pointer..], value, .little);
    }

    /// pops generic value from the stack
    pub fn Pop_From_Stack(this: *State, comptime T: type) !T {
        if ((this.stack_pointer + @sizeOf(T)) >= specs.stack_address_space)
            return error.StackUnderflow;
        const popped_value: T = std.mem.readInt(T, this.stack[this.stack_pointer..], .little);
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
        const skip_amount = specs.opcode_bytelen + specs.address_bytelen;
        Push_To_Stack(this, u16, this.program_counter + skip_amount);
        Jump_To_Subroutine(this, address);
    }

    /// activated through the RET instruction
    pub fn Return_From_Subroutine(this: *State) !void {
        this.program_counter = try Pop_From_Stack(this, u16);
    }
};
