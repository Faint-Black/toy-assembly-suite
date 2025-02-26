//=============================================================//
//                                                             //
//                       PRE-PROCESSOR                         //
//                                                             //
//   Responsible for dealing with the stripping and expansion  //
//  of preprocessor definitions, like macros and repeats.      //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("utils.zig");
const tok = @import("token.zig");
const sym = @import("symbol.zig");

/// Removes, replaces and expands preprocessor instructions,
/// like macros.
pub fn Preprocessor_Expansion(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, lexedTokens: []const tok.Token) ![]tok.Token {
    // debug information printing
    std.debug.print("\nLexed tokens:\n", .{});
    tok.Print_Token_Array(lexedTokens);

    // removes preprocessor definitions and adds them to the global symbol table.
    // this token array is a complete allocated and intermediary copy
    // and must be completely destroyed before this function exits
    const stripped_tokens = try First_Pass(allocator, symTable, lexedTokens);
    defer allocator.free(stripped_tokens);
    defer tok.Destroy_Tokens_Contents(allocator, stripped_tokens);

    // debug information printing
    std.debug.print("\nStripped tokens:\n", .{});
    tok.Print_Token_Array(stripped_tokens);

    // expands macro identifiers and returns a new token array.
    // this token array is a complete allocated copy
    const expanded_tokens = try Second_Pass(allocator, symTable, stripped_tokens);

    // debug information printing
    std.debug.print("\nExpanded tokens:\n", .{});
    tok.Print_Token_Array(expanded_tokens);

    return expanded_tokens;
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

/// Removes all the macro definition tokens and adds them to the symbol registry,
/// also adds dummy LABEL symbols which enable forward referencing
fn First_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();
    var macro_vector = std.ArrayList(tok.Token).init(allocator);
    defer macro_vector.deinit();

    var macro_building_mode = false;
    for (tokens) |token| {
        // dummy label creation, for forward referencing purposes
        if (token.tokType == .LABEL) {
            const label_symbol = sym.Symbol{ .name = try utils.Copy_Of_ConstString(allocator, token.identKey.?), .value = .{ .label = tok.Token.Init() } };
            try symTable.*.Add(label_symbol);
        }

        if (token.tokType == .MACRO) {
            if (macro_building_mode == true) {
                std.log.err("Cannot define a macro inside another macro!", .{});
                return error.BadMacro;
            }
            macro_building_mode = true;
            continue;
        }
        if (token.tokType == .ENDMACRO) {
            if (macro_building_mode == false) {
                std.log.err("No macro to end!", .{});
                return error.BadMacro;
            }
            macro_building_mode = false;
            continue;
        }

        // when you forget to add .endmacro at the end
        if (token.tokType == .ENDOFFILE and macro_building_mode == true) {
            std.log.err("Found EOF while building macro!", .{});
            return error.BadMacro;
        }

        // add token to macro token buffer
        if (macro_building_mode == true) {
            try macro_vector.append(try token.Copy(allocator));
            continue;
        }

        // add built macro to symbol table
        if (macro_building_mode == false and macro_vector.items.len > 0) {
            // assert if macro was given a valid name
            if (macro_vector.items[0].identKey == null)
                return error.NamelessMacro;
            // assert if macro has a newline after the macro name
            if (macro_vector.items[1].tokType != .LINEFINISH)
                return error.BadName;

            // crop macro name and newline
            const macro_name = macro_vector.orderedRemove(0).identKey.?;
            _ = macro_vector.orderedRemove(0);

            var macro_symbol: sym.Symbol = undefined;
            macro_symbol.name = macro_name;
            macro_symbol.value = .{ .macro = try macro_vector.toOwnedSlice() };
            try symTable.*.Add(macro_symbol);
        }

        try token_vector.append(try token.Copy(allocator));
    }

    if (macro_vector.items.len > 0) {
        std.log.err("Unflushed macro!", .{});
        return error.BadMacro;
    }

    return token_vector.toOwnedSlice();
}

/// unwraps the macros identifiers into a new token array
fn Second_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();

    for (tokens) |token| {
        if (token.tokType == .IDENTIFIER) {
            const symbol = symTable.*.Get(token.identKey);

            // pay no mind to the missing identifier
            if (symbol == null) {
                try token_vector.append(try token.Copy(allocator));
                continue;
            }

            if (symbol.?.value == .macro) {
                for (symbol.?.value.macro) |macroTok|
                    try token_vector.append(try macroTok.Copy(allocator));
                continue;
            }
        }
        try token_vector.append(try token.Copy(allocator));
    }

    return token_vector.toOwnedSlice();
}
