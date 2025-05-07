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
const warn = @import("warning.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const stdin = std.io.getStdIn().reader();

pub const VMerror = error{
    BadSyscall,
    StackUnderflow,
    StackOverflow,
    RomFileNotFound,
    RomFileTooBig,
    BadFile,
};

pub fn Output_Error_Message(err: VMerror) void {
    switch (err) {
        VMerror.BadSyscall => warn.Fatal_Error_Message("Executed a bad syscall!", .{}),
        VMerror.StackOverflow => warn.Fatal_Error_Message("Stack overflowed!", .{}),
        VMerror.StackUnderflow => warn.Fatal_Error_Message("Stack underflowed!", .{}),
        VMerror.RomFileNotFound => warn.Fatal_Error_Message("Rom file not found!", .{}),
        VMerror.RomFileTooBig => warn.Fatal_Error_Message("Rom file too big!", .{}),
        VMerror.BadFile => warn.Fatal_Error_Message("Bad rom file!", .{}),
    }
}

pub const VirtualMachine = struct {
    /// Only meant to be used for debugging and disassembly purposes,
    /// the actual machine is not meant to know its own size!
    original_rom_filesize: usize,

    /// byte stride for indexing instructions
    index_byte_stride: u8,

    /// Read Only Memory, where the instruction data is stored.
    rom: [specs.bytelen.rom]u8,
    /// Work Random Access Memory, writable memory freely available for manipulation.
    wram: [specs.bytelen.wram]u8,
    /// Stack, starts at the top and grows downwards.
    stack: [specs.bytelen.stack]u8,

    /// cpu registers
    accumulator: u32,
    x_index: u32,
    y_index: u32,
    program_counter: u16,
    stack_pointer: u16,

    /// processor flags
    carry_flag: bool,
    zero_flag: bool,
    negative_flag: bool,
    overflow_flag: bool,

    /// fill determines the byte that will fill the vacant empty space,
    /// put null for it so stay undefined.
    /// only use null rom_file parameter for testing purposes
    pub fn Init(rom_filepath: ?[]const u8, fill: ?u8) VMerror!VirtualMachine {
        var machine: VirtualMachine = undefined;
        // only variable harcoded to start at a given value
        machine.stack_pointer = specs.bytelen.stack - 1;
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
            var filestream = std.fs.cwd().openFile(filepath, .{ .mode = .read_only }) catch |err| {
                return switch (err) {
                    std.fs.File.OpenError.FileNotFound => VMerror.RomFileNotFound,
                    else => VMerror.BadFile,
                };
            };
            const rom_file_size = filestream.getEndPos() catch
                return VMerror.BadFile;
            if (rom_file_size >= (specs.bytelen.rom - 1))
                return VMerror.RomFileTooBig;
            _ = filestream.readAll(&machine.rom) catch
                return VMerror.BadFile;
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
    pub fn Push_To_Stack(this: *VirtualMachine, comptime T: type, value: T) VMerror!void {
        if (this.stack_pointer < @sizeOf(T))
            return error.StackOverflow;
        this.stack_pointer -= @sizeOf(T);
        const value_as_bytes: [@sizeOf(T)]u8 = std.mem.toBytes(value);
        std.mem.copyForwards(u8, this.stack[this.stack_pointer..], &value_as_bytes);
    }

    /// pops generic value from the stack
    pub fn Pop_From_Stack(this: *VirtualMachine, comptime T: type) VMerror!T {
        if ((this.stack_pointer + @sizeOf(T)) >= specs.bytelen.stack)
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
    pub fn Jump_To_Subroutine(this: *VirtualMachine, address: u16) VMerror!void {
        // only save the rom address of *the next* instruction
        // harcoded to the "JSR $ADDR" opcode syntax
        const skip_amount = specs.bytelen.opcode + specs.bytelen.address;
        try Push_To_Stack(this, u16, this.program_counter + skip_amount);
        Jump_To_Address(this, address);
    }

    /// activated through the RET instruction
    pub fn Return_From_Subroutine(this: *VirtualMachine) !void {
        this.program_counter = try Pop_From_Stack(this, u16);
    }

    /// sets reg to the input value
    pub fn Load_Value_Into_Reg(this: *VirtualMachine, value: u32, reg: *u32) void {
        reg.* = value;
        this.zero_flag = (value == 0);
    }

    /// "Transfer" is a misnomer, all this does is sets reg1 to the value of reg2
    pub fn Transfer_Registers(this: *VirtualMachine, reg1: *u32, reg2: *const u32) void {
        reg1.* = reg2.*;
        this.zero_flag = (reg2.* == 0);
    }

    /// signed add with carry two 32-bit values
    /// cannot fail, wrap behavior is well defined
    /// further documentation in assembly standards (src/shared/README.md)
    pub fn Add_With_Carry(this: *VirtualMachine, a: u32, b: u32, carry: u1) u32 {
        // result = a + b + carry
        var result, const overflow_1 = @addWithOverflow(a, b);
        result, const overflow_2 = @addWithOverflow(result, carry);
        this.carry_flag = utils.Int_To_Bool(overflow_1) or utils.Int_To_Bool(overflow_2);
        this.overflow_flag = Check_Overflow(a, b, result);
        this.negative_flag = Check_Sign(result);
        this.zero_flag = (result == 0);
        return result;
    }

    /// signed subtract with carry two 32-bit values
    /// cannot fail, wrap behavior is well defined
    /// further documentation in assembly standards (src/shared/README.md)
    pub fn Sub_With_Carry(this: *VirtualMachine, a: u32, b: u32, carry: u1) u32 {
        // result = a - b + (1 - carry)
        const result, const overflow = @subWithOverflow(a, b +% (1 - carry));
        const neg_b: u32 = @bitCast(std.math.negate(@as(i32, @bitCast(b))) catch unreachable);
        this.carry_flag = utils.Int_To_Bool(overflow);
        this.overflow_flag = Check_Overflow(a, neg_b, result);
        this.negative_flag = Check_Sign(result);
        this.zero_flag = (result == 0);
        return result;
    }

    /// set carry flag to 1
    pub fn Set_Carry_Flag(this: *VirtualMachine) void {
        this.carry_flag = true;
    }

    /// set carry flag to 0
    pub fn Clear_Carry_Flag(this: *VirtualMachine) void {
        this.carry_flag = false;
    }

    /// returns true if negative
    /// returns false if positive
    pub fn Check_Sign(n: u32) bool {
        return (n & 0x80000000 != 0);
    }

    /// if A and B are of the same sign and results in a different sign after an
    /// arithmetic operation, an overflow has occured
    pub fn Check_Overflow(a: u32, b: u32, result: u32) bool {
        const a_sign = Check_Sign(a);
        const b_sign = Check_Sign(b);
        const c_sign = Check_Sign(result);

        if (a_sign != b_sign) {
            return false;
        }
        if (a_sign == c_sign and b_sign == c_sign) {
            return false;
        }

        return true;
    }

    /// set overflow flag to 1
    pub fn Set_Overflow_Flag(this: *VirtualMachine) void {
        this.overflow_flag = true;
    }

    /// set overflow flag to 0
    pub fn Clear_Overflow_Flag(this: *VirtualMachine) void {
        this.overflow_flag = false;
    }

    /// just a subtraction operation under the hood, result is discarded
    /// only flags are modified
    pub fn Compare(this: *VirtualMachine, a: u32, b: u32) void {
        _ = this.Sub_With_Carry(a, b, 1);
    }

    /// branching functions namespace
    /// returns true if jump occured, false if not
    pub const BranchIf = enum {
        /// BCS instruction
        pub fn Carry_Set(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.carry_flag == true);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BCC instruction
        pub fn Carry_Clear(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.carry_flag == false);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BEQ instruction
        pub fn Zero_Set(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.zero_flag == true);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BNE instruction
        pub fn Zero_Clear(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.zero_flag == false);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BMI instruction
        pub fn Negative_Set(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.negative_flag == true);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BPL instruction
        pub fn Negative_Clear(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.negative_flag == false);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BVS instruction
        pub fn Overflow_Set(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.overflow_flag == true);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
        /// BVC instruction
        pub fn Overflow_Clear(this: *VirtualMachine, addr: u16) bool {
            const cond = (this.overflow_flag == false);
            if (cond) this.Jump_To_Address(addr);
            return cond;
        }
    };

    /// Accumulator = syscall code
    /// X index = first argument
    /// Y index = second argument
    pub fn Syscall(this: *VirtualMachine) VMerror!void {
        const syscall_code: u8 = @truncate(this.accumulator);
        const syscall_enum: specs.SyscallCode = @enumFromInt(syscall_code);
        switch (syscall_enum) {
            .PRINT_ROM_STR => {
                const start: u16 = @truncate(this.x_index);
                const maybe_end: ?usize = std.mem.indexOfScalar(u8, this.rom[start..], 0);
                if (maybe_end == null) {
                    warn.Error_Message("could not find end of ROM string!", .{});
                    return error.BadSyscall;
                }
                const end: u16 = start + (@as(u16, @truncate(maybe_end.?)));
                const string: []const u8 = this.rom[start..end];
                _ = stdout.print("{s}", .{string}) catch unreachable;
            },
            .PRINT_WRAM_STR => {
                const start: u16 = @truncate(this.x_index);
                const maybe_end: ?usize = std.mem.indexOfScalar(u8, this.wram[start..], 0);
                if (maybe_end == null) {
                    warn.Error_Message("could not find end of WRAM string!", .{});
                    return error.BadSyscall;
                }
                const end: u16 = start + (@as(u16, @truncate(maybe_end.?)));
                const string: []const u8 = this.wram[start..end];
                _ = stdout.print("{s}", .{string}) catch unreachable;
            },
            .PRINT_NEWLINES => {
                const n: u8 = @truncate(this.x_index);
                for (0..n) |_| {
                    _ = stdout.print("\n", .{}) catch unreachable;
                }
            },
            .PRINT_CHAR => {
                const character: u8 = @truncate(this.x_index);
                if (std.ascii.isASCII(character) == false) {
                    _ = stdout.print("?", .{}) catch unreachable;
                } else {
                    _ = stdout.print("{c}", .{character}) catch unreachable;
                }
            },
            .PRINT_DEC_INT => {
                const integer: i32 = @bitCast(this.x_index);
                _ = stdout.print("{}", .{integer}) catch unreachable;
            },
            .PRINT_HEX_INT => {
                const integer: u32 = this.x_index;
                _ = stdout.print("0x{X:0>8}", .{integer}) catch unreachable;
            },
            _ => return error.BadSyscall,
        }
    }
};

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "Reading from ROM or WRAM" {
    var mem: [specs.bytelen.rom]u8 = undefined;
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
    var mem: [specs.bytelen.rom]u8 = undefined;

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

test "Live VM testing" {
    var vm = try VirtualMachine.Init(null, 0x00);

    // straight jumping
    vm.Jump_To_Address(0x1337);
    try std.testing.expectEqual(0x1337, vm.program_counter);

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
}

test "Comparing and branching" {
    var vm = try VirtualMachine.Init(null, 0x00);

    vm.Compare(42, 42);
    // (A - B == 0) for BEQ and BNE
    try std.testing.expectEqual(true, vm.zero_flag);
    // (A - B < 0) for BMI and BPL
    try std.testing.expectEqual(false, vm.negative_flag);
    // (A - B -> overflow) for BVS and BVC
    try std.testing.expectEqual(false, vm.overflow_flag);
}

test "Arithmetic and flag modifications" {
    var vm = try VirtualMachine.Init(null, 0x00);
    var result: u32 = undefined;

    // signed two's complement 32-bit addition
    // (0) + (0) = 0
    result = vm.Add_With_Carry(0x00000000, 0x00000000, 0);
    try std.testing.expectEqual(0, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(true, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (1) + (0) = 1
    result = vm.Add_With_Carry(0x00000001, 0x00000000, 0);
    try std.testing.expectEqual(1, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (0) + (1) = 1
    result = vm.Add_With_Carry(0x00000000, 0x00000001, 0);
    try std.testing.expectEqual(1, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (1) + (1) = 2
    result = vm.Add_With_Carry(0x00000001, 0x00000001, 0);
    try std.testing.expectEqual(2, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (-1) + (0) = -1
    result = vm.Add_With_Carry(0xFFFFFFFF, 0x00000000, 0);
    try std.testing.expectEqual(0xFFFFFFFF, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(true, vm.negative_flag);
    // (0) + (-1) = -1
    result = vm.Add_With_Carry(0x00000000, 0xFFFFFFFF, 0);
    try std.testing.expectEqual(0xFFFFFFFF, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(true, vm.negative_flag);
    // (-1) + (1) = 0
    result = vm.Add_With_Carry(0xFFFFFFFF, 0x00000001, 0);
    try std.testing.expectEqual(0x00000000, result);
    try std.testing.expectEqual(true, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(true, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (2147483647) + (1) = -2147483648 <signed integer overflow>
    result = vm.Add_With_Carry(0x7FFFFFFF, 0x00000001, 0);
    try std.testing.expectEqual(0x80000000, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(true, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(true, vm.negative_flag);

    // signed two's complement 32-bit subtraction
    // (0) - (0) = 0
    result = vm.Sub_With_Carry(0x00000000, 0x00000000, 1);
    try std.testing.expectEqual(0x00000000, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(true, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (1) - (0) = 1
    result = vm.Sub_With_Carry(0x00000001, 0x00000000, 1);
    try std.testing.expectEqual(0x00000001, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (0) - (1) = -1
    result = vm.Sub_With_Carry(0x00000000, 0x00000001, 1);
    try std.testing.expectEqual(0xFFFFFFFF, result);
    try std.testing.expectEqual(true, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(true, vm.negative_flag);
    // (1) - (1) = 0
    result = vm.Sub_With_Carry(0x00000001, 0x00000001, 1);
    try std.testing.expectEqual(0x00000000, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(true, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (-1) - (0) = -1
    result = vm.Sub_With_Carry(0xFFFFFFFF, 0x00000000, 1);
    try std.testing.expectEqual(0xFFFFFFFF, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(true, vm.negative_flag);
    // (0) - (-1) = 1
    result = vm.Sub_With_Carry(0x00000000, 0xFFFFFFFF, 1);
    try std.testing.expectEqual(0x00000001, result);
    try std.testing.expectEqual(true, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
    // (-1) - (1) = -2
    result = vm.Sub_With_Carry(0xFFFFFFFF, 0x00000001, 1);
    try std.testing.expectEqual(0xFFFFFFFE, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(false, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(true, vm.negative_flag);
    // (-2147483648) - (1) = 2147483647 <signed integer overflow>
    result = vm.Sub_With_Carry(0x80000000, 0x00000001, 1);
    try std.testing.expectEqual(0x7FFFFFFF, result);
    try std.testing.expectEqual(false, vm.carry_flag);
    try std.testing.expectEqual(true, vm.overflow_flag);
    try std.testing.expectEqual(false, vm.zero_flag);
    try std.testing.expectEqual(false, vm.negative_flag);
}
