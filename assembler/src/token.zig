//=============================================================//
//                                                             //
//                            TOKEN                            //
//                                                             //
//   Defines the individual building block of this language.   //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("utils.zig");

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
            .identKey = if (self.identKey) |str| try utils.Copy_Of_ConstString(allocator, str) else null,
            .text = if (self.text) |str| try utils.Copy_Of_ConstString(allocator, str) else null,
            .value = self.value,
        };
    }

    /// print individual token, for debugging purposes
    pub fn Print(self: Token) void {
        if (self.tokType.Is_Value_Token()) {
            std.debug.print("{s}=0x{X}", .{ std.enums.tagName(TokenType, self.tokType).?, self.value });
        } else if (self.identKey != null) {
            std.debug.print("{s}=\"{s}\"", .{ std.enums.tagName(TokenType, self.tokType).?, self.identKey.? });
        } else {
            std.debug.print("{s}", .{std.enums.tagName(TokenType, self.tokType).?});
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
    std.debug.print("{{\n", .{});
    for (tokArray) |token| {
        if (token.tokType == .LINEFINISH) {
            std.debug.print("$\n", .{});
            continue;
        }
        token.Print();
        std.debug.print(", ", .{});
    }
    std.debug.print("}}\n", .{});
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

    // preprocessor DEFINE direct rom bytes
    /// define byte (8 bits)
    DB,
    /// define word (16 bits)
    DW,
    /// define double word (32 bits)
    DD,

    // preprocessor MACRO instructions
    /// start macro definition
    MACRO,
    /// end macro definition
    ENDMACRO,

    // direct VIRTUAL MACHINE instructions
    /// perform special operations based on the code
    SYSCALL,

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

    pub fn Is_Value_Token(self: TokenType) bool {
        return switch (self) {
            .LITERAL => true,
            .ADDRESS => true,
            else => false,
        };
    }
};
