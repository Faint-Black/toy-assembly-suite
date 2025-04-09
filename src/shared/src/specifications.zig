//=============================================================//
//                                                             //
//                   ASSEMBLY SPECIFICATIONS                   //
//                                                             //
//   Garantees the assembly's standard specifications across   //
//  all source files.                                          //
//                                                             //
//=============================================================//

const std = @import("std");

/// current toy assembly language revision
pub const current_assembly_version: u8 = 1;
// -version 1
//  All basic opcodes introduced.

/// "NOP" -> 1 byte
pub const opcode_bytelen: u8 = 1;
/// "$0x1" -> 2 bytes
pub const address_bytelen: u8 = 2;
/// "0x42" -> 4 bytes
pub const literal_bytelen: u8 = 4;
/// accumulator, X index, Y index hold a 4 byte value
pub const cpu_register_capacity: u8 = 4;

/// virtual-machine specifications
pub const rom_address_space: usize = 0xFFFF + 1;
pub const wram_address_space: usize = 0xFFFF + 1;
pub const stack_address_space: usize = 0x3FF + 1;

/// rom specifications
pub const rom_magic_number: u8 = 0x69;

/// standardized ROM header parsing
pub const Header = struct {
    pub const header_byte_size: usize = 16;
    pub const default_entry_point: u16 = header_byte_size;

    magic_number: u8,
    language_version: u8,
    entry_point: u16,
    debug_mode: bool,

    pub fn Parse_From_Byte_Array(header_bytes: [16]u8) Header {
        return Header{
            .magic_number = header_bytes[0],
            .language_version = header_bytes[1],
            .entry_point = std.mem.bytesToValue(u16, header_bytes[2..4]),
            .debug_mode = (header_bytes[15] != 0),
        };
    }

    pub fn Parse_To_Byte_Array(self: Header) [16]u8 {
        var result_header: [0x10]u8 = .{@as(u8, 0xCC)} ** 16;
        result_header[0x0] = self.magic_number;
        result_header[0x1] = self.language_version;
        result_header[0x2] = std.mem.toBytes(self.entry_point)[0];
        result_header[0x3] = std.mem.toBytes(self.entry_point)[1];
        result_header[0xF] = @intFromBool(self.debug_mode);
        return result_header;
    }
};

pub const AddressSpace = enum {
    not_applicable,
    rom,
    wram,
    stack,
};

/// "MNEMONIC_ARG1_ARG2"
pub const Opcode = enum(u8) {
    // Exit immediately upon trying to execute a null byte as an instruction
    PANIC = 0x00,
    // behavior depends entirely on virtual machine implementation,
    // although the below usage of the registers is mandatory
    // CODE = A
    // ARG1 = X
    // ARG2 = Y
    SYSTEMCALL,
    // Define index instructions byte stride
    STRIDE_LIT,
    // No argument opcodes
    BRK,
    NOP,
    CLC,
    SEC,
    RET,
    // Loading literals into the register
    LDA_LIT,
    LDX_LIT,
    LDY_LIT,
    // Loading values from addresses
    LDA_ADDR,
    LDX_ADDR,
    LDY_ADDR,
    // Register transfering
    LDA_X,
    LDA_Y,
    LDX_A,
    LDX_Y,
    LDY_A,
    LDY_X,
    // Indexed dereferencing
    LDA_ADDR_X,
    LDA_ADDR_Y,
    // Storing values into addresses
    STA_ADDR,
    STX_ADDR,
    STY_ADDR,
    // Jumping
    JMP_ADDR,
    JSR_ADDR,
    // Comparing
    CMP_A_X,
    CMP_A_Y,
    CMP_A_LIT,
    CMP_A_ADDR,
    CMP_X_A,
    CMP_X_Y,
    CMP_X_LIT,
    CMP_X_ADDR,
    CMP_Y_X,
    CMP_Y_A,
    CMP_Y_LIT,
    CMP_Y_ADDR,
    // Branching
    BCS_ADDR,
    BCC_ADDR,
    BEQ_ADDR,
    BNE_ADDR,
    BMI_ADDR,
    BPL_ADDR,
    BVS_ADDR,
    BVC_ADDR,
    // Addition with carry
    ADD_LIT,
    ADD_ADDR,
    ADD_X,
    ADD_Y,
    // Subtraction with carry
    SUB_LIT,
    SUB_ADDR,
    SUB_X,
    SUB_Y,
    // Increment
    INC_A,
    INC_X,
    INC_Y,
    INC_ADDR,
    // Decrement
    DEC_A,
    DEC_X,
    DEC_Y,
    DEC_ADDR,
    // Pushing to stack
    PUSH_A,
    PUSH_X,
    PUSH_Y,
    // Popping from stack
    POP_A,
    POP_X,
    POP_Y,
    // signal beginning/ending of a debug metadata string
    DEBUG_METADATA_SIGNAL = 0xFF,

    pub fn Instruction_Byte_Length(self: Opcode) u8 {
        return switch (self) {
            .PANIC => opcode_bytelen,
            .SYSTEMCALL => opcode_bytelen,
            .STRIDE_LIT => opcode_bytelen + 1, // special case
            .BRK => opcode_bytelen,
            .NOP => opcode_bytelen,
            .CLC => opcode_bytelen,
            .SEC => opcode_bytelen,
            .RET => opcode_bytelen,
            .LDA_LIT => opcode_bytelen + literal_bytelen,
            .LDX_LIT => opcode_bytelen + literal_bytelen,
            .LDY_LIT => opcode_bytelen + literal_bytelen,
            .LDA_ADDR => opcode_bytelen + address_bytelen,
            .LDX_ADDR => opcode_bytelen + address_bytelen,
            .LDY_ADDR => opcode_bytelen + address_bytelen,
            .LDA_X => opcode_bytelen,
            .LDA_Y => opcode_bytelen,
            .LDX_A => opcode_bytelen,
            .LDX_Y => opcode_bytelen,
            .LDY_A => opcode_bytelen,
            .LDY_X => opcode_bytelen,
            .LDA_ADDR_X => opcode_bytelen + address_bytelen,
            .LDA_ADDR_Y => opcode_bytelen + address_bytelen,
            .STA_ADDR => opcode_bytelen + address_bytelen,
            .STX_ADDR => opcode_bytelen + address_bytelen,
            .STY_ADDR => opcode_bytelen + address_bytelen,
            .JMP_ADDR => opcode_bytelen + address_bytelen,
            .JSR_ADDR => opcode_bytelen + address_bytelen,
            .CMP_A_X => opcode_bytelen,
            .CMP_A_Y => opcode_bytelen,
            .CMP_A_LIT => opcode_bytelen + literal_bytelen,
            .CMP_A_ADDR => opcode_bytelen + address_bytelen,
            .CMP_X_A => opcode_bytelen,
            .CMP_X_Y => opcode_bytelen,
            .CMP_X_LIT => opcode_bytelen + literal_bytelen,
            .CMP_X_ADDR => opcode_bytelen + address_bytelen,
            .CMP_Y_X => opcode_bytelen,
            .CMP_Y_A => opcode_bytelen,
            .CMP_Y_LIT => opcode_bytelen + literal_bytelen,
            .CMP_Y_ADDR => opcode_bytelen + address_bytelen,
            .BCS_ADDR => opcode_bytelen + address_bytelen,
            .BCC_ADDR => opcode_bytelen + address_bytelen,
            .BEQ_ADDR => opcode_bytelen + address_bytelen,
            .BNE_ADDR => opcode_bytelen + address_bytelen,
            .BMI_ADDR => opcode_bytelen + address_bytelen,
            .BPL_ADDR => opcode_bytelen + address_bytelen,
            .BVS_ADDR => opcode_bytelen + address_bytelen,
            .BVC_ADDR => opcode_bytelen + address_bytelen,
            .ADD_LIT => opcode_bytelen + literal_bytelen,
            .ADD_ADDR => opcode_bytelen + address_bytelen,
            .ADD_X => opcode_bytelen,
            .ADD_Y => opcode_bytelen,
            .SUB_LIT => opcode_bytelen + literal_bytelen,
            .SUB_ADDR => opcode_bytelen + address_bytelen,
            .SUB_X => opcode_bytelen,
            .SUB_Y => opcode_bytelen,
            .INC_A => opcode_bytelen,
            .INC_X => opcode_bytelen,
            .INC_Y => opcode_bytelen,
            .INC_ADDR => opcode_bytelen + address_bytelen,
            .DEC_A => opcode_bytelen,
            .DEC_X => opcode_bytelen,
            .DEC_Y => opcode_bytelen,
            .DEC_ADDR => opcode_bytelen + address_bytelen,
            .PUSH_A => opcode_bytelen,
            .PUSH_X => opcode_bytelen,
            .PUSH_Y => opcode_bytelen,
            .POP_A => opcode_bytelen,
            .POP_X => opcode_bytelen,
            .POP_Y => opcode_bytelen,
            .DEBUG_METADATA_SIGNAL => opcode_bytelen,
        };
    }

    pub fn What_Address_Space(self: Opcode) AddressSpace {
        return switch (self) {
            .LDA_ADDR => .wram,
            .LDX_ADDR => .wram,
            .LDY_ADDR => .wram,
            .LDA_ADDR_X => .wram,
            .LDA_ADDR_Y => .wram,
            .STA_ADDR => .wram,
            .STX_ADDR => .wram,
            .STY_ADDR => .wram,
            .JMP_ADDR => .rom,
            .JSR_ADDR => .rom,
            .CMP_A_ADDR => .wram,
            .CMP_X_ADDR => .wram,
            .CMP_Y_ADDR => .wram,
            .BCS_ADDR => .rom,
            .BCC_ADDR => .rom,
            .BEQ_ADDR => .rom,
            .BNE_ADDR => .rom,
            .BMI_ADDR => .rom,
            .BPL_ADDR => .rom,
            .BVS_ADDR => .rom,
            .BVC_ADDR => .rom,
            .ADD_ADDR => .wram,
            .SUB_ADDR => .wram,
            .INC_ADDR => .wram,
            .DEC_ADDR => .wram,
            .PUSH_A => .stack,
            .PUSH_X => .stack,
            .PUSH_Y => .stack,
            .POP_A => .stack,
            .POP_X => .stack,
            .POP_Y => .stack,
            else => .not_applicable,
        };
    }

    pub fn Instruction_String(self: Opcode, buffer: []u8, bytes: []const u8) ![]const u8 {
        if (self.Instruction_Byte_Length() != bytes.len)
            return error.OpcodeParametersMismatch;
        switch (self) {
            .PANIC => return try std.fmt.bufPrint(buffer, "PANIC", .{}),
            .SYSTEMCALL => return try std.fmt.bufPrint(buffer, "SYSCALL", .{}),
            .STRIDE_LIT => return try std.fmt.bufPrint(buffer, "STRIDE {}", .{bytes[1]}),
            .BRK => return try std.fmt.bufPrint(buffer, "BRK", .{}),
            .NOP => return try std.fmt.bufPrint(buffer, "NOP", .{}),
            .CLC => return try std.fmt.bufPrint(buffer, "CLC", .{}),
            .SEC => return try std.fmt.bufPrint(buffer, "SEC", .{}),
            .RET => return try std.fmt.bufPrint(buffer, "RET", .{}),
            .LDA_LIT => return try std.fmt.bufPrint(buffer, "LDA 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .LDX_LIT => return try std.fmt.bufPrint(buffer, "LDX 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .LDY_LIT => return try std.fmt.bufPrint(buffer, "LDY 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .LDA_ADDR => return try std.fmt.bufPrint(buffer, "LDA $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .LDX_ADDR => return try std.fmt.bufPrint(buffer, "LDX $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .LDY_ADDR => return try std.fmt.bufPrint(buffer, "LDY $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .LDA_X => return try std.fmt.bufPrint(buffer, "LDA X", .{}),
            .LDA_Y => return try std.fmt.bufPrint(buffer, "LDA Y", .{}),
            .LDX_A => return try std.fmt.bufPrint(buffer, "LDX A", .{}),
            .LDX_Y => return try std.fmt.bufPrint(buffer, "LDX Y", .{}),
            .LDY_A => return try std.fmt.bufPrint(buffer, "LDY A", .{}),
            .LDY_X => return try std.fmt.bufPrint(buffer, "LDY X", .{}),
            .LDA_ADDR_X => return try std.fmt.bufPrint(buffer, "LDA $0x{X:0>4}, X", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .LDA_ADDR_Y => return try std.fmt.bufPrint(buffer, "LDA $0x{X:0>4}, Y", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .STA_ADDR => return try std.fmt.bufPrint(buffer, "STA $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .STX_ADDR => return try std.fmt.bufPrint(buffer, "STX $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .STY_ADDR => return try std.fmt.bufPrint(buffer, "STY $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .JMP_ADDR => return try std.fmt.bufPrint(buffer, "JMP $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .JSR_ADDR => return try std.fmt.bufPrint(buffer, "JSR $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .CMP_A_X => return try std.fmt.bufPrint(buffer, "CMP A X", .{}),
            .CMP_A_Y => return try std.fmt.bufPrint(buffer, "CMP A Y", .{}),
            .CMP_A_LIT => return try std.fmt.bufPrint(buffer, "CMP A 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .CMP_A_ADDR => return try std.fmt.bufPrint(buffer, "CMP A $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .CMP_X_A => return try std.fmt.bufPrint(buffer, "CMP X A", .{}),
            .CMP_X_Y => return try std.fmt.bufPrint(buffer, "CMP X Y", .{}),
            .CMP_X_LIT => return try std.fmt.bufPrint(buffer, "CMP X 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .CMP_X_ADDR => return try std.fmt.bufPrint(buffer, "CMP X $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .CMP_Y_X => return try std.fmt.bufPrint(buffer, "CMP Y X", .{}),
            .CMP_Y_A => return try std.fmt.bufPrint(buffer, "CMP Y A", .{}),
            .CMP_Y_LIT => return try std.fmt.bufPrint(buffer, "CMP Y 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .CMP_Y_ADDR => return try std.fmt.bufPrint(buffer, "CMP Y $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BCS_ADDR => return try std.fmt.bufPrint(buffer, "BCS $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BCC_ADDR => return try std.fmt.bufPrint(buffer, "BCC $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BEQ_ADDR => return try std.fmt.bufPrint(buffer, "BEQ $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BNE_ADDR => return try std.fmt.bufPrint(buffer, "BNE $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BMI_ADDR => return try std.fmt.bufPrint(buffer, "BMI $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BPL_ADDR => return try std.fmt.bufPrint(buffer, "BPL $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BVS_ADDR => return try std.fmt.bufPrint(buffer, "BVS $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .BVC_ADDR => return try std.fmt.bufPrint(buffer, "BVC $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .ADD_LIT => return try std.fmt.bufPrint(buffer, "ADD 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .ADD_ADDR => return try std.fmt.bufPrint(buffer, "ADD $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .ADD_X => return try std.fmt.bufPrint(buffer, "ADD X", .{}),
            .ADD_Y => return try std.fmt.bufPrint(buffer, "ADD Y", .{}),
            .SUB_LIT => return try std.fmt.bufPrint(buffer, "SUB 0x{X:0>8}", .{std.mem.bytesToValue(u32, bytes[1..5])}),
            .SUB_ADDR => return try std.fmt.bufPrint(buffer, "SUB $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .SUB_X => return try std.fmt.bufPrint(buffer, "SUB X", .{}),
            .SUB_Y => return try std.fmt.bufPrint(buffer, "SUB Y", .{}),
            .INC_A => return try std.fmt.bufPrint(buffer, "INC A", .{}),
            .INC_X => return try std.fmt.bufPrint(buffer, "INC X", .{}),
            .INC_Y => return try std.fmt.bufPrint(buffer, "INC Y", .{}),
            .INC_ADDR => return try std.fmt.bufPrint(buffer, "INC $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .DEC_A => return try std.fmt.bufPrint(buffer, "DEC A", .{}),
            .DEC_X => return try std.fmt.bufPrint(buffer, "DEC X", .{}),
            .DEC_Y => return try std.fmt.bufPrint(buffer, "DEC Y", .{}),
            .DEC_ADDR => return try std.fmt.bufPrint(buffer, "DEC $0x{X:0>4}", .{std.mem.bytesToValue(u16, bytes[1..3])}),
            .PUSH_A => return try std.fmt.bufPrint(buffer, "PUSH A", .{}),
            .PUSH_X => return try std.fmt.bufPrint(buffer, "PUSH X", .{}),
            .PUSH_Y => return try std.fmt.bufPrint(buffer, "PUSH Y", .{}),
            .POP_A => return try std.fmt.bufPrint(buffer, "POP A", .{}),
            .POP_X => return try std.fmt.bufPrint(buffer, "POP X", .{}),
            .POP_Y => return try std.fmt.bufPrint(buffer, "POP Y", .{}),
            .DEBUG_METADATA_SIGNAL => return try std.fmt.bufPrint(buffer, "debug metadata signal", .{}),
        }
    }
};

/// tells the debugger how to interpret the rom in a humanly understandable way.
/// (open and closed square brackets represent the DEBUG_METADATA_SIGNAL byte)
pub const DebugMetadataType = enum(u8) {
    /// Saves the identifier name and source position of the original label.
    /// string terminated by the debug metadata signal.
    /// *by design cannot save original anonymous label name*
    ///
    /// EXAMPLE:
    /// ```
    /// [ LABEL_NAME 'Fibonacci' ]
    /// LDA 0x01
    /// ```
    ///
    LABEL_NAME,

    // *SCRAPPED IDEA; THIS CAN BE RESOLVED DURING THE DEBUGGER'S RUNTIME*
    //
    // Saves the label identifier name before it is turned into a pure
    // address, works for both relative label references and anonymous labels,
    // if no identifier was found, output the string "null".
    //
    // EXAMPLE:
    // ```
    // [ JUMP_TARGET 'Skip' ]
    // JMP Skip
    // Skip:
    // LDA 0x01
    // [ JUMP_TARGET 'Skip' ]
    // JMP @-
    // [ JUMP_TARGET 'null' ]
    // JMP $1337
    // ```
    //
    //JUMP_TARGET,

    // *SCRAPPED IDEA; ANYTHING BEFORE ENTRY POINT CONSIDERED DATA*
    //
    // signals the start of direct byte definitions, that are
    // not meant to be interpreted as instruction opcodes.
    // DONE: hardcoded to only occur between the start of rom
    //       and beginning of the entry point address.
    //
    // EXAMPLE:
    // ```
    // [ DATA_BEGIN ]
    // .db 0x01 0x02 0x03 0x04
    // .dw 0x0001 0x0002
    // .dd 0x00000001
    // ```
    //
    //DATA_BEGIN,

    // *SCRAPPED IDEA; ANYTHING AFTER ENTRY POINT CONSIDERED INSTRUCTION*
    //
    // signals the start of actual assembly instructions, and
    // implicitly, the end of direct data bytes.
    // DONE: harcoded to only occur at the start of the entry
    //       point address.
    //
    // EXAMPLE:
    // ```
    // [ DATA_BEGIN ]
    // .db "I am data!"
    // .db "Not opcodes."
    // [ INSTRUCTION_BEGIN ]
    // [ LABEL_NAME '_START' ]
    // LDA 0x00
    // STA $0x00
    // ```
    //
    //OPCODES_BEGIN,

    /// finds closing debug sinal on variable width metadata, such as strings.
    /// returns static hardcoded numbers for fixed width metadata, such as literals or addresses.
    /// bytes = {DEBUG_METADATA_SIGNAL, METADATA_TYPE, data, ..., data, DEBUG_METADATA_SIGNAL}
    pub fn Metadata_Length(self: DebugMetadataType, bytes: []const u8) !usize {
        if (bytes[0] != @intFromEnum(Opcode.DEBUG_METADATA_SIGNAL))
            return error.BadMetadata;
        return switch (self) {
            .LABEL_NAME => {
                for (1..bytes.len) |i| {
                    if (bytes[i] == @intFromEnum(Opcode.DEBUG_METADATA_SIGNAL))
                        return i + 1;
                }
                return error.BadMetadata;
            },
        };
    }
};

pub const SyscallCode = enum(u8) {
    // Print to stdout a static constant null terminated string.
    // X = address of str (in ROM)
    // Y = _unused_
    PRINT_ROM_STR = 0x00,
    // Print to stdout a variable null terminated string.
    // X = address of str (in RAM)
    // Y = _unused_
    PRINT_WRAM_STR = 0x01,
    // Print a newline to stdout.
    // X = _unused_
    // Y = _unused_
    PRINT_NEWLINE = 0x02,
    // Print an ASCII character to stdout. Special undisplayable characters are shown as '?'.
    // X = char
    // Y = _unused_
    PRINT_CHAR = 0x03,
    // Print an u32 integer to stdout in decimal format.
    // X = value
    // Y = _unused_
    PRINT_DEC_INT = 0x04,
    // Print an u32 integer to stdout in hexadecimal format.
    // X = value
    // Y = _unused_
    PRINT_HEX_INT = 0x05,

    // exhaust all remaining integers so it may catch @enumFromInt exceptions at runtime.
    _,
};

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "metadata length" {
    var len: usize = undefined;

    len = try DebugMetadataType.Metadata_Length(.LABEL_NAME, &.{ 0xFF, 0x00, 0xFF });
    try std.testing.expectEqual(3, len);
    len = try DebugMetadataType.Metadata_Length(.LABEL_NAME, &.{ 0xFF, 0x00, 0x00, 0xFF });
    try std.testing.expectEqual(4, len);
}
