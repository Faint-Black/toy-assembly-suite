//=============================================================//
//                                                             //
//                     CODE GENERATION                         //
//                                                             //
//   Responsible for generating the ROM bytecode that will be  //
//  passed to the virual machine for execution.                //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("shared").utils;
const specs = @import("shared").specifications;
const tok = @import("token.zig");
const sym = @import("symbol.zig");
const clap = @import("clap.zig");

const Opcode = specs.Opcode;
const DebugMetadataType = specs.DebugMetadataType;

pub fn Generate_Rom(allocator: std.mem.Allocator, flags: clap.Flags, symTable: *sym.SymbolTable, expandedTokens: []const tok.Token) ![]u8 {
    const first_pass = try Codegen(true, allocator, flags, symTable, expandedTokens);
    allocator.free(first_pass);
    const second_pass = try Codegen(false, allocator, flags, symTable, expandedTokens);

    // [DEBUG OUTPUT] print rom bytes
    if (flags.print_rom_bytes)
        Debug_Print_Rom(second_pass, flags);

    return second_pass;
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

/// First pass: result is discarded as it is only used to determine LABEL address locations
/// relative to its location in rom.
/// Second pass: now that the LABEL locations have been defined, generate the actual usable rom.
fn Codegen(isFirstPass: bool, allocator: std.mem.Allocator, flags: clap.Flags, symTable: *sym.SymbolTable, expandedTokens: []const tok.Token) ![]u8 {
    var rom_vector = std.ArrayList(u8).init(allocator);
    defer rom_vector.deinit();

    // avoid needless micro allocations
    // this only meant to store a few bytes anyway
    try rom_vector.ensureTotalCapacity(0xFFFF);

    // build the instruction line, one token at a time for proper symbol substitution
    var tokenBuffer: [64]tok.Token = undefined;
    var tokenBuffsize: usize = 0;

    // for ".db", ".dw" and ".dd" modes
    var activeByteDefiner: tok.TokenType = .UNDEFINED;

    // start with the 16 bytes of the ROM file header
    const rom_header = specs.Header{
        .magic_number = specs.rom_magic_number,
        .language_version = specs.current_assembly_version,
        .entry_point = specs.Header.default_entry_point,
        .debug_mode = flags.debug_mode,
    };
    try rom_vector.appendSlice(&rom_header.Parse_To_Byte_Array());

    // if the "_START:" special label has been defined already
    // put its value address on the appropriate rom header bytes
    if (isFirstPass == false) {
        if (symTable.Get("_START")) |symbol| {
            if (symbol.value != .label) {
                std.log.err("the \"_START\" keyword is reserved for labels!", .{});
                return error.MisuseOfLabels;
            }
            const address_value = symbol.value.label.value;
            rom_vector.items[2] = @truncate(address_value);
            rom_vector.items[3] = @truncate(address_value >> 8);
        }
    }

    // for every token loop
    for (expandedTokens) |token| {
        if (tokenBuffsize >= 8)
            return error.InstructionLineTooLong;
        if (token.tokType == tok.TokenType.ENDOFFILE)
            break;

        // ignore LABELs as their symbols and tokens should be already processed and stripped at this stage
        // unless debug mode is active, if so, insert the labels metadata
        if (token.tokType == .LABEL or token.tokType == .ANON_LABEL) {
            if (flags.debug_mode) {
                // insert label debug metadata
                try rom_vector.append(@intFromEnum(Opcode.DEBUG_METADATA_SIGNAL));
                try rom_vector.append(@intFromEnum(DebugMetadataType.LABEL_NAME));
                // 0xFF LABEL_NAME 'LabelName' 0xFF
                if (token.tokType == .LABEL)
                    try rom_vector.appendSlice(token.identKey.?);
                // 0xFF LABEL_NAME 'ANON_LABEL' 0xFF
                if (token.tokType == .ANON_LABEL)
                    try rom_vector.appendSlice("ANON_LABEL");
                try rom_vector.append(@intFromEnum(Opcode.DEBUG_METADATA_SIGNAL));
            }

            // the main purpose of the existance of the first pass:
            // resolve the label address and put it in the symbol table
            if (isFirstPass and token.tokType == .LABEL) {
                const current_address_value_token: tok.Token = tok.Token{
                    .tokType = .ADDRESS,
                    .identKey = try utils.Copy_Of_ConstString(allocator, token.identKey.?),
                    .value = @truncate(rom_vector.items.len),
                };
                const label_symbol = sym.Symbol{
                    .name = try utils.Copy_Of_ConstString(allocator, token.identKey.?),
                    .value = .{ .label = current_address_value_token },
                };
                // replaces if already exists
                try symTable.Add(label_symbol);
            }

            // generates the name for anonymous labels
            // and adds them to the symbol table as normal labels
            if (isFirstPass and token.tokType == .ANON_LABEL) {
                var buffer: [32]u8 = undefined;
                const slice = try std.fmt.bufPrint(&buffer, "ANON_LABEL_{x:0>8}", .{symTable.anonlabel_count});
                symTable.anonlabel_count += 1;

                const current_address_value_token: tok.Token = tok.Token{
                    .tokType = .ADDRESS,
                    .identKey = try utils.Copy_Of_ConstString(allocator, slice),
                    .value = @truncate(rom_vector.items.len),
                };
                const anonlabel_symbol = sym.Symbol{
                    .name = try utils.Copy_Of_ConstString(allocator, slice),
                    .value = .{ .label = current_address_value_token },
                };
                try symTable.Add(anonlabel_symbol);
            }

            // if it is currently second pass and debug mode is disabled,
            // ignore step entirely, as direct LABEL tokens are only made
            // to be added to the symbol table.
            continue;
        }

        // build instruction line and generate the appropriate bytecode
        if (token.tokType == .LINEFINISH) {
            // reset byte definition mode
            activeByteDefiner = .UNDEFINED;
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
        if (activeByteDefiner != .UNDEFINED) {
            if (token.tokType != .LITERAL and token.tokType != .ADDRESS) {
                std.log.err("Token \"{s}\" is not a valid value!", .{std.enums.tagName(tok.TokenType, token.tokType).?});
                return error.BadByteDefinition;
            }
            switch (activeByteDefiner) {
                .DB => try Append_Generic_Limited(&rom_vector, token.value, 1),
                .DW => try Append_Generic_Limited(&rom_vector, token.value, 2),
                .DD => try Append_Generic_Limited(&rom_vector, token.value, 4),
                else => return error.UnknownByteDefiner,
            }
            continue;
        }

        // substitute label reference with the fetched result address
        if (token.tokType == .BACKWARD_LABEL_REF or token.tokType == .FORWARD_LABEL_REF) {
            // on first pass not all labels are known yet, so skip this step with a dummy label
            if (isFirstPass) {
                const placeholder = tok.Token{ .tokType = .ADDRESS, .value = 0x0 };
                try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, placeholder);
                continue;
            }

            const label_token = try symTable.Search_Relative_Label(token, @truncate(rom_vector.items.len));
            const address_token = tok.Token{ .tokType = .ADDRESS, .value = label_token.value };
            try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, address_token);

            // [DEBUG OUTPUT] output anonymous label reference substitution details
            if (flags.print_anon_labels) {
                const sign: u8 = if (token.tokType == .BACKWARD_LABEL_REF) '-' else '+';
                std.debug.print("\nresulting relative label fetch:\n", .{});
                std.debug.print("relative index: {c}{}\n", .{ sign, token.value });
                std.debug.print("name: \"{?s}\"\n", .{label_token.identKey});
                std.debug.print("current rom address: 0x{X:0>8}\n", .{rom_vector.items.len});
                std.debug.print("fetched rom address: 0x{X:0>8}\n", .{address_token.value});
            }

            continue;
        }

        // identifier symbol substitution
        if (token.tokType == .IDENTIFIER) {
            if (symTable.Get(token.identKey)) |symbol| {
                switch (symbol.value) {
                    .label => {
                        if (isFirstPass) {
                            // first pass labels need to be added to the symbol table first
                            // so, to preserve bytespace, replace with dummy placeholder addresses
                            const placeholder = tok.Token{ .tokType = .ADDRESS, .value = 0 };
                            try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, placeholder);
                        } else {
                            // second pass labels have all been generated and may be
                            // substituted safely
                            try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, symbol.value.label);
                        }
                    },
                    // all macros need to be processed before this stage is ever reached
                    .macro => return error.UnexpandedMacro,
                    .define => return error.UnexpandedDefine,
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

    // copy variable width input into fixed width local buffer,
    // this is a less versatile, but overall safer approach.
    // *deprecated behavior* Exclude the instruction line newline token too.
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
        try vec.append(0);
    } else if (t[0].tokType == .SYSCALL) {
        // "SYSCALL"
        // Initiate a (virtual) machine system call
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.SYSTEMCALL));
    } else if (t[0].tokType == .BRK) {
        // "BRK"
        // Break, exits execution
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.BRK));
    } else if (t[0].tokType == .NOP) {
        // "NOP"
        // No operation, do nothing, preferably with some noticeable delay
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.NOP));
    } else if (t[0].tokType == .CLC) {
        // "CLC"
        // Clear carry, set the carry flag to 0
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CLC));
    } else if (t[0].tokType == .SEC) {
        // "SEC"
        // Set carry, set the carry flag to 1
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.SEC));
    } else if (t[0].tokType == .RET) {
        // "RET"
        // Return from subroutine
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.RET));
    } else if (t[0].tokType == .LDA and t[1].tokType == .LITERAL) {
        // "LDA 0x42"
        // Load literal into accumulator
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.LDA_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDX and t[1].tokType == .LITERAL) {
        // "LDX 0x42"
        // Load literal into X index
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.LDX_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDY and t[1].tokType == .LITERAL) {
        // "LDY 0x42"
        // Load literal into Y index
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.LDY_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .LDA and t[1].tokType == .ADDRESS) {
        // "LDA $0x1337"
        // Load value from address into accumulator
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.LDA_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .LDX and t[1].tokType == .ADDRESS) {
        // "LDX $0x1337"
        // Load value from address into X index
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.LDX_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .LDY and t[1].tokType == .ADDRESS) {
        // "LDY $0x1337"
        // Load value from address into Y index
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.LDY_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .LDA and t[1].tokType == .X) {
        // "LDA X"
        // Transfer the contents of the X index into the accumulator
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.LDA_X));
    } else if (t[0].tokType == .LDA and t[1].tokType == .Y) {
        // "LDA Y"
        // Transfer the contents of the Y index into the accumulator
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.LDA_Y));
    } else if (t[0].tokType == .LDX and t[1].tokType == .A) {
        // "LDX A"
        // Transfer the contents of the accumulator into the X index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.LDX_A));
    } else if (t[0].tokType == .LDX and t[1].tokType == .Y) {
        // "LDX Y"
        // Transfer the contents of the Y index into the X index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.LDX_Y));
    } else if (t[0].tokType == .LDY and t[1].tokType == .A) {
        // "LDY A"
        // Transfer the contents of the accumulator into the Y index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.LDY_A));
    } else if (t[0].tokType == .LDY and t[1].tokType == .X) {
        // "LDY X"
        // Transfer the contents of the X index into the Y index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.LDY_X));
    } else if (t[0].tokType == .LDA and t[1].tokType == .ADDRESS and t[2].tokType == .X) {
        // "LDA $0x1337 X"
        // Load value from address indexed by X into the accumulator
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.LDA_ADDR_X));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .LDA and t[1].tokType == .ADDRESS and t[2].tokType == .Y) {
        // "LDA $0x1337 Y"
        // Load value from address indexed by X into the accumulator
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.LDA_ADDR_Y));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .STA and t[1].tokType == .ADDRESS) {
        // "STA $0x1337"
        // Store accumulator value into address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.STA_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .STX and t[1].tokType == .ADDRESS) {
        // "STX $0x1337"
        // Store X index value into address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.STX_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .STY and t[1].tokType == .ADDRESS) {
        // "STY $0x1337"
        // Store Y index value into address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.STY_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .JMP and t[1].tokType == .ADDRESS) {
        // "JMP Foo"
        // Jump to rom address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.JMP_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .JSR and t[1].tokType == .ADDRESS) {
        // "JSR Foo"
        // Save current PC and jump to rom address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.JSR_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .X) {
        // "CMP A X"
        // Compares the accumulator to the X index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CMP_A_X));
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .Y) {
        // "CMP A Y"
        // Compares the accumulator to the Y index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CMP_A_Y));
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .LITERAL) {
        // "CMP A 0x42"
        // Compares the accumulator to a literal
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.CMP_A_LIT));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .ADDRESS) {
        // "CMP A $0x1337"
        // Compares the accumulator to the value inside an address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.CMP_A_ADDR));
        try Append_Generic_Limited(vec, t[2].value, 2);
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .A) {
        // "CMP X A"
        // Compares the X index to the accumulator
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CMP_X_A));
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .Y) {
        // "CMP X Y"
        // Compares the X index to the Y index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CMP_X_Y));
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .LITERAL) {
        // "CMP X 0x42"
        // Compares the X index to a literal
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.CMP_X_LIT));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .ADDRESS) {
        // "CMP X $0x1337"
        // Compares the X index to the value inside an address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.CMP_X_ADDR));
        try Append_Generic_Limited(vec, t[2].value, 2);
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .X) {
        // "CMP Y X"
        // Compares the Y index to the X index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CMP_Y_X));
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .A) {
        // "CMP Y A"
        // Compares the Y index to the accumulator
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.CMP_Y_A));
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .LITERAL) {
        // "CMP Y 0x42"
        // Compares the Y index to a literal
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.CMP_Y_LIT));
        try Append_Generic(vec, t[2].value);
    } else if (t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .ADDRESS) {
        // "CMP Y $0x1337"
        // Compares the Y index to the value inside an address
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.CMP_Y_ADDR));
        try Append_Generic_Limited(vec, t[2].value, 2);
    } else if (t[0].tokType == .BCS and t[1].tokType == .ADDRESS) {
        // "BCS Foo"
        // Branch if carry set
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BCS_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BCC and t[1].tokType == .ADDRESS) {
        // "BCC Foo"
        // Branch if carry clear
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BCC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BEQ and t[1].tokType == .ADDRESS) {
        // "BEQ Foo"
        // Branch if equal
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BEQ_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BNE and t[1].tokType == .ADDRESS) {
        // "BNE Foo"
        // Branch if not equal
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BNE_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BMI and t[1].tokType == .ADDRESS) {
        // "BMI Foo"
        // Branch if minus
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BMI_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BPL and t[1].tokType == .ADDRESS) {
        // "BPL Foo"
        // Branch if plus
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BPL_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BVS and t[1].tokType == .ADDRESS) {
        // "BVS Foo"
        // Branch if overflow set
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BVS_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .BVC and t[1].tokType == .ADDRESS) {
        // "BVC Foo"
        // Branch if overflow clear
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.BVC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .ADD and t[1].tokType == .LITERAL) {
        // "ADD 0x42"
        // accumulator += (literal + carry)
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.ADD_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .ADD and t[1].tokType == .ADDRESS) {
        // "ADD $0x1337"
        // accumulator += (value in address + carry)
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.ADD_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .ADD and t[1].tokType == .X) {
        // "ADD X"
        // accumulator += (X index + carry)
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.ADD_X));
    } else if (t[0].tokType == .ADD and t[1].tokType == .Y) {
        // "ADD Y"
        // accumulator += (Y index + carry)
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.ADD_Y));
    } else if (t[0].tokType == .SUB and t[1].tokType == .LITERAL) {
        // "SUB 0x42"
        // accumulator -= (literal + carry - 1)
        // instruction byte len = 1 + 4
        try vec.append(@intFromEnum(Opcode.SUB_LIT));
        try Append_Generic(vec, t[1].value);
    } else if (t[0].tokType == .SUB and t[1].tokType == .ADDRESS) {
        // "SUB $0x1337"
        // accumulator -= (value in address + carry - 1)
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.SUB_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .SUB and t[1].tokType == .X) {
        // "SUB X"
        // accumulator -= (X index + carry - 1)
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.SUB_X));
    } else if (t[0].tokType == .SUB and t[1].tokType == .Y) {
        // "SUB Y"
        // accumulator -= (Y index + carry - 1)
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.SUB_Y));
    } else if (t[0].tokType == .INC and t[1].tokType == .A) {
        // "INC A"
        // Increment the accumulator by one
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.INC_A));
    } else if (t[0].tokType == .INC and t[1].tokType == .X) {
        // "INC X"
        // Increment the X index by one
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.INC_X));
    } else if (t[0].tokType == .INC and t[1].tokType == .Y) {
        // "INC Y"
        // Increment the Y index by one
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.INC_Y));
    } else if (t[0].tokType == .INC and t[1].tokType == .ADDRESS) {
        // "INC $0x1337"
        // Increment the value inside the address by one
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.INC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .DEC and t[1].tokType == .A) {
        // "DEC A"
        // Decrement the accumulator by one
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.DEC_A));
    } else if (t[0].tokType == .DEC and t[1].tokType == .X) {
        // "DEC X"
        // Decrement the X index by one
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.DEC_X));
    } else if (t[0].tokType == .DEC and t[1].tokType == .Y) {
        // "DEC Y"
        // Decrement the Y index by one
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.DEC_Y));
    } else if (t[0].tokType == .DEC and t[1].tokType == .ADDRESS) {
        // "DEC $0x1337"
        // Decrement the value inside the address by one
        // instruction byte len = 1 + 2
        try vec.append(@intFromEnum(Opcode.DEC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if (t[0].tokType == .PUSH and t[1].tokType == .A) {
        // "PUSH A"
        // Pushes the value of the accumulator to the stack
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.PUSH_A));
    } else if (t[0].tokType == .PUSH and t[1].tokType == .X) {
        // "PUSH X"
        // Pushes the value of the X index to the stack
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.PUSH_X));
    } else if (t[0].tokType == .PUSH and t[1].tokType == .Y) {
        // "PUSH Y"
        // Pushes the value of the Y index to the stack
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.PUSH_Y));
    } else if (t[0].tokType == .POP and t[1].tokType == .A) {
        // "POP A"
        // Pops a value from the stack into the accumulator
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.POP_A));
    } else if (t[0].tokType == .POP and t[1].tokType == .X) {
        // "POP X"
        // Pops a value from the stack into the X index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.POP_X));
    } else if (t[0].tokType == .POP and t[1].tokType == .Y) {
        // "POP_Y"
        // Pops a value from the stack into the Y index
        // instruction byte len = 1
        try vec.append(@intFromEnum(Opcode.POP_Y));
    } else {
        std.debug.print("ERROR: unknown opcode!\n", .{});
        // append newline for proper token array printing
        if (t[line.len - 1].tokType != .LINEFINISH)
            t[line.len] = tok.Token{ .tokType = .LINEFINISH };
        tok.Print_Token_Array(t[0 .. line.len + 1]);
    }
}

fn Debug_Print_Rom(rom: []u8, flags: clap.Flags) void {
    std.debug.print("\nROM dump:\n", .{});
    if (flags.debug_mode) {
        std.debug.print("------+------+---------------------------\n", .{});
        std.debug.print(" addr | val  | value type\n", .{});
        std.debug.print("------+------+---------------------------\n", .{});
        const entry_point: u16 = std.mem.readInt(u16, rom[2..4], .little);
        const debug_signal: u8 = 0xFF;
        var debug_contents_mode: bool = false;
        var debug_first_byte: bool = false;
        var len_counter: i32 = 0;
        var opcode: Opcode = undefined;
        // debug mode output
        for (rom, 0..) |byte, i| {
            if (i < 16) {
                len_counter = 0;
                switch (i) {
                    0x0 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - magic number\n", .{ i, byte }),
                    0x1 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - assembly version\n", .{ i, byte }),
                    0x2 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - entry point (low byte)\n", .{ i, byte }),
                    0x3 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - entry point (high byte)\n", .{ i, byte }),
                    0x4 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0x5 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0x6 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0x7 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0x8 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0x9 => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0xA => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0xB => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0xC => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0xD => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0xE => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - free space\n", .{ i, byte }),
                    0xF => std.debug.print("0x{X:0>4}| 0x{X:0>2} | header - debug mode enable\n", .{ i, byte }),
                    else => unreachable,
                }
                continue;
            }

            if (len_counter >= 0) {
                // invert debug contents mode state
                if (byte == debug_signal) {
                    debug_contents_mode = !debug_contents_mode;
                }
                // what to do the moment debug signal ends
                if (byte == debug_signal and debug_contents_mode == false) {
                    std.debug.print("0x{X:0>4}| 0x{X:0>2} | end debug info\n", .{ i, byte });
                    continue;
                }
                // what to do the moment debug signal begins
                if (byte == debug_signal and debug_contents_mode == true) {
                    std.debug.print("0x{X:0>4}| 0x{X:0>2} | begin debug info\n", .{ i, byte });
                    debug_first_byte = true;
                    continue;
                }
                if (debug_contents_mode and debug_first_byte == true) {
                    std.debug.print("0x{X:0>4}| 0x{X:0>2} | debug info type: {s}\n", .{ i, byte, std.enums.tagName(DebugMetadataType, @enumFromInt(byte)).? });
                    debug_first_byte = false;
                    continue;
                }
                if (debug_contents_mode and debug_first_byte == false) {
                    std.debug.print("0x{X:0>4}| 0x{X:0>2} | \'{c}\'\n", .{ i, byte, byte });
                    debug_first_byte = false;
                    continue;
                }

                if (i < entry_point) {
                    len_counter = 0;
                    std.debug.print("0x{X:0>4}| 0x{X:0>2} | data\n", .{ i, byte });
                    continue;
                } else {
                    opcode = @enumFromInt(byte);
                    len_counter -= opcode.Instruction_Byte_Length();
                    std.debug.print("0x{X:0>4}| 0x{X:0>2} | opcode: {s}\n", .{ i, byte, std.enums.tagName(Opcode, @enumFromInt(byte)).? });
                }
            } else {
                std.debug.print("0x{X:0>4}| 0x{X:0>2} | opcode parameters\n", .{ i, byte });
            }

            len_counter += 1;
        }
    } else {
        std.debug.print("------+------\n", .{});
        std.debug.print(" addr | val\n", .{});
        std.debug.print("------+------\n", .{});
        // non debug mode output
        for (rom, 0..) |byte, i|
            std.debug.print("0x{X:0>4}| 0x{X:0>2}\n", .{ i, byte });
    }
}

/// Using low-endian, sequentially append the bytes of a value to an u8 arraylist
fn Append_Generic(vector: *std.ArrayList(u8), value: anytype) !void {
    const byte_array = std.mem.toBytes(value);
    try vector.appendSlice(&byte_array);
}

/// Using low-endian, sequentially append the first n bytes of a value to an u8 arraylist
fn Append_Generic_Limited(vector: *std.ArrayList(u8), value: anytype, comptime n: usize) !void {
    comptime std.debug.assert(n <= @sizeOf(@TypeOf(value)));
    const byte_array = std.mem.toBytes(value);
    try vector.appendSlice(byte_array[0..n]);
}

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "byte vector appending" {
    const num = @as(u32, 0xFFEEDDCC);
    var vector = std.ArrayList(u8).init(std.testing.allocator);
    defer vector.deinit();

    try Append_Generic(&vector, num);

    try std.testing.expectEqual(@as(usize, 4), vector.items.len);
    try std.testing.expectEqual(@as(u8, 0xCC), vector.items[0]);
    try std.testing.expectEqual(@as(u8, 0xDD), vector.items[1]);
    try std.testing.expectEqual(@as(u8, 0xEE), vector.items[2]);
    try std.testing.expectEqual(@as(u8, 0xFF), vector.items[3]);
}

test "limited byte vector appending" {
    const num = @as(u64, 0xDEADBEEF03020100);
    var vector = std.ArrayList(u8).init(std.testing.allocator);
    defer vector.deinit();

    try Append_Generic_Limited(&vector, num, 3);

    try std.testing.expectEqual(@as(usize, 3), vector.items.len);
    try std.testing.expectEqual(@as(u8, 0x00), vector.items[0]);
    try std.testing.expectEqual(@as(u8, 0x01), vector.items[1]);
    try std.testing.expectEqual(@as(u8, 0x02), vector.items[2]);

    // error case tests are not needed since they're caught at the
    // compile time assert inside the function.
}

test "assert rom header data" {
    var vector = std.ArrayList(u8).init(std.testing.allocator);
    defer vector.deinit();

    const rom_header = specs.Header{
        .magic_number = specs.rom_magic_number,
        .language_version = 9,
        .entry_point = specs.Header.default_entry_point,
        .debug_mode = true,
    };
    const rom_vector_bytes = rom_header.Parse_To_Byte_Array();
    try vector.appendSlice(&rom_vector_bytes);

    const magic_number: u8 = vector.items[0];
    try std.testing.expectEqual(specs.rom_magic_number, magic_number);
    const version: u8 = vector.items[1];
    try std.testing.expectEqual(@as(u8, 0x09), version);
    const entry_point: u16 = std.mem.readInt(u16, vector.items[2..4], .little);
    try std.testing.expectEqual(@as(u16, 0x0010), entry_point);

    // must be 16 bytes long, where $0xF is the last available header byte
    try std.testing.expectEqual(specs.rom_header_bytelen, vector.items.len);
}
