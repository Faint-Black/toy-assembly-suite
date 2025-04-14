//=============================================================//
//                                                             //
//                            TOKEN                            //
//                                                             //
//   Defines the individual building block of this language.   //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("shared").utils;

const stdout = std.io.getStdOut().writer();

pub const Token = struct {
    /// enum type of the token, undefined by default
    tokType: TokenType = TokenType.UNDEFINED,
    /// allocated identifier name
    identKey: ?[]u8 = null,
    /// allocated string contents (no use-case yet)
    text: ?[]u8 = null,
    /// 4 bytes of value contents
    value: u32 = 0,

    /// init all as undefined/null
    pub fn Init() Token {
        return Token{
            .tokType = TokenType.UNDEFINED,
            .identKey = null,
            .text = null,
            .value = 0,
        };
    }

    /// deallocate memory, if not null
    pub fn Deinit(self: Token, allocator: std.mem.Allocator) void {
        if (self.identKey) |memory|
            allocator.free(memory);
        if (self.text) |memory|
            allocator.free(memory);
    }

    /// returns a copy of the token,
    /// if it contains allocated memory, make a newly allocated copy of it
    pub fn Copy(self: Token, allocator: std.mem.Allocator) !Token {
        return Token{
            .tokType = self.tokType,
            .identKey = if (self.identKey) |str| try utils.Copy_Of_String(allocator, str) else null,
            .text = if (self.text) |str| try utils.Copy_Of_String(allocator, str) else null,
            .value = self.value,
        };
    }

    /// print individual token, for debugging purposes
    pub fn Print(self: Token) void {
        const enum_name = std.enums.tagName(TokenType, self.tokType).?;

        if (self.identKey) |identifier| {
            stdout.print("{s}=\"{s}\"", .{ enum_name, identifier }) catch unreachable;
        } else if (self.tokType == .LITERAL) {
            stdout.print("LIT=0x{x}", .{self.value}) catch unreachable;
        } else if (self.tokType == .ADDRESS) {
            stdout.print("ADDR=0x{x}", .{self.value}) catch unreachable;
        } else if (self.tokType == .BACKWARD_LABEL_REF) {
            stdout.print("RELATIVE_LABEL=-{}", .{self.value}) catch unreachable;
        } else if (self.tokType == .FORWARD_LABEL_REF) {
            stdout.print("RELATIVE_LABEL=+{}", .{self.value}) catch unreachable;
        } else {
            stdout.print("{s}", .{enum_name}) catch unreachable;
        }
    }
};

/// deallocate the allocated strings inside the tokens
/// (but does not deallocate the tokens themselves!)
pub fn Destroy_Tokens_Contents(allocator: std.mem.Allocator, tokArray: []const Token) void {
    for (tokArray) |token|
        token.Deinit(allocator);
}

/// for debugging only
pub fn Print_Token_Array(tokArray: []const Token) void {
    stdout.print("{{\n", .{}) catch unreachable;
    for (tokArray) |token| {
        if (token.tokType == .LINEFINISH) {
            stdout.print("$\n", .{}) catch unreachable;
            continue;
        }
        token.Print();
        stdout.print(", ", .{}) catch unreachable;
    }
    stdout.print("}}\n", .{}) catch unreachable;
}

pub const TokenType = enum {
    // special parsing tokens
    /// default token type
    UNDEFINED,
    /// matching definition could not be found *unused*
    UNKNOWN,
    /// explicitly defined error token *unused*
    ERROR,
    /// EOF
    ENDOFFILE,
    /// $
    LINEFINISH,

    // value tokens
    /// 32-bit number
    LITERAL,
    /// 32-bit address
    ADDRESS,

    // symbol related tokens
    /// identifier
    IDENTIFIER,
    /// rom address marker
    LABEL,
    /// used for relative referencing
    ANON_LABEL,
    /// referrer to a label n positions away (backwards)
    BACKWARD_LABEL_REF,
    /// referrer to a label n positions away (forwards)
    FORWARD_LABEL_REF,

    // preprocessor DEFINE direct rom bytes
    /// define byte (8 bits)
    DB,
    /// define word (16 bits)
    DW,
    /// define double word (32 bits)
    DD,

    // preprocessor instructions
    /// begin macro definition
    MACRO,
    /// end macro definition
    ENDMACRO,
    /// begin a repeat unwrapper
    REPEAT,
    /// end the repeat unwrapper
    ENDREPEAT,
    /// create a one token macro
    DEFINE,

    // direct VIRTUAL MACHINE instructions
    /// perform special operations based on the code
    SYSCALL,
    /// defines byte stride of indexing instructions
    STRIDE,

    // REGISTER tokens
    /// Accumulator
    A,
    /// X index
    X,
    /// Y index
    Y,
    /// Program Counter
    PC,
    /// Stack Counter
    SC,

    // REGISTER INSTRUCTION tokens
    /// clear carry
    CLC,
    /// set carry
    SEC,

    // LOAD instructions
    /// load to accumulator
    LDA,
    /// load to X index
    LDX,
    /// load to Y index
    LDY,

    // LOAD EFFECTIVE ADDRESS intructions
    /// load effective address to accumulator
    LEA,
    /// load effective address to X index
    LEX,
    /// load effective address to Y index
    LEY,

    // STORE instructions
    /// store accumulator to address
    STA,
    /// store X index to address
    STX,
    /// store Y index to address
    STY,

    // JUMPING instructions
    /// jump to label
    JMP,
    /// jump to subroutine
    JSR,
    /// return from subroutine
    RET,

    // COMPARE instructions
    /// compare
    CMP,

    // BRANCHING instructions
    /// branch if carry set
    BCS,
    /// branch if carry is cleared
    BCC,
    /// branch if equal (if zero flag is set)
    BEQ,
    /// branch if not equal (if zero flag is cleared)
    BNE,
    /// branch if minus (if negative flag is set)
    BMI,
    /// branch if plus (if negative flag is cleared)
    BPL,
    /// branch if overflow is set
    BVS,
    /// branch if overflow is cleared
    BVC,

    // ARITHMETIC instructions
    /// add arguments to accumulator
    ADD,
    /// subtract arguments to accumulator
    SUB,

    // INCREMENT/DECREMENT instructions
    /// increment argument by one
    INC,
    /// decrement argument by one
    DEC,

    // STACK instructions
    /// push to stack
    PUSH,
    /// pop from stack
    POP,

    // SPECIAL instructions
    /// break, signal end of program execution
    BRK,
    /// no operation, do nothing
    NOP,
};
