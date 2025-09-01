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
const warn = @import("shared").warn;
const streams = @import("shared").streams;

const Opcode = specs.Opcode;
const DebugMetadataType = specs.DebugMetadataType;

const ArrayList = std.array_list.Managed;

pub fn Generate_Rom(allocator: std.mem.Allocator, flags: clap.Flags, symTable: *sym.SymbolTable, expandedTokens: []const tok.Token) ![]u8 {
    // {..., ACTUAL_LAST_TOKEN, $, EOF, $}
    const last_token = expandedTokens[expandedTokens.len - 4];
    if (last_token.tokType == .LABEL or last_token.tokType == .ANON_LABEL) {
        warn.Error_Message("label pointing to EOF causes undefined behavior!", .{});
        return error.LastTokenIsLabel;
    }

    const first_pass = try Codegen(true, allocator, flags, symTable, expandedTokens);
    allocator.free(first_pass);
    const second_pass = try Codegen(false, allocator, flags, symTable, expandedTokens);

    // [DEBUG OUTPUT] print rom bytes
    if (flags.log_rom_bytes) {
        Debug_Print_Rom(second_pass);
    }

    return second_pass;
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

/// First pass: result is discarded as it is only used to determine LABEL address locations
/// relative to its location in rom.
/// Second pass: now that the LABEL locations have been defined, generate the actual usable rom.
fn Codegen(isFirstPass: bool, allocator: std.mem.Allocator, flags: clap.Flags, symTable: *sym.SymbolTable, expandedTokens: []const tok.Token) ![]u8 {
    var rom_vector = ArrayList(u8).init(allocator);
    defer rom_vector.deinit();

    // avoid needless micro allocations
    try rom_vector.ensureTotalCapacity(0xFFFF);

    // build the instruction line, one token at a time for proper symbol substitution
    var tokenBuffer: [64]tok.Token = undefined;
    var tokenBuffsize: usize = 0;

    // for ".db", ".dw" and ".dd" modes
    var activeByteDefiner: tok.TokenType = .UNDEFINED;

    // entry point, as is defined by the rom header
    var rom_header_entry_point = specs.Header.default_entry_point;
    var passed_START_label = false;

    // for naming the anonymous labels
    var anon_label_counter: usize = 0;

    // begin the rom with its respective 16 bytes of header bytes
    const rom_header = specs.Header{
        .magic_number = specs.Header.required_magic_number,
        .language_version = specs.current_assembly_version,
        .entry_point = rom_header_entry_point,
        .debug_mode = flags.debug_mode,
    };
    try rom_vector.appendSlice(&rom_header.Parse_To_Byte_Array());

    // for every token loop
    for (expandedTokens) |token| {
        if (tokenBuffsize >= 8)
            return error.InstructionLineTooLong;
        if (token.tokType == tok.TokenType.ENDOFFILE)
            break;

        // ignore LABELs as their symbols and tokens should be already processed and stripped at this stage
        // unless debug mode is active, if so, insert the labels metadata
        if (token.tokType == .LABEL or token.tokType == .ANON_LABEL) {
            // insert label name metadata, if applicable
            if (flags.debug_mode and passed_START_label) {
                // insert label debug metadata
                try rom_vector.append(@intFromEnum(Opcode.DEBUG_METADATA_SIGNAL));
                try rom_vector.append(@intFromEnum(DebugMetadataType.LABEL_NAME));
                // 0xFF LABEL_NAME 'LabelName' 0xFF
                if (token.tokType == .LABEL)
                    try rom_vector.appendSlice(token.identKey.?);
                // 0xFF LABEL_NAME 'ANON_LABEL' 0xFF
                if (token.tokType == .ANON_LABEL) {
                    var buf: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "ANON_LABEL_{}", .{anon_label_counter}) catch unreachable;
                    try rom_vector.appendSlice(str);
                    anon_label_counter += 1;
                }
                try rom_vector.append(@intFromEnum(Opcode.DEBUG_METADATA_SIGNAL));
            }

            // check if it's the entry point label
            if (token.tokType == .LABEL and std.mem.eql(u8, token.identKey.?, "_START")) {
                passed_START_label = true;
                rom_header_entry_point = @truncate(rom_vector.items.len);
                std.mem.copyForwards(u8, rom_vector.items[2..], &std.mem.toBytes(rom_header_entry_point));
            }

            // the main purpose of the existance of the first pass:
            // resolve the label address and put it in the symbol table
            if (isFirstPass and token.tokType == .LABEL) {
                const current_address_value_token: tok.Token = tok.Token{
                    .tokType = .ADDRESS,
                    .identKey = try utils.Copy_Of_String(allocator, token.identKey.?),
                    .value = @truncate(rom_vector.items.len),
                };
                const label_symbol = sym.Symbol{
                    .name = try utils.Copy_Of_String(allocator, token.identKey.?),
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
                    .identKey = try utils.Copy_Of_String(allocator, slice),
                    .value = @truncate(rom_vector.items.len),
                };
                const anonlabel_symbol = sym.Symbol{
                    .name = try utils.Copy_Of_String(allocator, slice),
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
            try Process_Instruction_Line(tokenBuffer[0..tokenBuffsize], &rom_vector, isFirstPass);
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
                warn.Error_Message("Token \"{s}\" is not a valid value!", .{std.enums.tagName(tok.TokenType, token.tokType).?});
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
            if (flags.log_anon_labels) {
                const sign: u8 = if (token.tokType == .BACKWARD_LABEL_REF) '-' else '+';
                streams.bufStdoutPrint("\nresulting relative label fetch:\n", .{}) catch unreachable;
                streams.bufStdoutPrint("relative index: {c}{}\n", .{ sign, token.value }) catch unreachable;
                streams.bufStdoutPrint("name: \"{?s}\"\n", .{label_token.identKey}) catch unreachable;
                streams.bufStdoutPrint("current rom address: 0x{X:0>8}\n", .{rom_vector.items.len}) catch unreachable;
                streams.bufStdoutPrint("fetched rom address: 0x{X:0>8}\n", .{address_token.value}) catch unreachable;
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
                warn.Error_Message("unknown identifier: \"{s}\"", .{token.identKey.?});
                return error.UnknownIdentifier;
            }
        }

        try utils.Append_Element_To_Buffer(tok.Token, &tokenBuffer, &tokenBuffsize, token);
    }

    return rom_vector.toOwnedSlice();
}

/// Append the bytecode instruction respective to the input instruction line tokens
fn Process_Instruction_Line(line: []tok.Token, vec: *ArrayList(u8), is_first_pass: bool) !void {
    // 4 token limit for each instruction line
    const buffsize: usize = 4;
    if (line.len >= buffsize)
        return error.InstructionLineTooLong;

    // copy variable width input into fixed width local buffer,
    // this is a less versatile, but overall safer approach.
    // *deprecated behavior* Exclude the instruction line newline token too.
    var t: [buffsize]tok.Token = .{tok.Token.Init()} ** buffsize;
    var t_len: usize = 0;
    for (0..line.len) |i| {
        if (line[i].tokType == .LINEFINISH)
            break;
        t_len += 1;
        t[i] = line[i];
    }

    // this "manual" if chain is necessary due to a variety of issues from other approaches,
    // unmatched lexed strings being automatically turned to identifiers is the biggest of them.
    // this may or may not be redesigned in the future. Keep in mind i am incredibly lazy...
    if (t[0].tokType == .ERROR) {
        // for debugging purposes only
        try vec.append(0);
    } else if ((t_len == 1) and t[0].tokType == .SYSCALL) {
        try vec.append(@intFromEnum(Opcode.SYSTEMCALL));
    } else if ((t_len == 2) and t[0].tokType == .STRIDE and t[1].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.STRIDE_LIT));
        try Append_Generic(vec, @as(u8, @truncate(t[1].value)));
    } else if ((t_len == 1) and t[0].tokType == .BRK) {
        try vec.append(@intFromEnum(Opcode.BRK));
    } else if ((t_len == 1) and t[0].tokType == .NOP) {
        try vec.append(@intFromEnum(Opcode.NOP));
    } else if ((t_len == 1) and t[0].tokType == .CLC) {
        try vec.append(@intFromEnum(Opcode.CLC));
    } else if ((t_len == 1) and t[0].tokType == .SEC) {
        try vec.append(@intFromEnum(Opcode.SEC));
    } else if ((t_len == 1) and t[0].tokType == .RET) {
        try vec.append(@intFromEnum(Opcode.RET));
    } else if ((t_len == 2) and t[0].tokType == .LDA and t[1].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.LDA_LIT));
        try Append_Generic(vec, t[1].value);
    } else if ((t_len == 2) and t[0].tokType == .LDX and t[1].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.LDX_LIT));
        try Append_Generic(vec, t[1].value);
    } else if ((t_len == 2) and t[0].tokType == .LDY and t[1].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.LDY_LIT));
        try Append_Generic(vec, t[1].value);
    } else if ((t_len == 2) and t[0].tokType == .LDA and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.LDA_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .LDX and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.LDX_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .LDY and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.LDY_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .LDA and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.LDA_X));
    } else if ((t_len == 2) and t[0].tokType == .LDA and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.LDA_Y));
    } else if ((t_len == 2) and t[0].tokType == .LDX and t[1].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.LDX_A));
    } else if ((t_len == 2) and t[0].tokType == .LDX and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.LDX_Y));
    } else if ((t_len == 2) and t[0].tokType == .LDY and t[1].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.LDY_A));
    } else if ((t_len == 2) and t[0].tokType == .LDY and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.LDY_X));
    } else if ((t_len == 3) and t[0].tokType == .LDA and t[1].tokType == .ADDRESS and t[2].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.LDA_ADDR_X));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 3) and t[0].tokType == .LDA and t[1].tokType == .ADDRESS and t[2].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.LDA_ADDR_Y));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .LEA and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.LEA_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .LEX and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.LEX_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .LEY and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.LEY_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .STA and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.STA_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .STX and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.STX_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .STY and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.STY_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .JMP and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.JMP_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .JSR and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.JSR_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.CMP_A_X));
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.CMP_A_Y));
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.CMP_A_LIT));
        try Append_Generic(vec, t[2].value);
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .A and t[2].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.CMP_A_ADDR));
        try Append_Generic_Limited(vec, t[2].value, 2);
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.CMP_X_A));
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.CMP_X_Y));
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.CMP_X_LIT));
        try Append_Generic(vec, t[2].value);
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .X and t[2].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.CMP_X_ADDR));
        try Append_Generic_Limited(vec, t[2].value, 2);
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.CMP_Y_X));
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.CMP_Y_A));
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.CMP_Y_LIT));
        try Append_Generic(vec, t[2].value);
    } else if ((t_len == 3) and t[0].tokType == .CMP and t[1].tokType == .Y and t[2].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.CMP_Y_ADDR));
        try Append_Generic_Limited(vec, t[2].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BCS and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BCS_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BCC and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BCC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BEQ and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BEQ_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BNE and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BNE_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BMI and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BMI_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BPL and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BPL_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BVS and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BVS_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .BVC and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.BVC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .ADD and t[1].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.ADD_LIT));
        try Append_Generic(vec, t[1].value);
    } else if ((t_len == 2) and t[0].tokType == .ADD and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.ADD_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .ADD and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.ADD_X));
    } else if ((t_len == 2) and t[0].tokType == .ADD and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.ADD_Y));
    } else if ((t_len == 2) and t[0].tokType == .SUB and t[1].tokType == .LITERAL) {
        try vec.append(@intFromEnum(Opcode.SUB_LIT));
        try Append_Generic(vec, t[1].value);
    } else if ((t_len == 2) and t[0].tokType == .SUB and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.SUB_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .SUB and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.SUB_X));
    } else if ((t_len == 2) and t[0].tokType == .SUB and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.SUB_Y));
    } else if ((t_len == 2) and t[0].tokType == .INC and t[1].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.INC_A));
    } else if ((t_len == 2) and t[0].tokType == .INC and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.INC_X));
    } else if ((t_len == 2) and t[0].tokType == .INC and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.INC_Y));
    } else if ((t_len == 2) and t[0].tokType == .INC and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.INC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .DEC and t[1].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.DEC_A));
    } else if ((t_len == 2) and t[0].tokType == .DEC and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.DEC_X));
    } else if ((t_len == 2) and t[0].tokType == .DEC and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.DEC_Y));
    } else if ((t_len == 2) and t[0].tokType == .DEC and t[1].tokType == .ADDRESS) {
        try vec.append(@intFromEnum(Opcode.DEC_ADDR));
        try Append_Generic_Limited(vec, t[1].value, 2);
    } else if ((t_len == 2) and t[0].tokType == .PUSH and t[1].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.PUSH_A));
    } else if ((t_len == 2) and t[0].tokType == .PUSH and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.PUSH_X));
    } else if ((t_len == 2) and t[0].tokType == .PUSH and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.PUSH_Y));
    } else if ((t_len == 2) and t[0].tokType == .POP and t[1].tokType == .A) {
        try vec.append(@intFromEnum(Opcode.POP_A));
    } else if ((t_len == 2) and t[0].tokType == .POP and t[1].tokType == .X) {
        try vec.append(@intFromEnum(Opcode.POP_X));
    } else if ((t_len == 2) and t[0].tokType == .POP and t[1].tokType == .Y) {
        try vec.append(@intFromEnum(Opcode.POP_Y));
    } else {
        // avoid twice of the same error printed to stdout
        if (is_first_pass) {
            warn.Error_Message("unknown opcode!", .{});
            // append newline for proper token array printing
            if (t[line.len - 1].tokType != .LINEFINISH)
                t[line.len] = tok.Token{ .tokType = .LINEFINISH };
            tok.Print_Token_Array(t[0 .. line.len + 1]);
        }
    }
}

fn Debug_Print_Rom(rom: []u8) void {
    var i: u16 = 0;
    streams.bufStdoutPrint("\nGENERATED ROM BYTES:", .{}) catch unreachable;
    while (true) : (i += 1) {
        if (i % 16 == 0) {
            if (i >= rom.len) break;
            streams.bufStdoutPrint("\n${X:0>4}:", .{i}) catch unreachable;
        }
        if (i < rom.len) {
            streams.bufStdoutPrint(" {x:0>2}", .{rom[i]}) catch unreachable;
        } else {
            streams.bufStdoutPrint(" ..", .{}) catch unreachable;
        }
    }
    streams.bufStdoutPrint("\n", .{}) catch unreachable;
}

/// Using low-endian, sequentially append the bytes of a value to an u8 arraylist
fn Append_Generic(vector: *ArrayList(u8), value: anytype) !void {
    const byte_array = std.mem.toBytes(value);
    try vector.appendSlice(&byte_array);
}

/// Using low-endian, sequentially append the first n bytes of a value to an u8 arraylist
fn Append_Generic_Limited(vector: *ArrayList(u8), value: anytype, comptime n: usize) !void {
    comptime std.debug.assert(n <= @sizeOf(@TypeOf(value)));
    const byte_array = std.mem.toBytes(value);
    try vector.appendSlice(byte_array[0..n]);
}

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "byte vector appending" {
    const num = @as(u32, 0xFFEEDDCC);
    var vector = ArrayList(u8).init(std.testing.allocator);
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
    var vector = ArrayList(u8).init(std.testing.allocator);
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
    var vector = ArrayList(u8).init(std.testing.allocator);
    defer vector.deinit();

    const rom_header = specs.Header{
        .magic_number = specs.Header.required_magic_number,
        .language_version = 9,
        .entry_point = specs.Header.default_entry_point,
        .debug_mode = true,
    };
    const rom_vector_bytes = rom_header.Parse_To_Byte_Array();
    try vector.appendSlice(&rom_vector_bytes);

    const magic_number: u8 = vector.items[0];
    try std.testing.expectEqual(specs.Header.required_magic_number, magic_number);
    const version: u8 = vector.items[1];
    try std.testing.expectEqual(@as(u8, 0x09), version);
    const entry_point: u16 = std.mem.readInt(u16, vector.items[2..4], .little);
    try std.testing.expectEqual(@as(u16, 0x0000), entry_point);

    // must be 16 bytes long, where $0xF is the last available header byte
    try std.testing.expectEqual(specs.bytelen.header, vector.items.len);
}
