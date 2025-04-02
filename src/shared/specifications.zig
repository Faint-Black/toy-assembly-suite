//=============================================================//
//                                                             //
//                   ASSEMBLY SPECIFICATIONS                   //
//                                                             //
//   Garantees the assembly's standard specifications across   //
//  all source files.                                          //
//                                                             //
//=============================================================//

const std = @import("std");

// -version 1
//  All basic opcodes introduced.
/// current toy assembly language revision
pub const current_assembly_version: u8 = 1;

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
pub const rom_header_bytelen: u8 = 16;
pub const rom_magic_number: u8 = 0x69;

/// standardized ROM header parsing
pub const Header = struct {
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
};
