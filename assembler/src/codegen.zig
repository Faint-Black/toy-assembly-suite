//=============================================================//
//                                                             //
//                     CODE GENERATION                         //
//                                                             //
//   Responsible for generating the ROM bytecode that will be  //
//  passed to the virual machine for execution.                //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("utils.zig");
const tok = @import("token.zig");
const sym = @import("symbol.zig");

/// f: [tokens] -> [rom]
pub fn Generate_Rom(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, expandedTokens: []const tok.Token) ![]u8 {
    try First_Pass(allocator, symTable, expandedTokens);
    return try Second_Pass(allocator, symTable.*, expandedTokens);
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

/// only responsible for attributing address values to the existing LABEL symbols
/// bytecode has to be generated twice for this program to accept forward references
fn First_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, expandedTokens: []const tok.Token) !void {
    // vital for determining the LABEL address positions
    var rom_vector = std.ArrayList(u8).init(allocator);
    defer rom_vector.deinit();

    // build the instruction line, one token at a time for proper symbol substitution
    var tokenBuffer: [64]tok.Token = undefined;
    var tokenBuffsize: usize = 0;

    // for ".db", ".dw" and ".dd" modes
    var activeByteDefiner: ?tok.TokenType = null;

    try Create_Header(&rom_vector, 0);

    // for every token loop
    for (expandedTokens) |token| {
        if (tokenBuffsize >= 8)
            return error.InstructionLineTooLong;
        if (token.tokType == tok.TokenType.ENDOFFILE)
            break;

        // build instruction line and generate the appropriate bytecode
        if (token.tokType == .LINEFINISH) {
            // reset byte definition mode
            activeByteDefiner = null;

            // skip empty instruction lines, e.g "[$]"
            if (tokenBuffsize == 0)
                continue;
            try Process_Instruction_Line(tokenBuffer[0..tokenBuffsize], &rom_vector);
            tokenBuffsize = 0;
            continue;
        }

        // activate byte definition mode
        if (token.tokType == .DB or token.tokType == .DW or token.tokType == .DD) {
            activeByteDefiner = token.tokType;
            continue;
        }

        // process direct byte definitions here
        if (activeByteDefiner != null) {
            if (token.tokType.Is_Value_Token() == false) {
                std.log.err("Token \"{s}\" is not a valid value!", .{std.enums.tagName(tok.TokenType, token.tokType).?});
                return error.BadByteDefinition;
            }
            switch (activeByteDefiner.?) {
                .DB => try Append_Generic_Limited(&rom_vector, token.value, 1),
                .DW => try Append_Generic_Limited(&rom_vector, token.value, 2),
                .DD => try Append_Generic_Limited(&rom_vector, token.value, 4),
                else => return error.UnknownByteDefiner,
            }
            continue;
        }

        // here the already existing LABEL symbol address value is changed in the symbol table
        if (token.tokType == .LABEL) {
            const current_address_value_token: tok.Token = tok.Token{
                .tokType = .ADDRESS,
                .identKey = try utils.Copy_Of_ConstString(allocator, token.identKey.?),
                .value = @truncate(rom_vector.items.len),
            };
            const label_symbol = sym.Symbol{
                .name = try utils.Copy_Of_ConstString(allocator, token.identKey.?),
                .value = .{ .label = current_address_value_token },
            };
            // replaces the existing LABEL entry
            // same effect as changing its value
            try symTable.*.Add(label_symbol);

            // special case: code entry point label
            // store address value in respective header bytes
            if (std.mem.eql(u8, token.identKey.?, "_START")) {
                std.mem.copyForwards(u8, rom_vector.items[2..6], &std.mem.toBytes(current_address_value_token.value));
            }

            continue;
        }

        // identifier symbol substitution
        // since this step only scans for LABEL addresses, there is no need for an accurate substitution
        if (token.tokType == .IDENTIFIER) {
            if (symTable.*.Get(token.identKey)) |symbol| {
                switch (symbol.value) {
                    // if its a label, replace it with a null placeholder value
                    .label => {
                        const placeholder = tok.Token{ .tokType = .ADDRESS, .value = 0x00 };
                        try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, placeholder);
                    },
                    // all macros need to be processed before this stage is ever reached
                    .macro => {
                        return error.UnexpandedMacro;
                    },
                }
                continue;
            } else {
                std.log.err("unknown identifier \"{s}\"", .{token.identKey.?});
                return error.UnknownIdentifier;
            }
        }

        try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, token);
    }
}

/// Now that all the LABEL address values are known, we can start the actual code generation
fn Second_Pass(allocator: std.mem.Allocator, symTable: sym.SymbolTable, expandedTokens: []const tok.Token) ![]u8 {
    var rom_vector = std.ArrayList(u8).init(allocator);
    defer rom_vector.deinit();

    // build the instruction line, one token at a time for proper symbol substitution
    var tokenBuffer: [64]tok.Token = undefined;
    var tokenBuffsize: usize = 0;

    // for ".db", ".dw" and ".dd" modes
    var activeByteDefiner: ?tok.TokenType = null;

    // start with the 16 bytes of the ROM file header
    try Create_Header(&rom_vector, 1);

    // if the "_START:" special label has been defined already
    // put its value address on the appropriate rom header bytes
    if (symTable.Get("_START")) |symbol| {
        if (symbol.value != .label) {
            std.log.err("the \"_START\" keyword is reserved for labels!", .{});
            return error.MisuseOfLabels;
        }
        const address_value = symbol.value.label.value;
        std.mem.copyForwards(u8, rom_vector.items[2..6], &std.mem.toBytes(address_value));
    }

    // for every token loop
    for (expandedTokens) |token| {
        if (tokenBuffsize >= 8)
            return error.InstructionLineTooLong;
        if (token.tokType == tok.TokenType.ENDOFFILE)
            break;

        // build instruction line and generate the appropriate bytecode
        if (token.tokType == .LINEFINISH) {
            // reset byte definition mode
            activeByteDefiner = null;

            // skip empty instruction lines, e.g "[$]"
            if (tokenBuffsize == 0)
                continue;
            try Process_Instruction_Line(tokenBuffer[0..tokenBuffsize], &rom_vector);
            tokenBuffsize = 0;
            continue;
        }

        // activate byte definition mode
        if (token.tokType == .DB or token.tokType == .DW or token.tokType == .DD) {
            activeByteDefiner = token.tokType;
            continue;
        }

        // process direct byte definitions here
        if (activeByteDefiner != null) {
            if (token.tokType.Is_Value_Token() == false) {
                std.log.err("Token \"{s}\" is not a valid value!", .{std.enums.tagName(tok.TokenType, token.tokType).?});
                return error.BadByteDefinition;
            }
            switch (activeByteDefiner.?) {
                .DB => try Append_Generic_Limited(&rom_vector, token.value, 1),
                .DW => try Append_Generic_Limited(&rom_vector, token.value, 2),
                .DD => try Append_Generic_Limited(&rom_vector, token.value, 4),
                else => return error.UnknownByteDefiner,
            }
            continue;
        }

        // ignore LABELs as their symbols and tokens should be already processed and stripped at this stage
        if (token.tokType == .LABEL)
            continue;

        // identifier symbol substitution
        if (token.tokType == .IDENTIFIER) {
            if (symTable.Get(token.identKey)) |symbol| {
                switch (symbol.value) {
                    // if its a label, replace it directly as it already represents an address token
                    .label => try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, symbol.value.label),
                    // all macros need to be processed before this stage is ever reached
                    .macro => return error.UnexpandedMacro,
                }
                continue;
            } else {
                return error.UnknownIdentifier;
            }
        }

        try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, token);
    }

    return rom_vector.toOwnedSlice();
}

/// Append the bytecode instruction respective to the input instruction line tokens
fn Process_Instruction_Line(line: []tok.Token, vec: *std.ArrayList(u8)) !void {
    // 8 token limit for an instruction line
    const buffsize: usize = 8;
    if (line.len >= buffsize)
        return error.InstructionLineTooLong;

    // copy variable width input into fixed width local buffer
    // *deprecated behavior* exclude the instruction line newline token too
    // this is a less versatile, but overall safer approach
    var t: [buffsize]tok.Token = .{tok.Token.Init()} ** buffsize;
    for (0..line.len) |i| {
        if (line[i].tokType == .LINEFINISH)
            break;
        t[i] = line[i];
    }

    // this "manual" if chain is necessary due to a variety of issues from other approaches,
    // unmatched lexed strings being automatically turned to identifiers is the biggest of them.
    // this may or may not be redesigned in the future. Keep in mind i am incredibly lazy...
    if (t[0].tokType == .ERROR) {
        // for debugging purposes only
        try vec.*.append(0);
    } else if (t[0].tokType == .SYSCALL) {
        // "SYSCALL"
        // Performs a (virtual) machine system call
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.SYSTEMCALL));
    } else if (t[0].tokType == .BRK) {
        // "BRK"
        // Break, exits execution
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.BRK));
    } else if (t[0].tokType == .NOP) {
        // "NOP"
        // No operation, do nothing, preferably with some noticeable delay
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.NOP));
    } else if (t[0].tokType == .CLC) {
        // "CLC"
        // Clear carry, set the carry flag to 0
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CLC));
    } else if (t[0].tokType == .SEC) {
        // "SEC"
        // Set carry, set the carry flag to 1
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.SEC));
    } else if (t[0].tokType == .RET) {
        // "RET"
        // Return from subroutine
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.RET));
    } else if (t[0].tokType == .LDA and t[1].tokType == .LITERAL) {
        // "LDA 0x42"
        // Load literal into accumulator
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDA_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDX and t[1].tokType == .LITERAL) {
        // "LDX 0x42"
        // Load literal into X index
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDX_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDY and t[1].tokType == .LITERAL) {
        // "LDY 0x42"
        // Load literal into Y index
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDY_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDA and t[1].tokType == .ADDRESS) {
        // "LDA $0x1337"
        // Load value from address into accumulator
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDA_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDX and t[1].tokType == .ADDRESS) {
        // "LDX $0x1337"
        // Load value from address into X index
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDX_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDY and t[1].tokType == .ADDRESS) {
        // "LDY $0x1337"
        // Load value from address into Y index
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDY_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDA and t[1].tokType == .X) {
        // "LDA X"
        // Transfer the contents of the X index into the accumulator
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.LDA_X));
    } else if (t[0].tokType == .LDA and t[1].tokType == .Y) {
        // "LDA Y"
        // Transfer the contents of the Y index into the accumulator
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.LDA_Y));
    } else if (t[0].tokType == .LDX and t[1].tokType == .A) {
        // "LDX A"
        // Transfer the contents of the accumulator into the X index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.LDX_A));
    } else if (t[0].tokType == .LDX and t[1].tokType == .Y) {
        // "LDX Y"
        // Transfer the contents of the Y index into the X index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.LDX_Y));
    } else if (t[0].tokType == .LDY and t[1].tokType == .A) {
        // "LDY A"
        // Transfer the contents of the accumulator into the Y index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.LDY_A));
    } else if (t[0].tokType == .LDY and t[1].tokType == .X) {
        // "LDY X"
        // Transfer the contents of the X index into the Y index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.LDY_X));
    } else if (t[0].tokType == .LDA and t[1].tokType == .ADDRESS and t[2].tokType == .X) {
        // "LDA $0x1337 X"
        // Load value from address indexed by X into the accumulator
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDA_ADDR_X));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDA and t[1].tokType == .ADDRESS and t[2].tokType == .Y) {
        // "LDA $0x1337 Y"
        // Load value from address indexed by X into the accumulator
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.LDA_ADDR_Y));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .STA and t[1].tokType == .ADDRESS) {
        // "STA $0x1337"
        // Store accumulator value into address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.STA_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .STX and t[1].tokType == .ADDRESS) {
        // "STX $0x1337"
        // Store X index value into address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.STX_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .STY and t[1].tokType == .ADDRESS) {
        // "STY $0x1337"
        // Store Y index value into address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.STY_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .JMP and t[1].tokType == .ADDRESS) {
        // "JMP Foo"
        // Jump to rom address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.JMP_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .JSR and t[1].tokType == .ADDRESS) {
        // "JSR Foo"
        // Save current PC and jump to rom address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.JSR_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .X) {
        // "CMP A X"
        // Compares the accumulator to the X index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CMP_A_X));
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .Y) {
        // "CMP A Y"
        // Compares the accumulator to the Y index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CMP_A_Y));
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .LITERAL) {
        // "CMP A 0x42"
        // Compares the accumulator to a literal
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.CMP_A_LIT));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .ADDRESS) {
        // "CMP A $0x1337"
        // Compares the accumulator to the value inside an address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.CMP_A_ADDR));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .A) {
        // "CMP X A"
        // Compares the X index to the accumulator
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CMP_X_A));
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .Y) {
        // "CMP X Y"
        // Compares the X index to the Y index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CMP_X_Y));
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .LITERAL) {
        // "CMP X 0x42"
        // Compares the X index to a literal
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.CMP_X_LIT));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .ADDRESS) {
        // "CMP X $0x1337"
        // Compares the X index to the value inside an address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.CMP_X_ADDR));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .X) {
        // "CMP Y X"
        // Compares the Y index to the X index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CMP_Y_X));
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .A) {
        // "CMP Y A"
        // Compares the Y index to the accumulator
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.CMP_Y_A));
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .LITERAL) {
        // "CMP Y 0x42"
        // Compares the Y index to a literal
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.CMP_Y_LIT));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .ADDRESS) {
        // "CMP Y $0x1337"
        // Compares the Y index to the value inside an address
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.CMP_Y_ADDR));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .BCS and t[1].tokType == .ADDRESS) {
        // "BCS Foo"
        // Branch if carry set
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BCS_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BCC and t[1].tokType == .ADDRESS) {
        // "BCC Foo"
        // Branch if carry clear
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BCC_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BEQ and t[1].tokType == .ADDRESS) {
        // "BEQ Foo"
        // Branch if equal
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BEQ_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BNE and t[1].tokType == .ADDRESS) {
        // "BNE Foo"
        // Branch if not equal
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BNE_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BMI and t[1].tokType == .ADDRESS) {
        // "BMI Foo"
        // Branch if minus
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BMI_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BPL and t[1].tokType == .ADDRESS) {
        // "BPL Foo"
        // Branch if plus
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BPL_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BVS and t[1].tokType == .ADDRESS) {
        // "BVS Foo"
        // Branch if overflow set
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BVS_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .BVC and t[1].tokType == .ADDRESS) {
        // "BVC Foo"
        // Branch if overflow clear
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.BVC_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .ADD and t[1].tokType == .LITERAL) {
        // "ADD 0x42"
        // accumulator += (literal + carry)
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.ADD_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .ADD and t[1].tokType == .ADDRESS) {
        // "ADD $0x1337"
        // accumulator += (value in address + carry)
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.ADD_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .ADD and t[1].tokType == .X) {
        // "ADD X"
        // accumulator += (X index + carry)
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.ADD_X));
    } else if (t[0].tokType == .ADD and t[1].tokType == .Y) {
        // "ADD Y"
        // accumulator += (Y index + carry)
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.ADD_Y));
    } else if (t[0].tokType == .SUB and t[1].tokType == .LITERAL) {
        // "SUB 0x42"
        // accumulator -= (literal + carry - 1)
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.SUB_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .SUB and t[1].tokType == .ADDRESS) {
        // "SUB $0x1337"
        // accumulator -= (value in address + carry - 1)
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.SUB_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .SUB and t[1].tokType == .X) {
        // "SUB X"
        // accumulator -= (X index + carry - 1)
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.SUB_X));
    } else if (t[0].tokType == .SUB and t[1].tokType == .Y) {
        // "SUB Y"
        // accumulator -= (Y index + carry - 1)
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.SUB_Y));
    } else if (t[0].tokType == .INC and t[1].tokType == .A) {
        // "INC A"
        // Increment the accumulator by one
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.INC_A));
    } else if (t[0].tokType == .INC and t[1].tokType == .X) {
        // "INC X"
        // Increment the X index by one
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.INC_X));
    } else if (t[0].tokType == .INC and t[1].tokType == .Y) {
        // "INC Y"
        // Increment the Y index by one
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.INC_Y));
    } else if (t[0].tokType == .INC and t[1].tokType == .ADDRESS) {
        // "INC $0x1337"
        // Increment the value inside the address by one
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.INC_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .DEC and t[1].tokType == .A) {
        // "DEC A"
        // Decrement the accumulator by one
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.DEC_A));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .DEC and t[1].tokType == .X) {
        // "DEC X"
        // Decrement the X index by one
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.DEC_X));
    } else if (t[0].tokType == .DEC and t[1].tokType == .Y) {
        // "DEC Y"
        // Decrement the Y index by one
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.DEC_Y));
    } else if (t[0].tokType == .DEC and t[1].tokType == .ADDRESS) {
        // "DEC $0x1337"
        // Decrement the value inside the address by one
        // instruction byte len = 1 + 4
        try vec.*.append(@intFromEnum(Opcode.DEC_ADDR));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .PUSH and t[1].tokType == .A) {
        // "PUSH A"
        // Pushes the value of the accumulator to the stack
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.PUSH_A));
    } else if (t[0].tokType == .PUSH and t[1].tokType == .X) {
        // "PUSH X"
        // Pushes the value of the X index to the stack
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.PUSH_X));
    } else if (t[0].tokType == .PUSH and t[1].tokType == .Y) {
        // "PUSH Y"
        // Pushes the value of the Y index to the stack
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.PUSH_Y));
    } else if (t[0].tokType == .POP and t[1].tokType == .A) {
        // "POP A"
        // Pops a value from the stack into the accumulator
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.POP_A));
    } else if (t[0].tokType == .POP and t[1].tokType == .X) {
        // "POP X"
        // Pops a value from the stack into the X index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.POP_X));
    } else if (t[0].tokType == .POP and t[1].tokType == .Y) {
        // "POP_Y"
        // Pops a value from the stack into the Y index
        // instruction byte len = 1
        try vec.*.append(@intFromEnum(Opcode.POP_Y));
    } else {
        std.debug.print("ERROR: unknown opcode!\n", .{});
        tok.Print_Token_Array(line);
    }
}

/// Create the 16 byte rom header
fn Create_Header(rom_vector: *std.ArrayList(u8), version: u8) !void {
    // byte 0 = magic number
    try rom_vector.*.append(@as(u8, 0x69));
    // byte 1 = assembly language version
    try rom_vector.*.append(version);
    // bytes 2 to 5 = execution address entry point
    // right after header is the default, but can be
    // altered with the special "_START:" label
    try rom_vector.*.append(@as(u8, 0x10));
    try rom_vector.*.append(@as(u8, 0x00));
    try rom_vector.*.append(@as(u8, 0x00));
    try rom_vector.*.append(@as(u8, 0x00));
    // bytes 6 to 15 = free space, for now
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
    try rom_vector.*.append(@as(u8, 0xCC));
}

/// Using low-endian, sequentially append the bytes of a value to an u8 arraylist
fn Append_Generic(vector: *std.ArrayList(u8), value: anytype) !void {
    const byte_array = std.mem.toBytes(value);
    for (byte_array) |byte|
        try vector.*.append(byte);
}

/// Using low-endian, sequentially append the first n bytes of a value to an u8 arraylist
fn Append_Generic_Limited(vector: *std.ArrayList(u8), value: anytype, n: usize) !void {
    const byte_array = std.mem.toBytes(value);
    if (n > byte_array.len)
        return error.LargerThanByteArray;
    for (byte_array, 0..) |byte, i| {
        if (i == n)
            break;
        try vector.*.append(byte);
    }
}

/// "MNEMONIC_ARG1_ARG2"
/// All literals are 32-bit unsigned integers
/// All registers can hold 32-bit values
/// All addresses are 32-bit unsigned integers
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
};

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "byte vector appending" {
    const num = @as(u32, 0xFFEEDDCC);
    var vector = std.ArrayList(u8).init(std.testing.allocator);
    defer vector.deinit();

    try Append_Generic(&vector, num);

    try std.testing.expect(vector.items.len == 4);
    try std.testing.expect(vector.items[0] == 0xCC);
    try std.testing.expect(vector.items[1] == 0xDD);
    try std.testing.expect(vector.items[2] == 0xEE);
    try std.testing.expect(vector.items[3] == 0xFF);
}

test "limited byte vector appending" {
    const num = @as(u64, 0xDEADBEEF03020100);
    var vector = std.ArrayList(u8).init(std.testing.allocator);
    defer vector.deinit();

    try Append_Generic_Limited(&vector, num, 3);

    try std.testing.expect(vector.items.len == 3);
    try std.testing.expect(vector.items[0] == 0x00);
    try std.testing.expect(vector.items[1] == 0x01);
    try std.testing.expect(vector.items[2] == 0x02);
}
